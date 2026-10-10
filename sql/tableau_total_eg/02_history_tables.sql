-- Step 3a. Technical user + the hourly table for the full history (Live + Slots).
--
-- Grain (1 row): hour (UTC) x product x casino x game x currency x country x player
--                x session (token) x status x free-spin context
--                + live: round   + slots: action name.
-- No single-bet information: `bets` = number of unique bets, `slot_rounds` = number of
-- slot rounds. Players, sessions and live rounds are part of the grain, so their COUNTD
-- stays exact at every level of a dashboard.
--
-- Size (ProdCH, 2026-10-09): live 62.5 k bets -> ~62 k rows/day (a live round is shared by
-- many players, so it has to stay in the grain), slots 22.3 M actions -> ~0.5 M rows/day.
-- History: live ~36 M rows since 2022-12, slots ~0.35 bn rows since 2024-10 (~45x fewer
-- rows than slot_actions).
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
GRANT SELECT  ON platform.slot_actions       TO bi_total_eg_definer;
GRANT SELECT  ON platform.partners_d         TO bi_total_eg_definer;   -- read as a table (wls list)
GRANT dictGet ON platform.partners_d         TO bi_total_eg_definer;
GRANT dictGet ON platform.whitelabels_d      TO bi_total_eg_definer;
GRANT dictGet ON platform.currency_d         TO bi_total_eg_definer;
GRANT dictGet ON bi_sandbox.country_names_d  TO bi_total_eg_definer;
-- CREATE/DROP TABLE: a refresh without APPEND builds a temporary table and swaps it
GRANT SELECT, INSERT, CREATE TABLE, DROP TABLE, TRUNCATE ON bi_sandbox.* TO bi_total_eg_definer;

-- ---------------------------------------------------------------------
-- 1. Closed days (<= today-2 UTC): appended once per day and product, never rewritten.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS bi_sandbox.bi_total_eg_hourly
(
    product                    LowCardinality(String),              -- 'Live' / 'Slots'
    hour                       DateTime('UTC'),
    bet_date                   Date,                                -- toDate(hour), UTC

    wl_id                      LowCardinality(String),
    wl_name                    LowCardinality(String),
    wl_label                   LowCardinality(String),
    wl_is_test                 UInt8,
    partner_name               LowCardinality(Nullable(String)),
    wl_user_id                 String,
    player_mongo_id            String,
    token_mongo_id             String,                              -- session

    game_id                    LowCardinality(String),
    country                    LowCardinality(String),
    country_name               LowCardinality(String),

    currency                   LowCardinality(String),
    currency_title             LowCardinality(String),
    currency_type              LowCardinality(String),
    is_fun                     UInt8,

    status                     LowCardinality(String),
    free_spins                 Nullable(String),                    -- free-spin grant id
    freespin_transaction_mode  LowCardinality(Nullable(String)),

    round_mongo_id             String,                              -- live round; '' for slots
    action_name                LowCardinality(String),              -- slot action; '' for live
    autoplay                   Nullable(String),                    -- live only

    bets                       UInt64,                              -- unique bets
    slot_rounds                Nullable(UInt64),                    -- slot rounds (counted on the starting action); NULL for live
    bet_size                   Decimal(38, 12),                     -- sum, player currency
    won                        Decimal(38, 12),                     -- sum, player currency
    converted_bet              Decimal(38, 4),                      -- sum, EUR
    converted_win              Decimal(38, 4),                      -- sum, EUR
    last_updated_at            DateTime64(6, 'UTC'),                -- max(updatedAt) of the row
    last_status_updated_at     DateTime64(6, 'UTC'),                -- max(statusUpdatedAt) of the row

    loaded_at                  DateTime DEFAULT now()
)
ENGINE = MergeTree
PARTITION BY toYYYYMM(bet_date)
ORDER BY (bet_date, product, wl_id, game_id, hour);

-- ---------------------------------------------------------------------
-- 2. Open days (after the last closed day of each product, normally today-1 and today):
--    fully replaced every 15 minutes (statuses still change there).
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS bi_sandbox.bi_total_eg_hourly_recent
AS bi_sandbox.bi_total_eg_hourly
ENGINE = MergeTree
PARTITION BY toYYYYMM(bet_date)
ORDER BY (bet_date, product, wl_id, game_id, hour);

-- Upgrading from the first version of this folder (bet-level, live only):
-- DROP VIEW IF EXISTS bi_sandbox.bi_total_eg_bets_mv;
-- DROP VIEW IF EXISTS bi_sandbox.bi_total_eg_bets_recent_mv;
-- DROP TABLE IF EXISTS bi_sandbox.bi_total_eg_bets;
-- DROP TABLE IF EXISTS bi_sandbox.bi_total_eg_bets_recent;
