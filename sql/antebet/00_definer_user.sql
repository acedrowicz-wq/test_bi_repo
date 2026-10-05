-- Step 0. Technical user that ALL MVs run as (DEFINER).
--
-- Why: on ProdCH, default_materialized_view_sql_security = DEFINER and
-- default_view_definer = CURRENT_USER. An MV created from the SQL console would
-- run as the JWT user of your console session (storage = 'cloud', not a
-- permanent account). If that user disappears or loses permissions, the MV
-- starts throwing errors, and platform.slot_actions is filled by
-- platform.mysql_slot_actions_mv from PeerDB, so the error would stop
-- the replication of slot_actions and every aggregate built on it.
--
-- HOST NONE: nobody can log in as this user, it is used only as a definer.
-- Password: generate a random one (e.g. `openssl rand -base64 32`), paste it
-- and do not save it anywhere; it is never needed.

CREATE USER IF NOT EXISTS bi_antebet_definer
    IDENTIFIED WITH sha256_password BY '<RANDOM_PASSWORD>'
    HOST NONE;

-- sources (incremental MVs)
GRANT SELECT ON platform.slot_actions             TO bi_antebet_definer;
GRANT SELECT ON platform.mysql_slot_actions_extra TO bi_antebet_definer;
-- dictionaries (refreshable MVs)
GRANT dictGet ON platform.currency_d    TO bi_antebet_definer;
GRANT dictGet ON platform.whitelabels_d TO bi_antebet_definer;
-- target tables; CREATE/DROP TABLE because the refresh without APPEND
-- builds a temporary table and swaps it with bi_antebet_report_recent
GRANT SELECT, INSERT, CREATE TABLE, DROP TABLE, TRUNCATE ON adam_sandbox.* TO bi_antebet_definer;

-- check
SHOW GRANTS FOR bi_antebet_definer;
