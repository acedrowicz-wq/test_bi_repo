-- Step 0. Country names need no object any more: they are inlined with transform() in the
-- alias layer (gen/parts.py). A dictionary with a CLICKHOUSE source needs a user + password on
-- ClickHouse Cloud ("A user other than the default user should specify the user name in the
-- dictionary source configuration"), and a Join-engine table is not replicated across replicas.
--
-- Removes what the first attempt of the deployment created (2026-10-10: the table, 249 rows).
DROP DICTIONARY IF EXISTS bi_sandbox.country_names_d;
DROP TABLE IF EXISTS bi_sandbox.country_names;
