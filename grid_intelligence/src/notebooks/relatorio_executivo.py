# Databricks notebook source
# ruff: noqa: F821
"""Relatório executivo diário, consumindo somente entidades Gold."""

import json
import re
from datetime import date, datetime

from pyspark.sql import functions as F

dbutils.widgets.text("catalogo", "grid_dev")
dbutils.widgets.text("schema_gold", "gold")
dbutils.widgets.text("regiao", "Campinas")
dbutils.widgets.dropdown("usar_ia", "false", ["false", "true"])

catalogo = dbutils.widgets.get("catalogo")
schema_gold = dbutils.widgets.get("schema_gold")
regiao = dbutils.widgets.get("regiao").strip()
usar_ia = dbutils.widgets.get("usar_ia").lower() == "true"

if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", catalogo):
    raise ValueError("catalogo inválido")
if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", schema_gold):
    raise ValueError("schema_gold inválido")
if not regiao:
    raise ValueError("regiao não pode ser vazia")


def _table(name: str):
    return spark.table(f"{catalogo}.{schema_gold}.{name}")


def _json_value(value):
    if isinstance(value, (date, datetime)):
        return value.isoformat()
    return value


def _rows(df):
    return [{key: _json_value(value) for key, value in row.asDict().items()} for row in df.collect()]


painel = _table("painel_operacional_dia")
prioridade = _table("prioridade_inspecao_uc")
saude = _table("saude_cliente")

ultimo_dia = painel.agg(F.max("data_evento").alias("ultimo_dia")).first()["ultimo_dia"]
if ultimo_dia is None:
    raise RuntimeError("Não há movimento em gold.painel_operacional_dia; confira a carga Bronze e o pipeline.")

regiao_normalizada = regiao.casefold()
operacao = painel.where(
    (F.lower(F.col("municipio")) == F.lit(regiao_normalizada))
    & (F.col("data_evento") == F.lit(ultimo_dia))
)
if operacao.limit(1).count() == 0:
    regioes = [row["municipio"] for row in painel.select("municipio").distinct().orderBy("municipio").collect()]
    disponiveis = ", ".join(regioes) or "nenhuma"
    raise RuntimeError(
        f"Não há movimento para a região '{regiao}' no último dia com movimento ({ultimo_dia}). "
        f"Regiões disponíveis: {disponiveis}."
    )

ids_conjunto = [row["id_conjunto"] for row in operacao.select("id_conjunto").distinct().collect()]
ids_lit = F.array(*[F.lit(value) for value in ids_conjunto])

media_30d = (
    painel.where(
        F.array_contains(ids_lit, F.col("id_conjunto"))
        & (F.col("data_evento") >= F.date_sub(F.lit(ultimo_dia), 30))
        & (F.col("data_evento") < F.lit(ultimo_dia))
    )
    .groupBy("id_conjunto")
    .agg(F.avg("qtd_chamados").alias("media_chamados_30d"))
)

operacao_comparada = (
    operacao.join(media_30d, "id_conjunto", "left")
    .select(
        "id_conjunto",
        "nome_conjunto",
        "municipio",
        "data_evento",
        "qtd_interrupcoes",
        "uc_horas_interrompidas",
        "maior_duracao_horas",
        "causa_predominante",
        "qtd_chamados",
        "qtd_chamados_negativos",
        "qtd_chamados_risco_saude",
        "qtd_mencoes_ouvidoria",
        "media_chamados_30d",
        "acao_recomendada",
    )
    .orderBy(F.desc("qtd_chamados_risco_saude"), F.desc("qtd_chamados"), "id_conjunto")
)

prioridade_alta = (
    prioridade.where(F.array_contains(ids_lit, F.col("id_conjunto")) & (F.col("prioridade_inspecao") == "alta"))
    .groupBy("bairro")
    .agg(F.count("id_uc").alias("qtd_ucs_prioridade_alta"))
    .orderBy(F.desc("qtd_ucs_prioridade_alta"), "bairro")
)

clientes_ouvidoria = (
    saude.where(
        F.array_contains(ids_lit, F.col("id_conjunto"))
        & F.col("risco_ouvidoria").isin("alto", "medio")
    )
    .select(
        "id_cliente",
        "nome_conjunto",
        "bairro",
        "qtd_mencoes_ouvidoria",
        "qtd_chamados_risco_saude",
        "risco_ouvidoria",
    )
    .orderBy(F.desc("qtd_mencoes_ouvidoria"), F.desc("qtd_chamados_risco_saude"), "id_cliente")
    .limit(10)
)

metric_table = f"{catalogo}.{schema_gold}.continuidade_metricas"
metricas = spark.sql(
    f"""
    SELECT
      cm.`Conjunto` AS conjunto,
      cm.`Codigo do Conjunto` AS id_conjunto,
      cm.`Municipio` AS municipio,
      cm.`Mes` AS mes_apuracao,
      MEASURE(cm.`DEC`) AS dec_horas,
      MEASURE(cm.`FEC`) AS fec_eventos
    FROM {metric_table} AS cm
    WHERE cm.`Mes` = (
      SELECT MAX(cm2.`Mes`)
      FROM {metric_table} AS cm2
    )
    GROUP BY ALL
    """
).where(F.lower(F.col("municipio")) == F.lit(regiao_normalizada))

