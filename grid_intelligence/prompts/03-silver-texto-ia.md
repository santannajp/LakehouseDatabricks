# Prompt 03 — Silver: o texto, com regex

> **Prompt 4 de 8.** Requer a silver numérica pronta. Esta rota é 100% determinística:
> não usa modelos nem funções de IA.

Leia `.llm/prd.md`, inclusive a diretriz de simplicidade. Agora implemente a parte da
Silver que trata as transcrições das ligações da central de atendimento.

## O que criar

| Arquivo | Cria | Tipo | Grão |
|---|---|---|---|
| `src/pipelines/grid_intelligence/transformations/13_silver_chamados.py` | `silver.chamados_anonimizados` | materialized view | um chamado |
| o mesmo arquivo | `silver.chamados_enriquecidos` | materialized view | um chamado |
| `src/sql/governanca_dado_pessoal.sql` | column mask sobre `bronze.chamados` | task SQL do job | — |

São 2.801 chamados. Use materialized views porque a classificação e a anonimização devem
ser reprocessáveis sem depender de um lote incremental.

## Ordem obrigatória

1. Anonimize a transcrição.
2. Enriqueça somente o texto anonimizado.

## Anonimização por regex

Em `silver.chamados_anonimizados`, use apenas expressões Spark como `regexp_replace` para
mascarar:

- e-mail
- CPF
- telefone
- CEP
- nome presente na coluna `nome_solicitante`

Use marcadores explícitos, como `[MASKED_EMAIL]`, `[MASKED_CPF]`, `[MASKED_PHONE]`,
`[MASKED_CEP]` e `[MASKED_PERSON]`. Traga do cadastro cliente, conjunto, município, bairro
e classe da UC. Derive data e hora do chamado. Registre `regex` em `anonimizado_por`.

## Enriquecimento determinístico

A partir de `transcricao_anonimizada`, produza as mesmas colunas em todas as execuções:

| Coluna | Regra |
|---|---|
| `sentimento` | termos curtos para `negative`, `positive` e `neutral` |
| `motivo` | regras ordenadas para religação, falta de energia, tensão, medição, rede, financeiro e informação |
| `equipamento_citado` | palavras-chave de medidor, transformador, poste e fio |
| `risco_a_saude` | oxigênio, diálise, remédio, criança, hospital, faísca ou incêndio |
| `urgencia` | alta para risco à saúde, média para falta de energia, religação urgente ou poste avariado, baixa no restante |
| `ameacou_ouvidoria` | ouvidoria, ANEEL, Procon ou processo |

Registre `regex` em `enriquecido_por`. Não use `ai_mask`, `ai_classify`,
`ai_analyze_sentiment`, `ai_extract`, `ai_query` ou qualquer outra função de IA.
Não inclua configuração de seleção de IA nem nome de modelo.

## RN-10 — proteção da origem

Crie uma column mask do Unity Catalog que devolva o valor original para membros do grupo
`grupo_atendimento` e `[RESTRITO]` para os demais. Aplique-a em
`bronze.chamados.nome_solicitante`, `telefone_solicitante` e `transcricao`.

Como o pipeline pode recriar a tabela em um full refresh, aplique a máscara em uma task SQL
do job depois do pipeline.

## Critério de aceite

- Nenhum nome, CPF ou telefone sobrevive em `chamados_anonimizados`.
- O enriquecimento lê somente o texto anonimizado.
- Todas as linhas registram `regex` nos campos de auditoria.
- Nenhuma função `ai_*` aparece no código, configuração ou SQL.
- A column mask está aplicada e retorna `[RESTRITO]` fora do grupo autorizado.
