-- Full deployment (steps 1-4) in one file, without comments. The bi_antebet_definer user must already exist (00_definer_user.sql).

CREATE DATABASE IF NOT EXISTS bi_sandbox;

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
    has_feature      SimpleAggregateFunction(max, UInt8),

    ante_bet         SimpleAggregateFunction(max, Float64),
    bonus_type       SimpleAggregateFunction(max, LowCardinality(String)),
    buy_mode         SimpleAggregateFunction(max, LowCardinality(String))
)
ENGINE = AggregatingMergeTree
PARTITION BY toYYYYMM(action_date)
ORDER BY (action_date, roundNumId, playerMongoId)
;

CREATE TABLE IF NOT EXISTS bi_sandbox.bi_antebet_report
(
    report_date          Date,
    wl_name              LowCardinality(String),
    game_name            LowCardinality(String),
    wlUserId             String,
    spin_category        LowCardinality(String),
    ante_bet_multiplier  Float64,
    bonus_type           LowCardinality(String),
    bonus_feature        LowCardinality(String),
    total_rounds         UInt64,
    total_bet_amount     Decimal(38, 4),
    total_win            Decimal(38, 4),
    GGR                  Decimal(38, 4),
    RTP                  Float64,
    refreshed_at         DateTime
)
ENGINE = ReplacingMergeTree(refreshed_at)
PARTITION BY toYYYYMM(report_date)
ORDER BY (report_date, wl_name, game_name, spin_category, bonus_feature, bonus_type, ante_bet_multiplier, wlUserId);

CREATE TABLE IF NOT EXISTS bi_sandbox.bi_antebet_report_recent
AS bi_sandbox.bi_antebet_report
ENGINE = MergeTree
ORDER BY (report_date, wl_name, game_name, spin_category, bonus_feature, bonus_type, ante_bet_multiplier, wlUserId);

CREATE MATERIALIZED VIEW IF NOT EXISTS bi_sandbox.bi_antebet_rounds_mv
TO bi_sandbox.bi_antebet_rounds
DEFINER = bi_antebet_definer SQL SECURITY DEFINER
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
    max(actionName NOT IN ('spin', 'buy_spin'))     AS has_feature,
    toFloat64(0)                                    AS ante_bet,
    ''                                              AS bonus_type,
    ''                                              AS buy_mode
FROM platform.slot_actions
WHERE status IN ('COMPLETED', 'FINALIZED')
  AND createdAt >= '2026-10-06 12:35:00'
GROUP BY action_date, roundNumId, playerMongoId;

CREATE MATERIALIZED VIEW IF NOT EXISTS bi_sandbox.bi_antebet_rounds_extra_mv
TO bi_sandbox.bi_antebet_rounds
DEFINER = bi_antebet_definer SQL SECURITY DEFINER
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
    toUInt8(0)                                   AS has_feature,
    ante_bet,
    bonus_type,
    buy_mode
FROM
(
    SELECT
        toDate(toTimezone(createdAt, 'Europe/Warsaw'))      AS action_date,
        roundNumId,
        playerMongoId,
        JSONExtractFloat(finalContext, 'spins', 'ante_bet')    AS ante_bet,
        JSONExtractString(finalContext, 'spins', 'bonus_type') AS bonus_type,
        if(actionName = 'buy_spin', JSONExtractString(finalContext, 'last_args', 'selected_mode'), '') AS buy_mode
    FROM platform.mysql_slot_actions_extra
    WHERE _peerdb_is_deleted = 0
      AND actionName IN ('spin', 'buy_spin')
      AND createdAt >= '2026-10-06 12:35:00'
)
WHERE ante_bet > 0 OR bonus_type != '' OR buy_mode != '';

CREATE MATERIALIZED VIEW IF NOT EXISTS bi_sandbox.bi_antebet_backfill_mv
REFRESH EVERY 1 MINUTE
APPEND TO bi_sandbox.bi_antebet_rounds
DEFINER = bi_antebet_definer SQL SECURITY DEFINER
AS
WITH
    toDateTime('2026-10-06 12:35:00', 'UTC')                                    AS cutoff,
    toDate('2026-08-20')                                                        AS start_day,
    toDate(cutoff, 'Europe/Warsaw')                                             AS cutoff_day,
    ifNull((SELECT count() > 0 FROM bi_sandbox.bi_antebet_rounds
            WHERE action_date = cutoff_day AND first_action_at < cutoff), 0)    AS cutoff_day_done,
    (SELECT min(action_date) FROM bi_sandbox.bi_antebet_rounds
     WHERE action_date < cutoff_day)                                            AS hist_min_raw,
    if(hist_min_raw IS NULL OR hist_min_raw = toDate('1970-01-01'), cutoff_day, assumeNotNull(hist_min_raw)) AS hist_min,
    if(cutoff_day_done, hist_min - 1, cutoff_day)                               AS d,
    toDateTime(d, 'Europe/Warsaw')                                              AS ts_from,
    least(toDateTime(d + 1, 'Europe/Warsaw'), cutoff)                           AS ts_to,
    now() >= cutoff + INTERVAL 15 MINUTE AND d >= start_day                     AS active
