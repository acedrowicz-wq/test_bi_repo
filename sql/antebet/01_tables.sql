-- =====================================================================
-- Antebet report: migration from Tableau to ClickHouse (ProdCH)
-- Schema: bi_sandbox
--
-- Layers:
--   1. bi_antebet_rounds (AggregatingMergeTree, ONE ROW PER ROUND)
--        <- bi_antebet_rounds_mv        (incremental MV on platform.slot_actions)
--        <- bi_antebet_rounds_extra_mv  (incremental MV on platform.mysql_slot_actions_extra)
--      Real time, insensitive to arrival order (the extra row reaches
--      ClickHouse ~40-70 s after slot_actions, freespin wins come up to
--      several hours after the bet).
--      <- bi_antebet_backfill_mv      (one-off history, does itself 1 day/min)
--   2. bi_antebet_report         (closed days, <= today-2)  <- bi_antebet_mv        (refresh every 15 min, APPEND)
--      bi_antebet_report_recent  (open days)                <- bi_antebet_recent_mv (refresh every 15 min, atomic swap)
--   3. bi_antebet_report_v (VIEW = report + recent)  ->  Tableau
--
-- Step 1. Deployment order: see README.md.
-- =====================================================================

CREATE DATABASE IF NOT EXISTS bi_sandbox;

-- ---------------------------------------------------------------------
-- 1. Round level (state)
--    Two sources write into the same row of the round; columns that one
--    source does not know get a neutral value ('' / 0 / NULL), and
--    max/min/sum merge them.
--    action_date = Warsaw date of the ACTION (not of the round, and not the report day:
--    the report counts the UTC day, see 04). It is only
--    for pruning; a round that crosses midnight has 2 rows, and the read
--    query merges them with GROUP BY roundNumId, playerMongoId.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS bi_sandbox.bi_antebet_rounds
(
    action_date      Date,
    roundNumId       String,
    playerMongoId    String,

    wlId             SimpleAggregateFunction(max, LowCardinality(String)),
    gameId           SimpleAggregateFunction(max, LowCardinality(String)),
    wlUserId         SimpleAggregateFunction(max, String),
    currency         SimpleAggregateFunction(max, LowCardinality(String)),
    first_action_at  SimpleAggregateFunction(min, Nullable(DateTime64(6, 'UTC'))),
    actions_cnt      SimpleAggregateFunction(sum, UInt64),
    round_bet        SimpleAggregateFunction(sum, Decimal(38, 4)),
    round_win        SimpleAggregateFunction(sum, Decimal(38, 4)),
    has_buy_spin     SimpleAggregateFunction(max, UInt8),
    has_feature      SimpleAggregateFunction(max, UInt8),     -- round has bonus actions (respin / freespin / bonus_spins_stop ...)

    -- from mysql_slot_actions_extra (finalContext of the bet action)
    ante_bet         SimpleAggregateFunction(max, Float64),
    bonus_type       SimpleAggregateFunction(max, LowCardinality(String)),
    buy_mode         SimpleAggregateFunction(max, LowCardinality(String))   -- last_args.selected_mode of buy_spin
)
ENGINE = AggregatingMergeTree
PARTITION BY toYYYYMM(action_date)
ORDER BY (action_date, roundNumId, playerMongoId)
-- Optional: closed days are already in bi_antebet_report, so the round
-- layer is needed only for the last few days (and for any re-backfill).
-- TTL action_date + INTERVAL 35 DAY
;

-- ---------------------------------------------------------------------
-- 2. Report level (grain of the original Tableau script)
--    RTP is stored per row for compatibility; in Tableau, compute it as
--    SUM(total_win) / SUM(total_bet_amount), not as AVG(RTP).
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS bi_sandbox.bi_antebet_report
(
    report_date          Date,
    wl_name              LowCardinality(String),
    game_name            LowCardinality(String),
    wlUserId             String,
    spin_category        LowCardinality(String),
    ante_bet_multiplier  Float64,
    bonus_type           LowCardinality(String),
    bonus_feature        LowCardinality(String),   -- Buy mode N / Ante >= 50 / Triggered bonus / No bonus
    total_rounds         UInt64,
    total_bet_amount     Decimal(38, 4),
    total_win            Decimal(38, 4),
    GGR                  Decimal(38, 4),
    RTP                  Float64,
    refreshed_at         DateTime
)
ENGINE = ReplacingMergeTree(refreshed_at)   -- protects against a repeated backfill of the same day
PARTITION BY toYYYYMM(report_date)
ORDER BY (report_date, wl_name, game_name, spin_category, bonus_feature, bonus_type, ante_bet_multiplier, wlUserId);

CREATE TABLE IF NOT EXISTS bi_sandbox.bi_antebet_report_recent
AS bi_sandbox.bi_antebet_report
ENGINE = MergeTree
ORDER BY (report_date, wl_name, game_name, spin_category, bonus_feature, bonus_type, ante_bet_multiplier, wlUserId);
