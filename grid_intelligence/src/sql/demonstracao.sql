-- Grid Intelligence — oito consultas de evidência do projeto.
-- Todas são somente leitura. Execute uma por vez no SQL Warehouse do bundle.

-- 1) RN-01 tem efeito: interrupções abaixo de 3 minutos ficam fora da Silver.
-- Esperado: bronze=1383, silver=1073, descartadas=310, percentual=22.42%.
WITH contagens AS (
  SELECT
    (SELECT COUNT(*) FROM ${catalogo}.${schema_bronze}.interrupcoes) AS bronze,
    (SELECT COUNT(*) FROM ${catalogo}.${schema_silver}.interrupcoes_validas) AS silver
)
SELECT
  bronze,
  silver,
  bronze - silver AS descartadas,
  ROUND(100.0 * (bronze - silver) / NULLIF(bronze, 0), 2) AS percentual_descartado
FROM contagens;

-- 2) A qualidade tem efeito: consumo inválido e reenvio duplicado são separados.
-- Esperado: total Bronze=5854587, total Silver=5806222; a soma das causas
-- descartadas é 48365, com mantida=5806222.
WITH cadastro AS (
  SELECT id_uc, LOWER(TRIM(classe_consumo)) AS classe_consumo
  FROM ${catalogo}.${schema_silver}.unidades_consumidoras
), marcada AS (
  SELECT
    b.id_uc,
    b.data,
    b.consumo_kwh,
    b.ingerido_em,
    c.id_uc AS cadastro_id_uc,
    c.classe_consumo,
    ROW_NUMBER() OVER (
      PARTITION BY b.id_uc, b.data
      ORDER BY b.ingerido_em DESC
    ) AS ordem_reenvio
  FROM ${catalogo}.${schema_bronze}.consumo_diario AS b
  LEFT JOIN cadastro AS c ON b.id_uc = c.id_uc
), classificada AS (
  SELECT
    CASE
      WHEN cadastro_id_uc IS NULL THEN 'sem_cadastro'
      WHEN consumo_kwh IS NULL THEN 'consumo_nulo'
      WHEN consumo_kwh < 0 THEN 'consumo_negativo'
      WHEN consumo_kwh > CASE classe_consumo
        WHEN 'residencial' THEN 500.0
        WHEN 'rural' THEN 2000.0
        WHEN 'comercial' THEN 5000.0
        WHEN 'poder_publico' THEN 10000.0
        WHEN 'industrial' THEN 50000.0
        ELSE 5000.0
      END THEN 'acima_limite_classe'
      WHEN ordem_reenvio > 1 THEN 'duplicata_reenvio'
      ELSE 'mantida'
    END AS motivo_descarte
  FROM marcada
)
SELECT motivo_descarte, COUNT(*) AS qtd_linhas
FROM classificada
GROUP BY motivo_descarte
ORDER BY qtd_linhas DESC, motivo_descarte;

-- 3) RN-04 é real: a metric view e o cálculo manual do insumo devem bater.
-- Esperado: diferencas_dec e diferencas_fec iguais a 0 para os 6 conjuntos.
WITH metric_view AS (
  SELECT
    cm.`Codigo do Conjunto` AS id_conjunto,
    cm.`Mes` AS mes_apuracao,
    MEASURE(cm.`DEC`) AS dec_metric_view,
    MEASURE(cm.`FEC`) AS fec_metric_view
  FROM ${catalogo}.${schema_gold}.continuidade_metricas AS cm
  WHERE cm.`Mes` = (
    SELECT MAX(cm2.`Mes`)
    FROM ${catalogo}.${schema_gold}.continuidade_metricas AS cm2
  )
  GROUP BY ALL
), manual AS (
  SELECT
    c.id_conjunto,
    c.mes_apuracao,
    SUM(c.uc_horas_interrompidas) / NULLIF(SUM(c.total_ucs), 0) AS dec_manual,
    SUM(c.uc_interrupcoes) / NULLIF(SUM(c.total_ucs), 0) AS fec_manual
  FROM ${catalogo}.${schema_gold}.continuidade_conjunto_mes AS c
  WHERE c.mes_apuracao = (
    SELECT MAX(c2.mes_apuracao)
    FROM ${catalogo}.${schema_gold}.continuidade_conjunto_mes AS c2
  )
  GROUP BY c.id_conjunto, c.mes_apuracao
)
SELECT
  m.id_conjunto,
  m.mes_apuracao,
  m.dec_metric_view,
  n.dec_manual,
  ROUND(m.dec_metric_view - n.dec_manual, 12) AS diferenca_dec,
  m.fec_metric_view,
  n.fec_manual,
  ROUND(m.fec_metric_view - n.fec_manual, 12) AS diferenca_fec
