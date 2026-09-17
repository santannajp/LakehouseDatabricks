from functools import reduce

from pyspark import pipelines as dp
from pyspark.sql import SparkSession
from pyspark.sql import functions as F

spark = SparkSession.getActiveSession() or SparkSession.builder.getOrCreate()
catalogo = spark.conf.get("catalogo")
schema_bronze = spark.conf.get("schema_bronze")
schema_silver = spark.conf.get("schema_silver")


def _contains_any(column, terms):
    lowered = F.lower(column)
    return reduce(lambda result, term: result | lowered.contains(term), terms, F.lit(False))


def _cadastro():
    return spark.read.table(f"{catalogo}.{schema_silver}.unidades_consumidoras").select(
        "id_uc",
        "id_cliente",
        "id_conjunto",
        "nome_conjunto",
        "municipio",
        "bairro",
        "classe_consumo",
    )


def _chamados_com_cadastro():
    chamados = spark.read.table(f"{catalogo}.{schema_bronze}.chamados")
    return chamados.join(_cadastro(), "id_uc", "left")


def _anonimizar_por_regex(transcricao):
    mascarado = F.regexp_replace(
        transcricao,
        r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}",
        "[MASKED_EMAIL]",
    )
    mascarado = F.regexp_replace(
        mascarado,
        r"\b\d{3}[.\s]?\d{3}[.\s]?\d{3}[-\s]?\d{2}\b",
        "[MASKED_CPF]",
    )
    mascarado = F.regexp_replace(
        mascarado,
        r"(?:\+?55\s*)?(?:\(?\d{2}\)?\s*)?9?\d{4}[-\s]?\d{4}",
        "[MASKED_PHONE]",
    )
    mascarado = F.regexp_replace(mascarado, r"\b\d{5}-?\d{3}\b", "[MASKED_CEP]")
    return F.regexp_replace(
        mascarado,
        r"\b[A-ZÁÉÍÓÚÃÕÇ][a-záéíóúãõç]+(?:\s+[A-ZÁÉÍÓÚÃÕÇ][a-záéíóúãõç]+)+\b",
        "[MASKED_PERSON]",
    )


@dp.materialized_view(
    name=f"{catalogo}.{schema_silver}.chamados_anonimizados",
    table_properties={"delta.feature.timestampNtz": "supported"},
)
def chamados_anonimizados():
    base = _chamados_com_cadastro()
    transcricao_segura = _anonimizar_por_regex(F.col("transcricao"))

    return base.select(
        "id_chamado",
        "id_uc",
        "id_cliente",
        "id_conjunto",
        "nome_conjunto",
        "municipio",
        "bairro",
        "classe_consumo",
        "abertura",
        F.to_date("abertura").alias("data_chamado"),
        F.hour("abertura").alias("hora_chamado"),
        "canal",
        "duracao_segundos",
        transcricao_segura.alias("transcricao_anonimizada"),
        F.lit("regex").alias("anonimizado_por"),
        "origem",
        "ingerido_em",
        "arquivo_origem",
        "ingerido_bronze_em",
    )


@dp.materialized_view(
    name=f"{catalogo}.{schema_silver}.chamados_enriquecidos",
    table_properties={"delta.feature.timestampNtz": "supported"},
)
def chamados_enriquecidos():
    base = spark.read.table(f"{catalogo}.{schema_silver}.chamados_anonimizados")
    texto = F.lower(F.col("transcricao_anonimizada"))

    risco_a_saude = _contains_any(
        F.col("transcricao_anonimizada"),
        [
            "oxigenio",
            "oxigênio",
            "dialise",
            "diálise",
            "remedio",
            "remédio",
            "crianca",
            "criança",
            "hospital",
            "faisca",
            "faísca",
            "incendio",
            "incêndio",
        ],
    )
    ameacou_ouvidoria = _contains_any(
        F.col("transcricao_anonimizada"), ["ouvidoria", "aneel", "procon", "processo"]
    )

    return (
        base.withColumn("risco_a_saude", risco_a_saude)
        .withColumn("ameacou_ouvidoria", ameacou_ouvidoria)
        .withColumn(
            "sentimento",
            F.when(
                _contains_any(
                    F.col("transcricao_anonimizada"),
                    [
                        "absurdo",
                        "pessimo",
                        "problema",
                        "sem energia",
                        "sem luz",
                        "nao resolveu",
                        "não resolveu",
                        "urgente",
                        "reclamar",
                    ],
                ),
                F.lit("negative"),
            )
            .when(
                _contains_any(
                    F.col("transcricao_anonimizada"),
                    ["obrigado", "obrigada", "agradeco", "agradeço", "resolvido"],
                ),
                F.lit("positive"),
            )
            .otherwise(F.lit("neutral")),
        )
        .withColumn(
            "motivo",
            F.when(
                texto.contains("religacao urgente") | texto.contains("religação urgente"),
                "religacao_urgente",
            )
            .when(texto.contains("religacao") | texto.contains("religação"), "religacao")
            .when(
                _contains_any(
                    F.col("transcricao_anonimizada"),
                    ["sem energia", "sem luz", "apagao", "apagão"],
                ),
                "falta_energia",
            )
            .when(
                _contains_any(F.col("transcricao_anonimizada"), ["tensao", "tensão", "oscil"]),
                "tensao",
            )
            .when(
                _contains_any(
                    F.col("transcricao_anonimizada"),
                    ["medidor", "conta", "leitura", "consumo"],
                ),
                "medicao",
            )
            .when(
                _contains_any(
                    F.col("transcricao_anonimizada"), ["poste", "fio", "transformador"]
                ),
                "rede",
            )
            .when(
                _contains_any(
                    F.col("transcricao_anonimizada"), ["pagamento", "tarifa", "fatura"]
                ),
                "financeiro",
            )
            .otherwise("informacao"),
        )
        .withColumn(
            "equipamento_citado",
            F.when(texto.contains("medidor"), "medidor")
            .when(texto.contains("transformador"), "transformador")
            .when(texto.contains("poste"), "poste")
            .when(texto.contains("fio"), "rede")
            .otherwise(F.lit(None).cast("string")),
        )
        .withColumn(
            "urgencia",
            F.when(F.col("risco_a_saude"), "alta")
            .when(
                _contains_any(
                    F.col("transcricao_anonimizada"),
                    [
                        "sem energia",
                        "sem luz",
                        "religacao urgente",
                        "religação urgente",
                        "poste avariado",
                    ],
                ),
                "media",
            )
            .otherwise("baixa"),
        )
        .withColumn("enriquecido_por", F.lit("regex"))
    )
