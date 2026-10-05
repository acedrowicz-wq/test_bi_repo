-- Step 3. Round backfill for the period before <CUTOFF>.
-- Parameters (UTC): {ts_from:DateTime}, {ts_to:DateTime} = one chunk (1 day; the last one ends at <CUTOFF>),
--                   {cutoff:DateTime} = the same <CUTOFF> as in 02_incremental_mvs.sql.
-- Start only after <CUTOFF> + ~15 min (PeerDB lag). run_backfill.sh does this automatically.

-- A. Rounds from slot_actions (same SELECT as in bi_antebet_rounds_mv)
INSERT INTO adam_sandbox.bi_antebet_rounds
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
  AND createdAt >= {ts_from:DateTime}
  AND createdAt <  {ts_to:DateTime}
GROUP BY action_date, roundNumId, playerMongoId;

-- B. Rounds from mysql_slot_actions_extra
--    The table has 1.34 TiB and is sorted by slotActionMongoId, so it is
--    narrowed with IN on the ids of that day's bet actions (primary key lookup).
INSERT INTO adam_sandbox.bi_antebet_rounds
SELECT
    action_date, roundNumId, playerMongoId,
    '', '', '', '',
    CAST(NULL AS Nullable(DateTime64(6, 'UTC'))),
    toUInt64(0), toDecimal128(0, 4), toDecimal128(0, 4), toUInt8(0),
    ante_bet, bonus_type
FROM
(
    SELECT
        toDate(toTimezone(createdAt, 'Europe/Warsaw'))         AS action_date,
        roundNumId,
        playerMongoId,
        JSONExtractFloat(finalContext, 'spins', 'ante_bet')    AS ante_bet,
        JSONExtractString(finalContext, 'spins', 'bonus_type') AS bonus_type
    FROM platform.mysql_slot_actions_extra
    WHERE _peerdb_is_deleted = 0
      AND actionName IN ('spin', 'buy_spin')
      AND createdAt < {cutoff:DateTime}           -- does not duplicate rows from the MV
      AND slotActionMongoId IN
      (
          SELECT toString(mongoId)
          FROM platform.slot_actions
          WHERE createdAt >= {ts_from:DateTime}
            AND createdAt <  {ts_to:DateTime}
            AND status IN ('COMPLETED', 'FINALIZED')
            AND actionName IN ('spin', 'buy_spin')
      )
)
WHERE ante_bet > 0 OR bonus_type != '';
