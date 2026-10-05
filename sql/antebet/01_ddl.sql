-- =====================================================================
-- Antebet report: migration from Tableau to ClickHouse (ProdCH)
-- Schema: adam_sandbox
--
-- Layers:
--   1. bi_antebet_rounds (AggregatingMergeTree, ONE ROW PER ROUND)
--        <- bi_antebet_rounds_mv        (incremental MV on platform.slot_actions)
--        <- bi_antebet_rounds_extra_mv  (incremental MV on platform.mysql_slot_actions_extra)
--      Real time, insensitive to arrival order (the extra row reaches
--      ClickHouse ~40-70 s after slot_actions, freespin wins come up to
--      several hours after the bet).
--   2. bi_antebet_report         (closed days, <= today-2)  <- bi_antebet_mv        (refresh once a day, APPEND)
--      bi_antebet_report_recent  (open days)                <- bi_antebet_recent_mv (refresh every 15 min, atomic swap)
--   3. bi_antebet_report_v (VIEW = report + recent)  ->  Tableau
--
-- Deployment order: see 02_backfill.sql.
-- =====================================================================

CREATE DATABASE IF NOT EXISTS adam_sandbox;

-- ---------------------------------------------------------------------
-- 1. Round level (state)
--    Two sources write into the same row of the round; columns that one
--    source does not know get a neutral value ('' / 0 / NULL), and
--    max/min/sum merge them.
--    action_date = Warsaw date of the ACTION (not of the round). It is only
--    for pruning; a round that crosses midnight has 2 rows, and the read
--    query merges them with GROUP BY roundNumId, playerMongoId.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS adam_sandbox.bi_antebet_rounds
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

    -- from mysql_slot_actions_extra (finalContext of the bet action)
    ante_bet         SimpleAggregateFunction(max, Float64),
    bonus_type       SimpleAggregateFunction(max, LowCardinality(String))
)
ENGINE = AggregatingMergeTree
PARTITION BY toYYYYMM(action_date)
ORDER BY (action_date, roundNumId, playerMongoId)
-- Optional: closed days are already in bi_antebet_report, so the round
-- layer is needed only for the last few days (and for any re-backfill).
-- TTL action_date + INTERVAL 35 DAY
;

-- ---------------------------------------------------------------------
-- 1a. MV: slot_actions -> rounds
--     IMPORTANT: this MV runs on the insert path of platform.slot_actions,
--     so an error here = an error in the production insert. That is why
--     it has no dictGet / JOIN / casts that can throw: the currency
--     (isFun) and whitelabel (isTest) filters are applied only in layer 2.
--     The data shows that COMPLETED/FINALIZED rows are written once
--     (no versions), so filtering on status at insert time is safe.
--     Replace the cutoff with the actual deployment time (see 02_backfill.sql).
-- ---------------------------------------------------------------------
CREATE MATERIALIZED VIEW IF NOT EXISTS adam_sandbox.bi_antebet_rounds_mv
TO adam_sandbox.bi_antebet_rounds
AS
SELECT
    toDate(toTimezone(createdAt, 'Europe/Warsaw')) AS action_date,
    roundNumId,
    toString(playerMongoId)                         AS playerMongoId,
    max(wlId)                                       AS wlId,
    max(gameId)                                     AS gameId,
    max(wlUserId)                                   AS wlUserId,
    max(currency)                                   AS currency,
    min(createdAt)                                  AS first_action_at,
    count()                                         AS actions_cnt,
    sum(convertedBet)                               AS round_bet,
    sum(convertedWin)                               AS round_win,
    max(actionName = 'buy_spin')                    AS has_buy_spin,
    toFloat64(0)                                    AS ante_bet,
    ''                                              AS bonus_type
FROM platform.slot_actions
WHERE status IN ('COMPLETED', 'FINALIZED')
  AND createdAt >= '2026-10-06 00:00:00'          -- <CUTOFF> (UTC)
GROUP BY action_date, roundNumId, playerMongoId;

-- ---------------------------------------------------------------------
-- 1b. MV: mysql_slot_actions_extra -> rounds
--     The round's category comes from the context of the bet action
--     (spin / buy_spin = the first action of the round in 99.99% of cases).
--     A row with ante_bet = 0 and an empty bonus_type gives the same result
--     as no row at all, so only rows that carry information are written
--     (~6% of bet actions).
--     The key (roundNumId, playerMongoId) is in both tables, so no JOIN is
--     needed at insert time and arrival order does not matter.
-- ---------------------------------------------------------------------
CREATE MATERIALIZED VIEW IF NOT EXISTS adam_sandbox.bi_antebet_rounds_extra_mv
TO adam_sandbox.bi_antebet_rounds
AS
SELECT
    action_date,
    roundNumId,
    playerMongoId,
    ''                                           AS wlId,
    ''                                           AS gameId,
    ''                                           AS wlUserId,
    ''                                           AS currency,
    CAST(NULL AS Nullable(DateTime64(6, 'UTC'))) AS first_action_at,
    toUInt64(0)                                  AS actions_cnt,
    toDecimal128(0, 4)                           AS round_bet,
    toDecimal128(0, 4)                           AS round_win,
    toUInt8(0)                                   AS has_buy_spin,
    ante_bet,
    bonus_type
