-- Step 3. Automatic round backfill for history (period before <CUTOFF>).
--
-- A refreshable MV that does ONE Warsaw day per run, going backwards:
--   1st run: the day of <CUTOFF>, from Warsaw midnight up to <CUTOFF>
--            (the incremental MVs from step 2 write from <CUTOFF> onwards),
--   then:    min(action_date) of days before the <CUTOFF> day - 1, down to start_day.
-- "The <CUTOFF> day is done" = there are rows for that day with first_action_at < <CUTOFF>
-- (rows from the incremental MVs have first_action_at >= <CUTOFF> or NULL).
-- It starts on its own 15 min after <CUTOFF> (PeerDB lag). One day takes ~45-60 s,
-- so it runs every minute; 47 days take ~1 h. After that every run does nothing.
--
-- action_date is set to the processed day d (not computed from createdAt).
-- Repair if any day D (< the <CUTOFF> day) loaded with an error:
--   DELETE FROM bi_sandbox.bi_antebet_rounds WHERE action_date <= 'D';
-- and the MV will reload that day and all earlier days by itself.
--
-- <CUTOFF> and start_day must be identical in BOTH branches of the UNION
-- and the same as in 02_incremental_mvs.sql.

CREATE MATERIALIZED VIEW IF NOT EXISTS bi_sandbox.bi_antebet_backfill_mv
REFRESH EVERY 1 MINUTE
APPEND TO bi_sandbox.bi_antebet_rounds
DEFINER = bi_antebet_definer SQL SECURITY DEFINER
AS
-- (a) slot_actions: amounts and dimensions
WITH
    toDateTime('2026-10-06 12:35:00', 'UTC')                                    AS cutoff,     -- <CUTOFF>
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

-- (b) mysql_slot_actions_extra: ante_bet / bonus_type of the bet actions from the same day
WITH
    toDateTime('2026-10-06 12:35:00', 'UTC')                                    AS cutoff,     -- <CUTOFF>
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
      AND createdAt < cutoff                       -- rows >= CUTOFF are written by the incremental MV
      AND slotActionMongoId IN
      (
          SELECT toString(mongoId)
          FROM platform.slot_actions
          WHERE active                             -- once finished, this set is not built either
            AND createdAt >= ts_from
            AND createdAt <  ts_to
            AND status IN ('COMPLETED', 'FINALIZED')
            AND actionName IN ('spin', 'buy_spin')
      )
)
WHERE ante_bet > 0 OR bonus_type != '' OR buy_mode != ''
SETTINGS max_bytes_before_external_group_by = 8000000000;