SELECT
    d                                AS action_date,
    roundNumId,
    toString(playerMongoId)          AS playerMongoId,
    max(wlId)                        AS wlId,
    max(gameId)                      AS gameId,
    max(wlUserId)                    AS wlUserId,
    max(currency)                    AS currency,
    min(createdAt)                   AS first_action_at,
    count()                          AS actions_cnt,
    sum(convertedBet)                AS round_bet,
    sum(convertedWin)                AS round_win,
    max(actionName = 'buy_spin')     AS has_buy_spin,
    max(actionName NOT IN ('spin', 'buy_spin')) AS has_feature,
    toFloat64(0)                     AS ante_bet,
    ''                               AS bonus_type,
    ''                               AS buy_mode
FROM platform.slot_actions
WHERE active
  AND status IN ('COMPLETED', 'FINALIZED')
  AND createdAt >= ts_from
  AND createdAt <  ts_to
GROUP BY roundNumId, playerMongoId

UNION ALL

WITH
    toDateTime('2026-10-06 12:35:00', 'UTC')                                    AS cutoff,
    toDate('2026-08-20')                                                        AS start_day,
    toDate(cutoff, 'Europe/Warsaw')                                             AS cutoff_day,
    ifNull((SELECT count() > 0 FROM bi_sandbox.bi_antebet_rounds
            WHERE action_date = cutoff_day AND first_action_at < cutoff), 0)    AS cutoff_day_done,
    (SELECT min(action_date) FROM bi_sandbox.bi_antebet_rounds
     WHERE action_date < cutoff_day)                                            AS hist_min_raw,
    if(hist_min_raw IS NULL OR hist_min_raw = toDate('1970-01-01'), cutoff_day, assumeNotNull(hist_min_raw)) AS hist_min,
    if(cutoff_day_done, hist_min - 1, cutoff_day)                               AS d,
    toDateTime(d, 'Europe/Warsaw')                                              AS ts_from,
    least(toDateTime(d + 1, 'Europe/Warsaw'), cutoff)                           AS ts_to,
    now() >= cutoff + INTERVAL 15 MINUTE AND d >= start_day                     AS active
SELECT
    d                                            AS action_date,
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
    toUInt8(0)                                   AS has_feature,
    ante_bet,
    bonus_type,
    buy_mode
FROM
(
    SELECT
        roundNumId,
        playerMongoId,
        JSONExtractFloat(finalContext, 'spins', 'ante_bet')    AS ante_bet,
        JSONExtractString(finalContext, 'spins', 'bonus_type') AS bonus_type,
        if(actionName = 'buy_spin', JSONExtractString(finalContext, 'last_args', 'selected_mode'), '') AS buy_mode
    FROM platform.mysql_slot_actions_extra
    WHERE active
      AND _peerdb_is_deleted = 0
      AND actionName IN ('spin', 'buy_spin')
      AND createdAt < cutoff
      AND slotActionMongoId IN
      (
          SELECT toString(mongoId)
          FROM platform.slot_actions
          WHERE active
            AND createdAt >= ts_from
            AND createdAt <  ts_to
            AND status IN ('COMPLETED', 'FINALIZED')
            AND actionName IN ('spin', 'buy_spin')
      )
)
WHERE ante_bet > 0 OR bonus_type != '' OR buy_mode != ''
SETTINGS max_bytes_before_external_group_by = 8000000000;

CREATE MATERIALIZED VIEW IF NOT EXISTS bi_sandbox.bi_antebet_mv
REFRESH EVERY 5 MINUTE
APPEND TO bi_sandbox.bi_antebet_report
DEFINER = bi_antebet_definer SQL SECURITY DEFINER
AS
WITH
    toDate('2026-08-20')                                                                          AS start_day,
    toDate(now(), 'UTC')                                                                AS today,
    ifNull((SELECT count() > 0 FROM bi_sandbox.bi_antebet_rounds WHERE action_date = start_day), 0) AS backfill_done,
    greatest(ifNull((SELECT max(report_date) FROM bi_sandbox.bi_antebet_report), toDate('1970-01-01')) + 1, start_day) AS date_from,
    if(backfill_done, least(date_from + 2, today - 2), date_from - 1)                             AS date_to
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
    multiIf(
        has_buy_spin = 1,           concat('Buy mode ', if(raw_buy_mode != '', raw_buy_mode, '?')),
        ante_bet_multiplier >= 50,  'Ante >= 50',
        has_feature = 1,            'Triggered bonus',
                                    'No bonus'
    )                                                          AS bonus_feature,
    count()                                                    AS total_rounds,
    sum(round_bet)                                             AS total_bet_amount,
    sum(round_win)                                             AS total_win,
    total_bet_amount - total_win                               AS GGR,
    if(total_bet_amount > 0, toFloat64(total_win) / toFloat64(total_bet_amount), 0) AS RTP,
    now()                                                      AS refreshed_at
