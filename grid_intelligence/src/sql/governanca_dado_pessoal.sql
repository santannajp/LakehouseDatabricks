-- A tabela bronze e recriada em full refresh. Esta task reaplica a governanca depois dela.
USE CATALOG IDENTIFIER(:catalogo);
USE SCHEMA IDENTIFIER(:schema_bronze);

CREATE OR REPLACE FUNCTION mascarar_dado_pessoal(valor STRING)
RETURN CASE
  WHEN is_account_group_member('grupo_atendimento') THEN valor
  ELSE '[RESTRITO]'
END;

ALTER TABLE chamados ALTER COLUMN nome_solicitante SET MASK mascarar_dado_pessoal;
ALTER TABLE chamados ALTER COLUMN telefone_solicitante SET MASK mascarar_dado_pessoal;
ALTER TABLE chamados ALTER COLUMN transcricao SET MASK mascarar_dado_pessoal;