FROM
(
    SELECT
        toDate(toTimezone(createdAt, 'Europe/Warsaw'))      AS action_date,
        roundNumId,
        playerMongoId,
        JSONExtractFloat(finalContext, 'spins', 'ante_bet')    AS ante_bet,
        JSONExtractString(finalContext, 'spins', 'bonus_type') AS bonus_type
    FROM platform.mysql_slot_actions_extra
    WHERE _peerdb_is_deleted = 0
      AND actionName IN ('spin', 'buy_spin')
      AND createdAt >= '2026-10-06 00:00:00'      -- <CUTOFF> (UTC), same as in 1a
)
WHERE ante_bet > 0 OR bonus_type != '';

-- ---------------------------------------------------------------------
-- 2. Report level (grain of the original Tableau script)
--    RTP is stored per row for compatibility; in Tableau, compute it as
--    SUM(total_win) / SUM(total_bet_amount), not as AVG(RTP).
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS adam_sandbox.bi_antebet_report
(
    report_date          Date,
    wl_name              LowCardinality(String),
    game_name            LowCardinality(String),
    wlUserId             String,
    spin_category        LowCardinality(String),
    ante_bet_multiplier  Float64,
    bonus_type           LowCardinality(String),
    total_rounds         UInt64,
    total_bet_amount     Decimal(38, 4),
    total_win            Decimal(38, 4),
    GGR                  Decimal(38, 4),
    RTP                  Float64,
    refreshed_at         DateTime
)
ENGINE = ReplacingMergeTree(refreshed_at)   -- protects against a repeated backfill of the same day
PARTITION BY toYYYYMM(report_date)
ORDER BY (report_date, wl_name, game_name, spin_category, bonus_type, ante_bet_multiplier, wlUserId);

CREATE TABLE IF NOT EXISTS adam_sandbox.bi_antebet_report_recent
AS adam_sandbox.bi_antebet_report
ENGINE = MergeTree
ORDER BY (report_date, wl_name, game_name, spin_category, bonus_type, ante_bet_multiplier, wlUserId);

-- ---------------------------------------------------------------------
-- 2a. Closed days -> bi_antebet_report
--     Once a day at 01:00 UTC (after Warsaw midnight). It appends every day
--     in (max(report_date) in the table, today-2], so it catches up on its
--     own after a missed run. Rounds last at most ~22 h, so day today-2 is
--     already final. The lower bound today-7 guards against an accidental
--     full scan when the table is empty: run the history backfill BEFORE
--     creating this MV.
-- ---------------------------------------------------------------------
CREATE MATERIALIZED VIEW IF NOT EXISTS adam_sandbox.bi_antebet_mv
REFRESH EVERY 1 DAY OFFSET 1 HOUR
APPEND TO adam_sandbox.bi_antebet_report
AS
WITH
    toDate(now(), 'Europe/Warsaw')                                                       AS today,
    greatest((SELECT max(report_date) FROM adam_sandbox.bi_antebet_report) + 1, today - 7) AS date_from,
    today - 2                                                                            AS date_to
SELECT
    report_date,
    dictGet('platform.whitelabels_d', 'name', tuple(wl_id))   AS wl_name,
    game_name,
    wlUserId,
    multiIf(
        has_buy_spin = 1 OR ante_bet_multiplier >= 50, '3. Buy Bonus',
        ante_bet_multiplier > 0,                       '2. Ante Bet',
                                                       '1. Regular Spin'
    )                                                          AS spin_category,
    ante_bet_multiplier,
    if(raw_bonus_type != '', raw_bonus_type, 'regular game')   AS bonus_type,
    count()                                                    AS total_rounds,
    sum(round_bet)                                             AS total_bet_amount,
    sum(round_win)                                             AS total_win,
    total_bet_amount - total_win                               AS GGR,
    if(total_bet_amount > 0, toFloat64(total_win) / toFloat64(total_bet_amount), 0) AS RTP,
    now()                                                      AS refreshed_at
