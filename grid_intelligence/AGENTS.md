# Convenções para agentes

## Contexto e autenticação

- Leia `.llm/prd.md` e o prompt correspondente antes de alterar o projeto.
- Nunca escolha um perfil Databricks automaticamente. Use explicitamente `--profile grid_inteligence`.
- O nome lógico do projeto é `grid_intelligence`; o nome real configurado na CLI é `grid_inteligence`.
- `dev` usa o catálogo `grid_dev`; `prod` usa `grid_intelligence`.
- Valide com `databricks bundle validate --strict -t dev --profile grid_inteligence` antes de fazer deploy.

## Dados e regras de negócio

- Bronze preserva a entrada e não aplica regra de negócio.
- Silver aplica filtros numéricos, deduplicação e enriquecimento de texto com regex.
- Nenhuma máscara de dado pessoal deve usar função de IA; preserve as máscaras regex existentes.
- DEC e FEC só existem oficialmente em `gold.continuidade_metricas`; consultas de medidas usam `MEASURE()`.
- Prioridade alta é fila de inspeção, nunca acusação de fraude, furto, roubo, irregularidade ou culpa.
- Relatórios executivos leem somente Gold. Bronze/Silver só podem aparecer em consultas de demonstração que provem qualidade ou anonimização.
- Datas relativas devem usar o último dia com movimento no dataset, nunca depender de `current_date()` para este projeto sintético.

## Desenvolvimento

- Parametrize catálogo, schemas e warehouse pelo bundle; não grave catálogo de produção em código de dev.
- Mantenha JSON, SQL e scripts versionados; prefira scripts idempotentes para recursos que não têm tipo de bundle.
- Antes de executar SQL no Databricks, prefira consultas `SELECT`, `WITH`, `SHOW`, `DESCRIBE` ou `EXPLAIN` durante diagnóstico.
- Não remova recursos ou dados sem confirmar o alvo exato e a necessidade da operação.
- Após alterações, rode `uv run pytest`, `uv run ruff check .` e `databricks bundle validate --strict -t dev --profile grid_inteligence`.
