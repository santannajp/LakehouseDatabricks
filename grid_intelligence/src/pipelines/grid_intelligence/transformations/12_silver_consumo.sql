CREATE OR REFRESH MATERIALIZED VIEW ${catalogo}.${schema_silver}.consumo_diario
TBLPROPERTIES ('delta.feature.timestampNtz' = 'supported')
AS SELECT
  c.id_uc,
  c.data,
  c.consumo_kwh,
  c.horas_com_leitura,
  c.sinal_violacao_medidor,
  u.id_conjunto,
  u.nome_conjunto,
  u.municipio,
  u.bairro,
  u.classe_consumo,
  c.origem,
  c.ingerido_em,
  c.arquivo_origem,
  c.ingerido_bronze_em
FROM ${catalogo}.${schema_bronze}.consumo_diario c
JOIN ${catalogo}.${schema_silver}.unidades_consumidoras u
  ON c.id_uc = u.id_uc
WHERE c.consumo_kwh IS NOT NULL
  AND c.consumo_kwh >= 0
  AND c.consumo_kwh <= CASE u.classe_consumo
    WHEN 'residencial' THEN 500.0
    WHEN 'rural' THEN 2000.0
    WHEN 'comercial' THEN 5000.0
    WHEN 'poder_publico' THEN 10000.0
    WHEN 'industrial' THEN 50000.0
    ELSE 5000.0
  END
QUALIFY row_number() OVER (
  PARTITION BY c.id_uc, c.data
  ORDER BY c.ingerido_em DESC
) = 1;

CREATE OR REFRESH MATERIALIZED VIEW ${catalogo}.${schema_silver}.baseline_consumo
TBLPROPERTIES ('delta.feature.timestampNtz' = 'supported')
AS
WITH ancoragem AS (
  SELECT max(data) AS data_referencia
  FROM ${catalogo}.${schema_silver}.consumo_diario
),
por_uc AS (
  SELECT
    c.id_uc,
    c.id_conjunto,
    c.nome_conjunto,
    c.municipio,
    c.bairro,
    c.classe_consumo,
    a.data_referencia,
    avg(CASE
      WHEN c.data > date_sub(a.data_referencia, ${janela_recente_dias})
      THEN c.consumo_kwh
    END) AS consumo_medio_recente_kwh,
    avg(CASE
      WHEN c.data <= date_sub(a.data_referencia, ${janela_recente_dias})
       AND c.data > date_sub(a.data_referencia, ${janela_recente_dias} + ${janela_baseline_dias})
      THEN c.consumo_kwh
    END) AS consumo_medio_baseline_kwh,
    count_if(c.data > date_sub(a.data_referencia, ${janela_recente_dias})) AS dias_no_periodo_recente,
    count_if(
      c.data <= date_sub(a.data_referencia, ${janela_recente_dias})
      AND c.data > date_sub(a.data_referencia, ${janela_recente_dias} + ${janela_baseline_dias})
    ) AS dias_no_baseline,
    max(CASE
      WHEN c.data > date_sub(a.data_referencia, ${janela_recente_dias})
       AND c.sinal_violacao_medidor THEN true
      ELSE false
    END) AS sinal_violacao_recente
  FROM ${catalogo}.${schema_silver}.consumo_diario c
  CROSS JOIN ancoragem a
  GROUP BY
    c.id_uc,
    c.id_conjunto,
    c.nome_conjunto,
    c.municipio,
    c.bairro,
    c.classe_consumo,
    a.data_referencia
),
com_conjunto AS (
  SELECT
    p.*,
    avg(p.consumo_medio_baseline_kwh) OVER (PARTITION BY p.id_conjunto) AS consumo_medio_baseline_conjunto_kwh,
    avg(p.consumo_medio_recente_kwh) OVER (PARTITION BY p.id_conjunto) AS consumo_medio_recente_conjunto_kwh
  FROM por_uc p
)
SELECT
  id_uc,
  id_conjunto,
  nome_conjunto,
  municipio,
  bairro,
  classe_consumo,
  data_referencia,
  consumo_medio_baseline_kwh,
  consumo_medio_recente_kwh,
  dias_no_baseline,
  dias_no_periodo_recente,
  sinal_violacao_recente,
  (consumo_medio_recente_kwh - consumo_medio_baseline_kwh)
    / NULLIF(consumo_medio_baseline_kwh, 0) AS variacao_da_uc,
  consumo_medio_baseline_conjunto_kwh,
  consumo_medio_recente_conjunto_kwh,
  (consumo_medio_recente_conjunto_kwh - consumo_medio_baseline_conjunto_kwh)
    / NULLIF(consumo_medio_baseline_conjunto_kwh, 0) AS variacao_do_conjunto
FROM com_conjunto;