FROM metric_view AS m
INNER JOIN manual AS n
  ON m.id_conjunto = n.id_conjunto
 AND m.mes_apuracao = n.mes_apuracao
ORDER BY m.id_conjunto;

-- 4) Os dois eixos funcionam: prioridade alta mostra queda individual,
-- vizinhança/conjunto estável e sinal observado lado a lado.
-- Esperado: 23 UCs de prioridade alta, com as duas variações disponíveis.
SELECT
  p.id_uc,
  p.id_conjunto,
  p.nome_conjunto,
  p.bairro,
  p.variacao_da_uc,
  p.variacao_do_conjunto,
  p.caiu_contra_si,
  p.vizinhanca_estavel,
  p.sinal_violacao_recente,
  p.motivo_observado
FROM ${catalogo}.${schema_gold}.prioridade_inspecao_uc AS p
WHERE p.prioridade_inspecao = 'alta'
ORDER BY p.variacao_da_uc, p.id_uc;

-- 5) A anonimização funciona: o mesmo chamado fica restrito na Bronze e
-- disponível de forma mascarada na Silver.
-- Esperado para CHM000005: Bronze=[RESTRITO] e Silver contém [MASKED_*].
SELECT
  b.id_chamado,
  b.transcricao AS bronze_transcricao,
  s.transcricao_anonimizada AS silver_transcricao,
  s.anonimizado_por
FROM ${catalogo}.${schema_bronze}.chamados AS b
INNER JOIN ${catalogo}.${schema_silver}.chamados_anonimizados AS s
  ON b.id_chamado = s.id_chamado
WHERE b.id_chamado = 'CHM000005';

-- 6) O evento narrativo está lá: noite da cascata em 2026-07-30,
-- comparada com a média do mesmo horário nos outros dias.
-- Esperado: 3 linhas para 21h, 22h e 23h; 22h/23h têm 6 chamados.
WITH por_dia_hora AS (
  SELECT
    c.data_chamado,
    c.hora_chamado,
    COUNT(*) AS qtd_chamados
  FROM ${catalogo}.${schema_silver}.chamados_enriquecidos AS c
  WHERE c.hora_chamado BETWEEN 21 AND 23
  GROUP BY c.data_chamado, c.hora_chamado
), cascata AS (
  SELECT hora_chamado, qtd_chamados
  FROM por_dia_hora
  WHERE data_chamado = DATE '2026-07-30'
), outras_noites AS (
  SELECT hora_chamado, AVG(qtd_chamados) AS media_outros_dias
  FROM por_dia_hora
  WHERE data_chamado <> DATE '2026-07-30'
  GROUP BY hora_chamado
)
SELECT
  c.hora_chamado,
  c.qtd_chamados AS chamados_cascata,
  ROUND(o.media_outros_dias, 2) AS media_mesma_hora_outros_dias,
  ROUND(c.qtd_chamados / NULLIF(o.media_outros_dias, 0), 2) AS multiplicador
FROM cascata AS c
LEFT JOIN outras_noites AS o ON c.hora_chamado = o.hora_chamado
ORDER BY c.hora_chamado;

-- 7) A tendência está lá: consumo total por ano no histórico de quatro anos.
-- Esperado: cinco buckets de ano em ordem crescente, cobrindo aproximadamente quatro
-- anos de histórico; os anos completos intermediários crescem perto de 30%.
SELECT
  YEAR(c.data) AS ano,
  ROUND(SUM(c.consumo_kwh), 2) AS consumo_total_kwh
FROM ${catalogo}.${schema_silver}.consumo_diario AS c
GROUP BY YEAR(c.data)
ORDER BY ano;

-- 8) A sazonalidade está lá: chamados por mês e classificação do verão.
-- Esperado: dezembro, janeiro e fevereiro acima da média dos demais meses,
-- próximos do dobro no conjunto da série.
SELECT
  MONTH(c.abertura) AS mes,
  CASE WHEN MONTH(c.abertura) IN (12, 1, 2) THEN 'verao' ELSE 'demais_meses' END AS periodo,
  COUNT(*) AS qtd_chamados
FROM ${catalogo}.${schema_silver}.chamados_enriquecidos AS c
GROUP BY MONTH(c.abertura), CASE WHEN MONTH(c.abertura) IN (12, 1, 2) THEN 'verao' ELSE 'demais_meses' END
ORDER BY mes;