facts = {
    "regiao": regiao,
    "ultimo_dia_com_movimento": _json_value(ultimo_dia),
    "operacao_por_conjunto": _rows(operacao_comparada),
    "bairros_prioridade_alta": _rows(prioridade_alta),
    "clientes_risco_ouvidoria": _rows(clientes_ouvidoria),
    "continuidade_ultimo_mes": _rows(metricas),
}


def _number(value, decimals=3):
    if value is None:
        return "sem histórico"
    if decimals == 0:
        return str(int(value))
    return f"{float(value):.{decimals}f}"


def _deterministic_report(data):
    operacao_rows = data["operacao_por_conjunto"]
    bairros = data["bairros_prioridade_alta"]
    clientes = data["clientes_risco_ouvidoria"]
    continuidade = data["continuidade_ultimo_mes"]

    ocorrido = "; ".join(
        f"{row['nome_conjunto']}: {row['qtd_interrupcoes']} interrupções, "
        f"{_number(row['uc_horas_interrompidas'])} horas-UC, maior evento de "
        f"{_number(row['maior_duracao_horas'])} hora(s), causa predominante "
        f"{row['causa_predominante']}, {row['qtd_chamados']} chamados "
        f"({row['qtd_chamados_negativos']} negativos)"
        for row in operacao_rows
    )
    impacto = "; ".join(
        f"{row['nome_conjunto']} tem {row['qtd_chamados_risco_saude']} chamado(s) com risco à saúde, "
        f"{row['qtd_mencoes_ouvidoria']} menção(ões) à ouvidoria e média de "
        f"{_number(row['media_chamados_30d'], 2)} chamado(s) nos 30 dias anteriores"
        for row in operacao_rows
    )
    dec_fec = "; ".join(
        f"{row['conjunto']}: DEC {_number(row['dec_horas'])} h/UC e FEC {_number(row['fec_eventos'])}"
        for row in continuidade
    ) or "não há métrica mensal para a região"
    bairros_texto = ", ".join(
        f"{row['bairro']} ({row['qtd_ucs_prioridade_alta']} UC(s))" for row in bairros
    ) or "nenhum bairro com prioridade alta"
    clientes_texto = ", ".join(row["id_cliente"] for row in clientes) or "nenhum cliente em risco alto ou médio"
    acoes = "; ".join(
        f"{row['nome_conjunto']}: {row['acao_recomendada']}" for row in operacao_rows
    )

    return (
        f"O que aconteceu: em {data['ultimo_dia_com_movimento']}, {ocorrido}.\n\n"
        f"Impacto em números: {impacto}. No último mês, {dec_fec}.\n\n"
        f"O que precisa de ação: {acoes}. Prioridade alta de inspeção nos bairros {bairros_texto}; "
        f"clientes em risco de ouvidoria: {clientes_texto}."
    )


def _ai_report(data):
    instructions = (
        "Redija um relatório executivo em português, com no máximo 250 palavras e exatamente três partes "
        "tituladas 'O que aconteceu', 'Impacto em números' e 'O que precisa de ação'. "
        "Use exclusivamente os números e textos do JSON fornecido: não estime, não invente e não arredonde "
        "para criar efeito. UCs com consumo atípico são prioridade de inspeção; nunca use os termos fraude, "
        "furto, roubo ou irregularidade e nunca atribua culpa. Diferencie cliente de UC, cite o último dia "
        "com movimento e termine com a ação recomendada. JSON de fatos:\n"
        f"{json.dumps(data, ensure_ascii=False)}"
    )
    escaped = instructions.replace("'", "''")
    return spark.sql(f"SELECT ai_gen('{escaped}') AS relatorio").first()["relatorio"]


relatorio = _ai_report(facts) if usar_ia else _deterministic_report(facts)
if not relatorio:
    raise RuntimeError("O relatório não foi gerado.")
if len(relatorio.split()) > 250:
    raise RuntimeError("O relatório excedeu o limite de 250 palavras.")
for termo_proibido in ("fraude", "furto", "roubo", "irregularidade"):
    if termo_proibido in relatorio.casefold():
        raise RuntimeError(f"O relatório contém termo proibido: {termo_proibido}")

resultado = {
    "relatorio": relatorio,
    "usar_ia": usar_ia,
    "gerador": "ai_gen" if usar_ia else "gabarito_deterministico",
    "regiao": regiao,
    "ultimo_dia_com_movimento": _json_value(ultimo_dia),
    "fatos": facts,
}
dbutils.notebook.exit(json.dumps(resultado, ensure_ascii=False))
