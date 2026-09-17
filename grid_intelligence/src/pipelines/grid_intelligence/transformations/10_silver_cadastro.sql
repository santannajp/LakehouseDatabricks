CREATE OR REFRESH STREAMING TABLE ${catalogo}.${schema_silver}.unidades_consumidoras
TBLPROPERTIES ('delta.feature.timestampNtz' = 'supported')
AS SELECT
  id_uc,
  id_cliente,
  id_conjunto,
  nome_conjunto,
  municipio,
  CASE
    WHEN bairro IS NULL OR trim(bairro) = '' THEN 'nao informado'
    ELSE bairro
  END AS bairro,
  logradouro,
  lower(trim(classe_consumo)) AS classe_consumo,
  subgrupo_tarifario,
  tensao_nominal_v,
  situacao,
  data_ligacao,
  possui_medidor_inteligente,
  consumo_medio_kwh_dia,
  latitude,
  longitude,
  origem,
  ingerido_em,
  arquivo_origem,
  ingerido_bronze_em
FROM STREAM(${catalogo}.${schema_bronze}.unidades_consumidoras)
WHERE id_uc IS NOT NULL
  AND id_conjunto IS NOT NULL;
