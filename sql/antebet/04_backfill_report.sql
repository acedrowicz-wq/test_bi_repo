-- Step 4. Report backfill for closed days (the body of bi_antebet_mv with fixed bounds).
-- Parameters: {date_from:Date}, {date_to:Date} (Warsaw dates, inclusive), at most ~7 days at a time,
-- up to and including today-2. run_backfill.sh does this automatically.

INSERT INTO adam_sandbox.bi_antebet_report
WITH
    {date_from:Date} AS date_from,
    {date_to:Date}   AS date_to
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
