CREATE OR REFRESH MATERIALIZED VIEW ${catalogo}.${schema_gold}.painel_operacional_dia
COMMENT 'Painel diario de rede, atendimento, consumo e acao recomendada'
AS
WITH interrupcoes_dia AS (
  SELECT
    id_conjunto,
    data_evento,
    sum(uc_horas_interrompidas) AS uc_horas_interrompidas,
    count(*) AS qtd_interrupcoes,
    max(duracao_horas) AS maior_duracao_horas,
    mode(causa) AS causa_predominante,
    count_if(causa_climatica) AS qtd_interrupcoes_climaticas
  FROM ${catalogo}.${schema_silver}.interrupcoes_validas
  GROUP BY id_conjunto, data_evento
),
chamados_dia AS (
  SELECT
    id_conjunto,
    data_chamado AS data_evento,
    count(*) AS qtd_chamados,
    count_if(sentimento IN ('negative', 'mixed')) AS qtd_chamados_negativos,
    count_if(risco_a_saude) AS qtd_chamados_risco_saude,
    count_if(ameacou_ouvidoria) AS qtd_mencoes_ouvidoria,
    count_if(urgencia = 'alta') AS qtd_urgencia_alta
  FROM ${catalogo}.${schema_silver}.chamados_enriquecidos
  GROUP BY id_conjunto, data_chamado
),
consumo_dia AS (
  SELECT
    id_conjunto,
    data AS data_evento,
    sum(consumo_kwh) AS consumo_total_kwh,
    count_if(sinal_violacao_medidor) AS qtd_sinais_violacao
  FROM ${catalogo}.${schema_silver}.consumo_diario
  GROUP BY id_conjunto, data
),
prioridade_dia AS (
  SELECT
    id_conjunto,
    data_referencia AS data_evento,
    count_if(prioridade_inspecao = 'alta') AS qtd_ucs_prioridade_alta,
    count_if(prioridade_inspecao = 'media') AS qtd_ucs_prioridade_media,
    count_if(prioridade_inspecao = 'baixa') AS qtd_ucs_prioridade_baixa
  FROM ${catalogo}.${schema_gold}.prioridade_inspecao_uc
  GROUP BY id_conjunto, data_referencia
),
cadastro AS (
  SELECT
    id_conjunto,
    max(nome_conjunto) AS nome_conjunto,
    max(municipio) AS municipio,
    count(*) AS total_ucs
  FROM ${catalogo}.${schema_silver}.unidades_consumidoras
  GROUP BY id_conjunto
),
unido AS (
  SELECT
    coalesce(i.id_conjunto, c.id_conjunto, o.id_conjunto, p.id_conjunto) AS id_conjunto,
    coalesce(i.data_evento, c.data_evento, o.data_evento, p.data_evento) AS data_evento,
    i.uc_horas_interrompidas,
    i.qtd_interrupcoes,
    i.maior_duracao_horas,
    i.causa_predominante,
    i.qtd_interrupcoes_climaticas,
    c.qtd_chamados,
    c.qtd_chamados_negativos,
    c.qtd_chamados_risco_saude,
    c.qtd_mencoes_ouvidoria,
    c.qtd_urgencia_alta,
    o.consumo_total_kwh,
    o.qtd_sinais_violacao,
    p.qtd_ucs_prioridade_alta,
    p.qtd_ucs_prioridade_media,
    p.qtd_ucs_prioridade_baixa
  FROM interrupcoes_dia i
  FULL OUTER JOIN chamados_dia c
    ON i.id_conjunto = c.id_conjunto AND i.data_evento = c.data_evento
  FULL OUTER JOIN consumo_dia o
    ON coalesce(i.id_conjunto, c.id_conjunto) = o.id_conjunto
   AND coalesce(i.data_evento, c.data_evento) = o.data_evento
  FULL OUTER JOIN prioridade_dia p
    ON coalesce(i.id_conjunto, c.id_conjunto, o.id_conjunto) = p.id_conjunto
   AND coalesce(i.data_evento, c.data_evento, o.data_evento) = p.data_evento
)
SELECT
  u.id_conjunto,
  cad.nome_conjunto,
  cad.municipio,
  u.data_evento,
  cad.total_ucs,
  coalesce(u.uc_horas_interrompidas, 0) AS uc_horas_interrompidas,
  coalesce(u.qtd_interrupcoes, 0) AS qtd_interrupcoes,
  coalesce(u.maior_duracao_horas, 0) AS maior_duracao_horas,
  coalesce(u.causa_predominante, 'sem interrupcao') AS causa_predominante,
  coalesce(u.qtd_interrupcoes_climaticas, 0) AS qtd_interrupcoes_climaticas,
  coalesce(u.qtd_chamados, 0) AS qtd_chamados,
  coalesce(u.qtd_chamados_negativos, 0) AS qtd_chamados_negativos,
  coalesce(u.qtd_chamados_risco_saude, 0) AS qtd_chamados_risco_saude,
  coalesce(u.qtd_mencoes_ouvidoria, 0) AS qtd_mencoes_ouvidoria,
  coalesce(u.qtd_urgencia_alta, 0) AS qtd_urgencia_alta,
  coalesce(u.consumo_total_kwh, 0) AS consumo_total_kwh,
  coalesce(u.qtd_sinais_violacao, 0) AS qtd_sinais_violacao,
  coalesce(u.qtd_ucs_prioridade_alta, 0) AS qtd_ucs_prioridade_alta,
  coalesce(u.qtd_ucs_prioridade_media, 0) AS qtd_ucs_prioridade_media,
  coalesce(u.qtd_ucs_prioridade_baixa, 0) AS qtd_ucs_prioridade_baixa,
  CASE
    WHEN coalesce(u.qtd_chamados_risco_saude, 0) > 0
      OR coalesce(u.qtd_urgencia_alta, 0) > 0 THEN 'atender risco a saude'
    WHEN coalesce(u.qtd_mencoes_ouvidoria, 0) > 0 THEN 'retornar cliente antes da ouvidoria'
    WHEN coalesce(u.qtd_interrupcoes, 0) > 0 THEN 'tratar impacto na rede'
    WHEN coalesce(u.qtd_ucs_prioridade_alta, 0) > 0 THEN 'programar inspecao prioritaria'
    ELSE 'monitorar'
  END AS acao_recomendada
FROM unido u
JOIN cadastro cad
  ON u.id_conjunto = cad.id_conjunto;