FROM
(
    SELECT
        toDate(assumeNotNull(min(first_action_at)), 'UTC') AS report_date,
        max(wlId)        AS wl_id,
        max(gameId)      AS game_name,
        max(wlUserId)    AS wlUserId,
        max(currency)    AS cur,
        sum(round_bet)   AS round_bet,
        sum(round_win)   AS round_win,
        max(has_buy_spin) AS has_buy_spin,
        max(ante_bet)    AS ante_bet_multiplier,
        max(bonus_type)  AS raw_bonus_type,
        max(buy_mode)    AS raw_buy_mode,
        max(has_feature) AS has_feature
    FROM bi_sandbox.bi_antebet_rounds
    WHERE date_to >= date_from
      AND action_date BETWEEN date_from - 1 AND date_to + 1
    GROUP BY roundNumId, playerMongoId
    HAVING sum(actions_cnt) > 0
       AND report_date BETWEEN date_from AND date_to
)
WHERE dictHas('platform.currency_d', tuple(cur))
  AND dictGetUInt8('platform.currency_d', 'isFun', tuple(cur)) = 0
  AND dictHas('platform.whitelabels_d', tuple(wl_id))
  AND dictGetUInt8('platform.whitelabels_d', 'isTest', tuple(wl_id)) = 0
GROUP BY report_date, wl_name, game_name, wlUserId, spin_category, ante_bet_multiplier, bonus_type, bonus_feature
SETTINGS max_bytes_before_external_group_by = 8000000000;

CREATE MATERIALIZED VIEW IF NOT EXISTS bi_sandbox.bi_antebet_recent_mv
REFRESH EVERY 15 MINUTE
TO bi_sandbox.bi_antebet_report_recent
DEFINER = bi_antebet_definer SQL SECURITY DEFINER
AS
WITH
    toDate(now(), 'UTC')                                                       AS today,
    greatest(ifNull((SELECT max(report_date) FROM bi_sandbox.bi_antebet_report), toDate('1970-01-01')) + 1, today - 3) AS date_from,
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
    multiIf(
        has_buy_spin = 1,           concat('Buy mode ', if(raw_buy_mode != '', raw_buy_mode, '?')),
        ante_bet_multiplier >= 50,  'Ante >= 50',
        has_feature = 1,            'Triggered bonus',
                                    'No bonus'
    )                                                          AS bonus_feature,
    count()                                                    AS total_rounds,
    sum(round_bet)                                             AS total_bet_amount,
    sum(round_win)                                             AS total_win,
    total_bet_amount - total_win                               AS GGR,
    if(total_bet_amount > 0, toFloat64(total_win) / toFloat64(total_bet_amount), 0) AS RTP,
    now()                                                      AS refreshed_at
FROM
(
    SELECT
        toDate(assumeNotNull(min(first_action_at)), 'UTC') AS report_date,
        max(wlId)        AS wl_id,
        max(gameId)      AS game_name,
        max(wlUserId)    AS wlUserId,
        max(currency)    AS cur,
        sum(round_bet)   AS round_bet,
        sum(round_win)   AS round_win,
        max(has_buy_spin) AS has_buy_spin,
        max(ante_bet)    AS ante_bet_multiplier,
        max(bonus_type)  AS raw_bonus_type,
        max(buy_mode)    AS raw_buy_mode,
        max(has_feature) AS has_feature
    FROM bi_sandbox.bi_antebet_rounds
    WHERE action_date >= date_from - 1
    GROUP BY roundNumId, playerMongoId
    HAVING sum(actions_cnt) > 0
       AND report_date >= date_from
)
WHERE dictHas('platform.currency_d', tuple(cur))
  AND dictGetUInt8('platform.currency_d', 'isFun', tuple(cur)) = 0
  AND dictHas('platform.whitelabels_d', tuple(wl_id))
  AND dictGetUInt8('platform.whitelabels_d', 'isTest', tuple(wl_id)) = 0
GROUP BY report_date, wl_name, game_name, wlUserId, spin_category, ante_bet_multiplier, bonus_type, bonus_feature
SETTINGS max_bytes_before_external_group_by = 8000000000;

CREATE OR REPLACE VIEW bi_sandbox.bi_antebet_report_v AS
SELECT * EXCEPT refreshed_at
FROM bi_sandbox.bi_antebet_report
WHERE report_date <= (SELECT max(report_date) FROM bi_sandbox.bi_antebet_report)
UNION ALL
SELECT * EXCEPT refreshed_at
FROM bi_sandbox.bi_antebet_report_recent
WHERE report_date > (SELECT max(report_date) FROM bi_sandbox.bi_antebet_report);
