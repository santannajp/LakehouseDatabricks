CREATE OR REFRESH MATERIALIZED VIEW ${catalogo}.${schema_gold}.prioridade_inspecao_uc
COMMENT 'Prioridade explicavel de inspecao por unidade consumidora'
AS SELECT
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
  variacao_da_uc,
  variacao_do_conjunto,
  variacao_da_uc <= ${limiar_queda_uc_pct} AS caiu_contra_si,
  abs(variacao_do_conjunto) <= ${faixa_estabilidade_conjunto_pct} AS vizinhanca_estavel,
  variacao_da_uc <= ${limiar_queda_uc_pct}
    AND abs(variacao_do_conjunto) <= ${faixa_estabilidade_conjunto_pct} AS atende_os_dois_eixos,
  CASE
    WHEN variacao_da_uc <= ${limiar_queda_uc_pct}
      AND abs(variacao_do_conjunto) <= ${faixa_estabilidade_conjunto_pct}
      AND sinal_violacao_recente THEN 'alta'
    WHEN variacao_da_uc <= ${limiar_queda_uc_pct}
      AND abs(variacao_do_conjunto) <= ${faixa_estabilidade_conjunto_pct} THEN 'media'
    WHEN sinal_violacao_recente THEN 'media'
    ELSE 'baixa'
  END AS prioridade_inspecao,
  CASE
    WHEN variacao_da_uc <= ${limiar_queda_uc_pct}
      AND abs(variacao_do_conjunto) <= ${faixa_estabilidade_conjunto_pct}
      AND sinal_violacao_recente THEN 'Queda individual e sinal recente no medidor'
    WHEN variacao_da_uc <= ${limiar_queda_uc_pct}
      AND abs(variacao_do_conjunto) <= ${faixa_estabilidade_conjunto_pct} THEN 'Queda individual com vizinhanca estavel'
    WHEN sinal_violacao_recente THEN 'Sinal recente no medidor sem queda individual relevante'
    ELSE 'Variacao acompanhou a vizinhanca'
  END AS motivo_observado
FROM ${catalogo}.${schema_silver}.baseline_consumo;
