# PRD — Grid Intelligence

## 1. Visao do produto

Grid Intelligence e uma plataforma de dados e IA para a distribuidora ficticia Luz do
Vale Distribuidora S.A. O projeto transforma dados operacionais, de consumo e de
atendimento em quatro entregas auditaveis para operacao e diretoria:

1. continuidade do fornecimento por conjunto e mes, com DEC e FEC definidos uma unica vez
2. prioridade de inspecao por UC, explicavel e sem acusacao
3. saude do cliente, com risco de ouvidoria e risco a saude
4. painel operacional diario, cruzando rede, atendimento, consumo e acao recomendada

O projeto usa arquitetura medalhao no Unity Catalog. O catalogo separa os ambientes:
`grid_dev` para desenvolvimento e `grid_intelligence` para producao. Em cada catalogo,
os schemas mantem os nomes `raw`, `bronze`, `silver` e `gold`.

## 2. Contexto de negocio

A distribuidora opera sob regulacao da ANEEL e tem tres dores mensuraveis:

- continuidade: interrupcoes acima do limite regulatorio geram compensacao financeira
- perdas nao tecnicas: energia distribuida e nao faturada precisa de priorizacao de visita
- atendimento: transcricoes guardam sinais antecipados de reclamacao na ouvidoria

O objetivo do produto e reduzir tempo de diagnostico, tornar os indicadores consistentes e
dar ao inspetor uma fila explicavel. O produto nao determina culpa nem substitui a decisao
de campo.

## 3. Glossario

| Termo | Definicao |
|---|---|
| UC — Unidade Consumidora | Ponto de entrega de energia. Nao e sinonimo de cliente: um cliente pode ter varias UCs |
| Cliente | Pessoa ou entidade que pode possuir uma ou mais UCs |
| Conjunto | Subdivisao geografica da concessao e unidade de agregacao do regulador |
| DEC | Duracao Equivalente de Interrupcao por UC, em horas |
| FEC | Frequencia Equivalente de Interrupcao por UC |
| PNT | Perdas Nao Tecnicas |
| Prioridade de inspecao | Classificacao de quanto uma UC merece visita tecnica: alta, media ou baixa |
| Bronze | Copia fiel dos dados de entrada, com origem e momento de ingestao |
| Silver | Dados limpos, deduplicados e enriquecidos para consumo analitico |
| Gold | Entidades de negocio prontas para dashboard, agente e relatorio |

## 4. Regras de negocio

### Continuidade e operacao

- **RN-01** — Somente interrupcoes de fornecimento com duracao maior ou igual a 3 minutos
  entram na apuracao de DEC e FEC. O limiar vive na configuracao do pipeline.
- **RN-02** — O numerador de DEC e a soma de `duracao_horas * qtd_ucs_afetadas`, chamada
  de horas-UC interrompidas.
- **RN-03** — O numerador de FEC e a soma de `qtd_ucs_afetadas`. O denominador de DEC e
  FEC e o total de UCs do conjunto, inclusive as nao atingidas pelo evento.
- **RN-04** — DEC e FEC tem uma unica definicao no sistema, na metric view de continuidade,
  consumida por dashboard, agente e relatorio com `MEASURE()`.
- **RN-05** — A apuracao oficial e mensal, com uma linha por conjunto e mes. O acumulado
  de varios meses e uma medida separada da media mensal.

### Prioridade de inspecao

- **RN-06** — Uma UC e candidata quando a queda ocorre em dois eixos simultaneos: contra
  o proprio baseline e enquanto a vizinhanca permanece estavel.
- **RN-07** — A saida e sempre prioridade de inspecao — alta, media ou baixa — nunca um
  rotulo de fraude, furto, roubo, irregularidade ou culpa.
- **RN-08** — A decisao deve ser explicavel por regra e pelos numeros observados. Nao ha
  classificacao supervisionada sem rotulo confiavel neste dataset.

### Atendimento e privacidade

- **RN-09** — Dados pessoais em transcricao sao mascarados antes de qualquer analise de
  conteudo ou enriquecimento.
- **RN-10** — O texto original identificado e preservado somente com acesso restrito. A
  protecao na leitura e a protecao na analise coexistem.

### Dados e governanca

- **RN-11** — A ingestao nao filtra, corrige nem aplica regra de negocio. Defeitos de
  origem permanecem na bronze como evidencia.
- **RN-12** — Todo registro ingerido carrega a origem e o momento de ingestao no pipeline.
- **RN-13** — O agente conversacional acessa somente entidades da camada gold.
- **RN-14** — Entidades gold carregam descricao em linguagem de negocio. Bronze e silver
  sao passagem e nao precisam de descricao.

## 5. Dados de entrada

Os dados sinteticos tem quatro anos de historico, crescimento aproximado de 30% ao ano,
sazonalidade de verao no atendimento e defeitos propositais para validar a plataforma.

| Base | Grao | Linhas esperadas | Colunas principais |
|---|---|---:|---|
| `unidades_consumidoras` | uma linha por UC | 4.000 | UC, cliente, conjunto, bairro, classe e cadastro |
| `interrupcoes` | uma linha por evento | 1.383 | conjunto, inicio, fim, duracao, causa e UCs afetadas |
| `consumo_diario` | UC por dia | 5.854.587 | data, consumo, horas de leitura e sinal do medidor |
| `chamados` | uma linha por ligacao | 2.801 | cliente, UC, abertura, canal e transcricao |

Os Parquet chegam ao volume managed `raw.landing`, uma pasta por base:

```text
/Volumes/grid_dev/raw/landing/unidades_consumidoras/
/Volumes/grid_dev/raw/landing/interrupcoes/
/Volumes/grid_dev/raw/landing/consumo_diario/
/Volumes/grid_dev/raw/landing/chamados/
```

## 6. Modelo de informacao

```text
raw.landing/<base>/
  -> bronze.<base>
     -> silver.unidades_consumidoras
     -> silver.interrupcoes_validas
     -> silver.consumo_diario
     -> silver.baseline_consumo
     -> silver.chamados_enriquecidos
        -> gold.continuidade_conjunto_mes
        -> gold.continuidade_metricas
        -> gold.prioridade_inspecao_uc
        -> gold.saude_cliente
        -> gold.painel_operacional_dia
```

Bronze usa Auto Loader e preserva o fato de entrada. Silver normaliza cadastro, aplica a
RN-01, remove leituras invalidas, deduplica `(id_uc, data)`, cria baseline comparavel e
mascara/enriquece texto. Gold publica as perguntas de negocio. A metric view e criada por
SQL versionado e concentra a definicao de DEC e FEC.

## 7. Entregas e consumidores

| Entrega | Consumidores | Pergunta respondida |
|---|---|---|
| Continuidade | dashboard, agente, relatorio | Estamos dentro do limite e onde piorou? |
| Prioridade de inspecao | operacao e inspetor | Quais UCs merecem visita primeiro? |
| Saude do cliente | atendimento e diretoria | Quem esta em rota de ouvidoria ou risco a saude? |
| Painel operacional diario | operacao e relatorio | O que aconteceu e qual acao deve ocorrer hoje? |

## 8. Diretriz de implementacao

O projeto e construido ao vivo. Priorize codigo curto e legivel. Nao adicionar expectations,
`CONSTRAINT`, propriedades ou tratamento de casos que o dataset nao tenha. Regras devem
aparecer como SQL direto e observavel. Catalogos e schemas sao parametrizados pelo bundle.
Nomes de entidades e colunas nao usam acentos.
