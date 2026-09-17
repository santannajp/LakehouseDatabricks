CREATE OR REFRESH MATERIALIZED VIEW ${catalogo}.${schema_gold}.continuidade_conjunto_mes
COMMENT 'Insumos mensais de continuidade por conjunto para DEC e FEC'
TBLPROPERTIES ('delta.feature.timestampNtz' = 'supported')
AS
WITH ucs_por_conjunto AS (
  SELECT
    id_conjunto,
    max(nome_conjunto) AS nome_conjunto,
    max(municipio) AS municipio,
    count(*) AS total_ucs
  FROM ${catalogo}.${schema_silver}.unidades_consumidoras
  GROUP BY id_conjunto
)
SELECT
  i.id_conjunto,
  u.nome_conjunto,
  u.municipio,
  i.mes_apuracao,
  u.total_ucs,
  sum(i.uc_horas_interrompidas) AS uc_horas_interrompidas,
  sum(i.qtd_ucs_afetadas) AS uc_interrupcoes,
  count(*) AS qtd_interrupcoes,
  count_if(i.causa_climatica) AS qtd_interrupcoes_climaticas,
  count_if(i.tipo = 'programada') AS qtd_interrupcoes_programadas,
  max(i.duracao_horas) AS maior_duracao_horas
FROM ${catalogo}.${schema_silver}.interrupcoes_validas i
JOIN ucs_por_conjunto u
  ON i.id_conjunto = u.id_conjunto
GROUP BY
  i.id_conjunto,
  u.nome_conjunto,
  u.municipio,
  i.mes_apuracao,
  u.total_ucs;
