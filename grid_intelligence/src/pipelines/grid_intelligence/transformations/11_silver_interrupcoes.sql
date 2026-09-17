CREATE OR REFRESH STREAMING TABLE ${catalogo}.${schema_silver}.interrupcoes_validas
TBLPROPERTIES ('delta.feature.timestampNtz' = 'supported')
AS SELECT
  id_interrupcao,
  id_conjunto,
  inicio,
  fim,
  duracao_minutos,
  to_date(inicio) AS data_evento,
  date_trunc('MONTH', inicio) AS mes_apuracao,
  duracao_minutos / 60.0 AS duracao_horas,
  (duracao_minutos / 60.0) * qtd_ucs_afetadas AS uc_horas_interrompidas,
  tipo,
  causa,
  causa = 'climatica' AS causa_climatica,
  equipamento,
  qtd_ucs_afetadas,
  origem,
  ingerido_em,
  arquivo_origem,
  ingerido_bronze_em
FROM STREAM(${catalogo}.${schema_bronze}.interrupcoes)
-- Interrupcoes abaixo de tres minutos sao atuacoes do religador, nao falta de energia.
-- O evento continua preservado na bronze e deixa de entrar nos indicadores somente aqui.
WHERE duracao_minutos >= ${duracao_minima_interrupcao_min};
