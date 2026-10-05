-- Step 4. Report MVs and the Tableau view. They can be created right after step 3;
-- they wait on their own until the round backfill (bi_antebet_backfill_mv) has finished.

-- ---------------------------------------------------------------------
-- 2a. Closed days -> bi_antebet_report
--     Every 15 minutes it appends the next days after max(report_date)
--     in the table, at most 3 days per run, up to today-2 (rounds last
--     at most ~22 h, so today-2 is already final).
--     - Empty table: it starts from start_day (2026-08-20).
--     - It does NOTHING until the round backfill has reached start_day
--       (bi_antebet_rounds has rows with action_date <= start_day).
--     So the history fills itself in (~16 runs = ~4 h after the round
--     backfill), and then each day is appended once, by the first
--     run after Warsaw midnight. A missed run catches up by itself.
-- ---------------------------------------------------------------------
CREATE MATERIALIZED VIEW IF NOT EXISTS bi_sandbox.bi_antebet_mv
REFRESH EVERY 15 MINUTE
APPEND TO bi_sandbox.bi_antebet_report
DEFINER = bi_antebet_definer SQL SECURITY DEFINER
AS
WITH
    toDate('2026-08-20')                                                                          AS start_day,
    toDate(now(), 'Europe/Warsaw')                                                                AS today,
    (SELECT countIf(action_date <= start_day) > 0 FROM bi_sandbox.bi_antebet_rounds)            AS backfill_done,
    greatest(ifNull((SELECT max(report_date) FROM bi_sandbox.bi_antebet_report), toDate('1970-01-01')) + 1, start_day) AS date_from,
    if(backfill_done, least(date_from + 2, today - 2), date_from - 1)                             AS date_to   -- date_to < date_from = nothing to do
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
    FROM bi_sandbox.bi_antebet_rounds
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
CREATE MATERIALIZED VIEW IF NOT EXISTS bi_sandbox.bi_antebet_recent_mv
REFRESH EVERY 15 MINUTE
TO bi_sandbox.bi_antebet_report_recent
DEFINER = bi_antebet_definer SQL SECURITY DEFINER
AS
WITH
    toDate(now(), 'Europe/Warsaw')                                                       AS today,
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
GROUP BY report_date, wl_name, game_name, wlUserId, spin_category, ante_bet_multiplier, bonus_type
SETTINGS max_bytes_before_external_group_by = 8000000000;

-- ---------------------------------------------------------------------
-- 3. View for Tableau
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW bi_sandbox.bi_antebet_report_v AS
SELECT * EXCEPT refreshed_at
FROM bi_sandbox.bi_antebet_report
WHERE report_date <= (SELECT max(report_date) FROM bi_sandbox.bi_antebet_report)
UNION ALL
SELECT * EXCEPT refreshed_at
FROM bi_sandbox.bi_antebet_report_recent
WHERE report_date > (SELECT max(report_date) FROM bi_sandbox.bi_antebet_report);
