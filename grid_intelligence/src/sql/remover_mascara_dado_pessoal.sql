-- A Bronze e mascarada para leitores externos. O pipeline precisa ler a origem
-- completa para construir a Silver anonimizada. A mascara e reaplicada na task
-- governanca_dado_pessoal imediatamente depois do pipeline.
USE CATALOG IDENTIFIER(:catalogo);
USE SCHEMA IDENTIFIER(:schema_bronze);

ALTER TABLE chamados ALTER COLUMN nome_solicitante DROP MASK;
ALTER TABLE chamados ALTER COLUMN telefone_solicitante DROP MASK;
ALTER TABLE chamados ALTER COLUMN transcricao DROP MASK;
