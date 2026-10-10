-- Step 3a. Technical user + flat bet-level table for the full history.
--
-- Grain = 1 live bet, like the CSV / Tableau source (the workbook computes
-- COUNTD of players / rounds / sessions, so the data cannot be pre-aggregated).
-- Size: platform.bets has ~36 M rows since 2022-12 (~70-80 k bets/day),
-- a few GB in ClickHouse - one flat MergeTree table is the simplest and fastest
-- option for Tableau (no FINAL, no JOIN, no dictGet at query time).
--
-- The table keeps technical column names; the Tableau names (with spaces, €, ...)
-- are applied only in the view bi_sandbox.bi_total_eg_v (03_history_mvs_and_view.sql).

-- ---------------------------------------------------------------------
-- 0. Definer: MVs never run as a console (JWT) user. Same reasoning as
--    sql/antebet/00_definer_user.sql. HOST NONE = nobody can log in.
-- ---------------------------------------------------------------------
CREATE USER IF NOT EXISTS bi_total_eg_definer
    IDENTIFIED WITH sha256_password BY '<RANDOM_PASSWORD>'
    HOST NONE;

GRANT SELECT  ON platform.bets               TO bi_total_eg_definer;
GRANT SELECT  ON platform.partners_d         TO bi_total_eg_definer;   -- read as a table (wls list)
GRANT dictGet ON platform.partners_d         TO bi_total_eg_definer;
GRANT dictGet ON platform.whitelabels_d      TO bi_total_eg_definer;
GRANT dictGet ON platform.currency_d         TO bi_total_eg_definer;
GRANT dictGet ON bi_sandbox.country_names_d  TO bi_total_eg_definer;
-- CREATE/DROP TABLE: a refresh without APPEND builds a temporary table and swaps it
GRANT SELECT, INSERT, CREATE TABLE, DROP TABLE, TRUNCATE ON bi_sandbox.* TO bi_total_eg_definer;

-- ---------------------------------------------------------------------
-- 1. Closed days (<= today-2 UTC): appended once per day, never rewritten.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS bi_sandbox.bi_total_eg_bets
(
    bet_date                   Date,                                -- toDate(createdAt), UTC
    created_at                 DateTime64(6, 'UTC'),
    updated_at                 DateTime64(6, 'UTC'),
    status_updated_at          DateTime64(6, 'UTC'),

    mongo_id                   String,                              -- bet id
    player_mongo_id            String,
    round_mongo_id             String,
    token_mongo_id             String,
    round_num_id               String,

    wl_id                      LowCardinality(String),
    wl_name                    LowCardinality(String),
    wl_label                   LowCardinality(String),
    wl_is_test                 UInt8,
    partner_name               LowCardinality(Nullable(String)),
    wl_user_id                 String,
    tenant_id                  LowCardinality(String),

    game_id                    LowCardinality(String),
    country                    LowCardinality(String),
    country_name               LowCardinality(String),

    currency                   LowCardinality(String),
    currency_title             LowCardinality(String),
    currency_type              LowCardinality(String),
    is_fun                     UInt8,

    status                     LowCardinality(String),
    autoplay                   Nullable(String),
    free_spins                 Nullable(String),
    freespin_transaction_mode  LowCardinality(Nullable(String)),

    bet_size                   Decimal(30, 12),                     -- player currency
    won                        Decimal(30, 12),                     -- player currency
    converted_bet              Decimal(16, 4),                      -- EUR
    converted_win              Decimal(16, 4),                      -- EUR

    loaded_at                  DateTime DEFAULT now()
)
ENGINE = ReplacingMergeTree(updated_at)      -- protects against a repeated load of the same day
PARTITION BY toYYYYMM(bet_date)
ORDER BY (bet_date, wl_id, game_id, mongo_id);

-- ---------------------------------------------------------------------
-- 2. Open days (after the last closed day, normally today-1 and today):
--    fully replaced every 15 minutes (bet statuses still change there).
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS bi_sandbox.bi_total_eg_bets_recent
AS bi_sandbox.bi_total_eg_bets
ENGINE = MergeTree
PARTITION BY toYYYYMM(bet_date)
ORDER BY (bet_date, wl_id, game_id, mongo_id);
