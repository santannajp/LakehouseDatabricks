-- O YAML usa nomes simples porque o catalogo e o schema sao definidos antes.
USE CATALOG IDENTIFIER(:catalogo);
USE SCHEMA IDENTIFIER(:schema_gold);

CREATE OR REPLACE VIEW continuidade_metricas
WITH METRICS
LANGUAGE YAML
AS $$
version: 1.1
source: continuidade_conjunto_mes
comment: "Metricas governadas de continuidade do fornecimento por conjunto e mes"
dimensions:
  - name: Conjunto
    expr: nome_conjunto
    display_name: "Conjunto"
    synonyms: ["regiao", "area", "localidade"]
    comment: "Nome do conjunto regulatorio"
  - name: Codigo do Conjunto
    expr: id_conjunto
    display_name: "Codigo do Conjunto"
    synonyms: ["codigo", "id do conjunto"]
    comment: "Identificador do conjunto regulatorio"
  - name: Municipio
    expr: municipio
    display_name: "Municipio"
    synonyms: ["cidade"]
    comment: "Municipio atendido pelo conjunto"
  - name: Mes
    expr: mes_apuracao
    display_name: "Mes"
    synonyms: ["mes de apuracao", "periodo"]
    comment: "Mes de apuracao dos indicadores"
measures:
  - name: DEC
    expr: SUM(uc_horas_interrompidas) / NULLIF(SUM(total_ucs), 0)
    display_name: "DEC"
    synonyms: ["duracao sem luz", "horas sem energia", "duracao equivalente"]
    comment: "Horas medias sem energia por UC do conjunto no mes"
    format:
      type: number
      decimal_places:
        type: exact
        places: 2
  - name: FEC
    expr: SUM(uc_interrupcoes) / NULLIF(SUM(total_ucs), 0)
    display_name: "FEC"
    synonyms: ["frequencia de interrupcao", "quantidade de interrupcoes"]
    comment: "Numero medio de interrupcoes por UC do conjunto no mes"
    format:
      type: number
      decimal_places:
        type: exact
        places: 2
  - name: DEC Acumulado
    expr: SUM(uc_horas_interrompidas) / NULLIF(SUM(total_ucs) / COUNT(DISTINCT mes_apuracao), 0)
    display_name: "DEC Acumulado"
    synonyms: ["duracao acumulada", "horas sem energia acumuladas"]
    comment: "Horas sem energia por UC acumuladas no periodo selecionado"
    format:
      type: number
      decimal_places:
        type: exact
        places: 2
  - name: Interrupcoes
    expr: SUM(qtd_interrupcoes)
    display_name: "Interrupcoes"
    synonyms: ["eventos de rede", "faltas"]
    comment: "Quantidade de interrupcoes validas no periodo"
    format:
      type: number
      decimal_places:
        type: exact
        places: 0
  - name: Interrupcoes Climaticas
    expr: SUM(qtd_interrupcoes_climaticas)
    display_name: "Interrupcoes Climaticas"
    synonyms: ["eventos climaticos", "intemperie"]
    comment: "Interrupcoes cuja causa foi classificada como climatica"
    format:
      type: number
      decimal_places:
        type: exact
        places: 0
  - name: Proporcao Climatica
    expr: SUM(qtd_interrupcoes_climaticas) / NULLIF(SUM(qtd_interrupcoes), 0)
    display_name: "Proporcao Climatica"
    synonyms: ["percentual climatico", "participacao climatica"]
    comment: "Proporcao dos eventos validos com causa climatica"
    format:
      type: percentage
      decimal_places:
        type: exact
        places: 1
  - name: Interrupcoes Programadas
    expr: SUM(qtd_interrupcoes_programadas)
    display_name: "Interrupcoes Programadas"
    synonyms: ["manutencoes programadas", "desligamentos programados"]
    comment: "Quantidade de interrupcoes programadas no periodo"
    format:
      type: number
      decimal_places:
        type: exact
        places: 0
  - name: Horas UC Interrompidas
    expr: SUM(uc_horas_interrompidas)
    display_name: "Horas UC Interrompidas"
    synonyms: ["horas-UC", "horas afetadas"]
    comment: "Soma da duracao multiplicada pelas UCs afetadas"
    format:
      type: number
      decimal_places:
        type: exact
        places: 1
  - name: Maior Interrupcao
    expr: MAX(maior_duracao_horas)
    display_name: "Maior Interrupcao"
    synonyms: ["pior evento", "maior duracao"]
    comment: "Maior duracao de interrupcao em horas"
    format:
      type: number
      decimal_places:
        type: exact
        places: 2
  - name: Total de UCs
    expr: SUM(total_ucs) / COUNT(DISTINCT mes_apuracao)
    display_name: "Total de UCs"
    synonyms: ["unidades consumidoras", "base de UCs"]
    comment: "Quantidade media de UCs do conjunto no periodo selecionado"
    format:
      type: number
      decimal_places:
        type: exact
        places: 0
$$
