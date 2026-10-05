-- Step 3. Automatic round backfill for history (period before <CUTOFF>).
--
-- A refreshable MV that does ONE Warsaw day per run, going backwards
-- from <CUTOFF> to start_day:
--   next day = min(action_date) in bi_antebet_rounds - 1
-- The incremental MVs (step 2) start writing at <CUTOFF> (= a Warsaw
-- midnight), so the first day done is the day before <CUTOFF>, then the one
-- before that, and so on. It starts on its own 15 min after <CUTOFF> (PeerDB lag).
-- One day takes ~45-60 s, so it runs every minute; 47 days take ~1 h.
-- After it reaches start_day, every run does nothing (cost ~0); you
-- can drop it, but you do not have to.
--
-- action_date is set to the processed day d (not computed from createdAt),
-- so "min(action_date)" moves exactly one day per run.
-- Repair if any day loaded with an error (see README, "Checks"):
--   DELETE FROM adam_sandbox.bi_antebet_rounds WHERE action_date <= '<bad day>';
-- and the MV will reload that day and all earlier days by itself.
--
-- <CUTOFF> and start_day must be identical in BOTH branches of the UNION
-- and the same as in 02_incremental_mvs.sql.

CREATE MATERIALIZED VIEW IF NOT EXISTS adam_sandbox.bi_antebet_backfill_mv
REFRESH EVERY 1 MINUTE
APPEND TO adam_sandbox.bi_antebet_rounds
DEFINER = bi_antebet_definer SQL SECURITY DEFINER
AS
-- (a) slot_actions: amounts and dimensions
WITH
    toDateTime('2026-10-05 22:00:00', 'UTC')                                    AS cutoff,     -- <CUTOFF>
    toDate('2026-08-20')                                                        AS start_day,
    ifNull((SELECT min(action_date) FROM adam_sandbox.bi_antebet_rounds), toDate('1970-01-01')) AS min_day,
    min_day - 1                                                                 AS d,
    toDateTime(d, 'Europe/Warsaw')                                              AS ts_from,
    least(toDateTime(d + 1, 'Europe/Warsaw'), cutoff)                           AS ts_to,
    now() >= cutoff + INTERVAL 15 MINUTE AND min_day > start_day                AS active
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
    toFloat64(0)                     AS ante_bet,
    ''                               AS bonus_type
FROM platform.slot_actions
WHERE active
  AND status IN ('COMPLETED', 'FINALIZED')
  AND createdAt >= ts_from
  AND createdAt <  ts_to
GROUP BY roundNumId, playerMongoId

UNION ALL

-- (b) mysql_slot_actions_extra: ante_bet / bonus_type of the bet actions from the same day
WITH
    toDateTime('2026-10-05 22:00:00', 'UTC')                                    AS cutoff,     -- <CUTOFF>
    toDate('2026-08-20')                                                        AS start_day,
    ifNull((SELECT min(action_date) FROM adam_sandbox.bi_antebet_rounds), toDate('1970-01-01')) AS min_day,
    min_day - 1                                                                 AS d,
    toDateTime(d, 'Europe/Warsaw')                                              AS ts_from,
    least(toDateTime(d + 1, 'Europe/Warsaw'), cutoff)                           AS ts_to,
    now() >= cutoff + INTERVAL 15 MINUTE AND min_day > start_day                AS active
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
    ante_bet,
    bonus_type
FROM
(
    SELECT
        roundNumId,
        playerMongoId,
        JSONExtractFloat(finalContext, 'spins', 'ante_bet')    AS ante_bet,
        JSONExtractString(finalContext, 'spins', 'bonus_type') AS bonus_type
    FROM platform.mysql_slot_actions_extra
    WHERE active
      AND _peerdb_is_deleted = 0
      AND actionName IN ('spin', 'buy_spin')
      AND createdAt < cutoff                       -- rows >= CUTOFF are written by the incremental MV
      AND slotActionMongoId IN
      (
          SELECT toString(mongoId)
          FROM platform.slot_actions
          WHERE createdAt >= ts_from
            AND createdAt <  ts_to
            AND status IN ('COMPLETED', 'FINALIZED')
            AND actionName IN ('spin', 'buy_spin')
      )
)
WHERE ante_bet > 0 OR bonus_type != ''
SETTINGS max_bytes_before_external_group_by = 8000000000;