FROM
(
    SELECT
        toDate(toTimezone(assumeNotNull(min(first_action_at)), 'Europe/Warsaw')) AS report_date,
        max(wlId)        AS wl_id,
        max(gameId)      AS game_name,
        max(wlUserId)    AS wlUserId,
        max(currency)    AS cur,
        sum(round_bet)   AS round_bet,
        sum(round_win)   AS round_win,
        max(has_buy_spin) AS has_buy_spin,
        max(ante_bet)    AS ante_bet_multiplier,
        max(bonus_type)  AS raw_bonus_type
    FROM adam_sandbox.bi_antebet_rounds
    WHERE action_date BETWEEN date_from - 1 AND date_to + 1   -- +-1 day: rounds that cross midnight
    GROUP BY roundNumId, playerMongoId
    HAVING sum(actions_cnt) > 0                               -- the round must have a slot_actions part
       AND report_date BETWEEN date_from AND date_to
)
WHERE dictHas('platform.currency_d', tuple(cur))
  AND dictGetUInt8('platform.currency_d', 'isFun', tuple(cur)) = 0
  AND dictHas('platform.whitelabels_d', tuple(wl_id))
  AND dictGetUInt8('platform.whitelabels_d', 'isTest', tuple(wl_id)) = 0
GROUP BY report_date, wl_name, game_name, wlUserId, spin_category, ante_bet_multiplier, bonus_type
SETTINGS max_bytes_before_external_group_by = 8000000000;

-- ---------------------------------------------------------------------
-- 2b. Open days -> bi_antebet_report_recent
--     Every 15 minutes it recomputes ALL days after the last closed one
--     (normally today-1 and today; for ~2 h after midnight also today-2)
--     and atomically replaces the table (no APPEND). That way a round whose
--     category changes (extra arrived later) leaves no stale rows behind.
-- ---------------------------------------------------------------------
CREATE MATERIALIZED VIEW IF NOT EXISTS adam_sandbox.bi_antebet_recent_mv
REFRESH EVERY 15 MINUTE
TO adam_sandbox.bi_antebet_report_recent
AS
WITH
    toDate(now(), 'Europe/Warsaw')                                                       AS today,
    greatest((SELECT max(report_date) FROM adam_sandbox.bi_antebet_report) + 1, today - 3) AS date_from,
    today                                                                                AS date_to
SELECT
    report_date,
    dictGet('platform.whitelabels_d', 'name', tuple(wl_id))   AS wl_name,
    game_name,
    wlUserId,
    multiIf(
        has_buy_spin = 1 OR ante_bet_multiplier >= 50, '3. Buy Bonus',
        ante_bet_multiplier > 0,                       '2. Ante Bet',
                                                       '1. Regular Spin'
    )                                                          AS spin_category,
    ante_bet_multiplier,
    if(raw_bonus_type != '', raw_bonus_type, 'regular game')   AS bonus_type,
    count()                                                    AS total_rounds,
    sum(round_bet)                                             AS total_bet_amount,
    sum(round_win)                                             AS total_win,
    total_bet_amount - total_win                               AS GGR,
    if(total_bet_amount > 0, toFloat64(total_win) / toFloat64(total_bet_amount), 0) AS RTP,
    now()                                                      AS refreshed_at
FROM
(
    SELECT
        toDate(toTimezone(assumeNotNull(min(first_action_at)), 'Europe/Warsaw')) AS report_date,
        max(wlId)        AS wl_id,
        max(gameId)      AS game_name,
        max(wlUserId)    AS wlUserId,
        max(currency)    AS cur,
        sum(round_bet)   AS round_bet,
        sum(round_win)   AS round_win,
        max(has_buy_spin) AS has_buy_spin,
        max(ante_bet)    AS ante_bet_multiplier,
        max(bonus_type)  AS raw_bonus_type
    FROM adam_sandbox.bi_antebet_rounds
    WHERE action_date >= date_from - 1
    GROUP BY roundNumId, playerMongoId
    HAVING sum(actions_cnt) > 0
       AND report_date >= date_from
)
WHERE dictHas('platform.currency_d', tuple(cur))
  AND dictGetUInt8('platform.currency_d', 'isFun', tuple(cur)) = 0
  AND dictHas('platform.whitelabels_d', tuple(wl_id))
  AND dictGetUInt8('platform.whitelabels_d', 'isTest', tuple(wl_id)) = 0
GROUP BY report_date, wl_name, game_name, wlUserId, spin_category, ante_bet_multiplier, bonus_type
SETTINGS max_bytes_before_external_group_by = 8000000000;

-- ---------------------------------------------------------------------
-- 3. View for Tableau
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW adam_sandbox.bi_antebet_report_v AS
SELECT * EXCEPT refreshed_at
FROM adam_sandbox.bi_antebet_report
WHERE report_date <= (SELECT max(report_date) FROM adam_sandbox.bi_antebet_report)
UNION ALL
SELECT * EXCEPT refreshed_at
FROM adam_sandbox.bi_antebet_report_recent
WHERE report_date > (SELECT max(report_date) FROM adam_sandbox.bi_antebet_report);
