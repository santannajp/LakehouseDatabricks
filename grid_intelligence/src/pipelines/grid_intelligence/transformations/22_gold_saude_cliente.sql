CREATE OR REFRESH MATERIALIZED VIEW ${catalogo}.${schema_gold}.saude_cliente
COMMENT 'Sinais de atendimento, risco a saude e risco de ouvidoria por cliente'
TBLPROPERTIES ('delta.feature.timestampNtz' = 'supported')
AS
WITH chamados_30_dias AS (
  SELECT
    id_chamado,
    id_uc,
    id_cliente,
    id_conjunto,
    nome_conjunto,
    municipio,
    bairro,
    abertura,
    sentimento,
    motivo,
    equipamento_citado,
    risco_a_saude,
    urgencia,
    ameacou_ouvidoria,
    transcricao_anonimizada,
    count(*) OVER (
      PARTITION BY id_cliente
      ORDER BY CAST(abertura AS TIMESTAMP)
      RANGE BETWEEN INTERVAL 30 DAYS PRECEDING AND CURRENT ROW
    ) AS qtd_chamados_30_dias
  FROM ${catalogo}.${schema_silver}.chamados_enriquecidos
),
agregado AS (
  SELECT
    id_cliente,
    max_by(id_conjunto, abertura) AS id_conjunto,
    max_by(nome_conjunto, abertura) AS nome_conjunto,
    max_by(municipio, abertura) AS municipio,
    max_by(bairro, abertura) AS bairro,
    count(*) AS qtd_chamados,
    count(DISTINCT id_uc) AS qtd_ucs_com_chamado,
    count_if(sentimento IN ('negative', 'mixed')) AS qtd_chamados_negativos,
    count_if(ameacou_ouvidoria) AS qtd_mencoes_ouvidoria,
    count_if(risco_a_saude) AS qtd_chamados_risco_saude,
    count_if(urgencia = 'alta') AS qtd_urgencia_alta,
    max(CASE WHEN qtd_chamados_30_dias >= 3 THEN true ELSE false END) AS reincidente,
    mode(motivo) AS motivo_predominante,
    max_by(equipamento_citado, abertura) AS ultimo_equipamento_citado,
    max_by(transcricao_anonimizada, abertura) AS ultima_fala,
    min(abertura) AS primeiro_chamado_em,
    max(abertura) AS ultimo_chamado_em
  FROM chamados_30_dias
  GROUP BY id_cliente
)
SELECT
  *,
  qtd_chamados_negativos / NULLIF(qtd_chamados, 0) AS proporcao_negativa,
  CASE
    WHEN qtd_mencoes_ouvidoria > 0 THEN 'alto'
    WHEN reincidente AND qtd_chamados_negativos > 0 THEN 'medio'
    WHEN qtd_chamados_risco_saude > 0 THEN 'medio'
    ELSE 'baixo'
  END AS risco_ouvidoria
FROM agregado;
