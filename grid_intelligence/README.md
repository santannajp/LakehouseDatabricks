# Grid Intelligence

Plataforma de dados e IA da distribuidora fictícia Luz do Vale, construída no Databricks.
O projeto segue a sequência de prompts em `prompts/`: setup, bronze, silver, gold,
dashboard, agente e demonstração.

## Pré-requisitos

- Databricks CLI v1.7.0 ou superior
- `uv` para o ambiente Python
- acesso ao workspace `https://dbc-7a6349ec-d685.cloud.databricks.com`
- perfil OAuth configurado na CLI

Confira os perfis:

```bash
databricks auth profiles
```

Neste projeto, o perfil configurado é `grid_inteligence`, usado como o perfil lógico
`grid_intelligence`. Todos os comandos Databricks abaixo usam o nome real configurado.

## Setup

O catálogo não é criado pelo bundle. Crie os dois catálogos por SQL:

```bash
databricks experimental aitools tools query \
  --profile grid_inteligence \
  "CREATE CATALOG IF NOT EXISTS grid_dev COMMENT 'Catalogo de desenvolvimento da Grid Intelligence'"

databricks experimental aitools tools query \
  --profile grid_inteligence \
  "CREATE CATALOG IF NOT EXISTS grid_intelligence COMMENT 'Catalogo de producao da Grid Intelligence'"
```

Conceda acesso ao usuário responsável, trocando `SEU-EMAIL`:

```bash
databricks grants update CATALOG grid_dev \
  --json '{"changes":[{"principal":"SEU-EMAIL","add":["ALL_PRIVILEGES"]}]}' \
  --profile grid_inteligence

databricks grants update CATALOG grid_intelligence \
  --json '{"changes":[{"principal":"SEU-EMAIL","add":["ALL_PRIVILEGES"]}]}' \
  --profile grid_inteligence
```

O bundle cria os schemas `raw`, `bronze`, `silver` e `gold`, além do volume managed
`raw.landing`.

Valide e faça o deploy de desenvolvimento:

```bash
databricks bundle validate --strict -t dev --profile grid_inteligence
databricks bundle deploy -t dev --profile grid_inteligence
```

O `skip_name_prefix_for_schema` mantém os nomes dos schemas sem prefixo de usuário. O
isolamento entre dev e prod acontece pelos catálogos.

## Upload dos dados

Depois do deploy, suba uma pasta por base, com o Parquet dentro:

```text
/Volumes/grid_dev/raw/landing/unidades_consumidoras/
/Volumes/grid_dev/raw/landing/interrupcoes/
/Volumes/grid_dev/raw/landing/consumo_diario/
/Volumes/grid_dev/raw/landing/chamados/
```

Do diretório raiz do projeto, suba tudo de uma vez:

```bash
databricks fs cp -r landing dbfs:/Volumes/grid_dev/raw/landing \
  --overwrite --profile grid_inteligence
```

O prefixo `dbfs:` é obrigatório para operações em volumes. Se os dados estiverem em outro
local, substitua `landing` pela pasta local que contém as quatro subpastas.

## Recomeçar do zero

O comando abaixo é destrutivo: remove o catálogo, schemas, tabelas, volume e arquivos.
Confirme o catálogo antes de executar.

```bash
databricks experimental aitools tools query \
  --profile grid_inteligence \
  "DROP CATALOG IF EXISTS grid_dev CASCADE"
```

## Estrutura

```text
databricks.yml
resources/grid_schemas.yml
prompts/
.llm/prd.md
landing/
src/
tests/
```

O PRD em `.llm/prd.md` é a fonte de contexto, glossário e regras de negócio para os
prompts seguintes.

## Do zero ao copiloto

Execute a sequência abaixo na raiz de `grid_intelligence`, sempre informando o perfil:

```bash
uv sync --dev
databricks bundle validate --strict -t dev --profile grid_inteligence
databricks bundle deploy -t dev --profile grid_inteligence
databricks fs cp -r landing dbfs:/Volumes/grid_dev/raw/landing \
  --overwrite --profile grid_inteligence
databricks bundle run sample_job -t dev --profile grid_inteligence
uv run python scripts/apply_genie_space.py \
  --profile grid_inteligence \
  --catalogo grid_dev \
  --warehouse-id 8561dbb0dd49340a
```

O job executa a ingestão, o pipeline medalhão, a metric view, a governança e o relatório
executivo. O parâmetro `usar_ia` é `false` por padrão; para testar a redação com `ai_gen`:

```bash
databricks bundle run sample_job -t dev --profile grid_inteligence \
  --params usar_ia=true,regiao=Campinas
```

O relatório falha explicitamente quando a região não tem movimento no último dia do painel.
O arquivo `src/notebooks/relatorio_executivo.py` lê apenas Gold. A demonstração técnica em
`src/sql/demonstracao.sql` contém oito consultas de evidência; as consultas 1, 2 e 5 leem
Bronze de propósito para provar descarte e anonimização, enquanto o relatório executivo não
faz isso.

Links do ambiente `dev`:

- [Dashboard operacional](https://dbc-7a6349ec-d685.cloud.databricks.com/sql/dashboardsv3/01f1b2d48635100d82b27c2f884cd507)
- [Genie — Copiloto de Operações](https://dbc-7a6349ec-d685.cloud.databricks.com/genie/rooms/01f1b2d69afb1f799da6428d57146efa)

## Convenções de pastas

```text
src/pipelines/   transformações Bronze, Silver e Gold
src/sql/         governança, metric view e demonstração
src/notebooks/   relatórios executados pelo job
src/dashboards/  definições Lakeview versionadas
src/genie/       definição serializada do Genie
scripts/         aplicadores idempotentes de recursos sem suporte a bundle
resources/       recursos Declarative Automation Bundles
prompts/         especificações funcionais ordenadas
```

## Regras que não podem ser quebradas

- bronze não filtra nem corrige dados
- interrupções abaixo de 3 minutos não entram em DEC/FEC
- DEC e FEC são definidos uma vez na metric view
- prioridade de inspeção não é acusação
- dados pessoais são mascarados antes da análise
- o agente consulta somente gold

## Desenvolvimento local

```bash
uv sync --dev
uv run pytest
uv run ruff check .
```

Para conferir o bundle depois de editar YAML ou notebook:

```bash
databricks bundle validate --strict -t dev --profile grid_inteligence
uv run pytest
uv run ruff check .
```
