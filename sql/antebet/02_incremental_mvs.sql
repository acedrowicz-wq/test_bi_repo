-- Step 2. Incremental MVs. <CUTOFF> (both places) = a Warsaw midnight LATER than the time you create them, written in UTC (22:00 in summer time, 23:00 in winter time).

-- ---------------------------------------------------------------------
-- 1a. MV: slot_actions -> rounds
--     IMPORTANT: this MV runs on the insert path of platform.slot_actions,
--     so an error here = an error in the production insert. That is why
--     it has no dictGet / JOIN / casts that can throw: the currency
--     (isFun) and whitelabel (isTest) filters are applied only in layer 2.
--     The data shows that COMPLETED/FINALIZED rows are written once
--     (no versions), so filtering on status at insert time is safe.
--     <CUTOFF>: see README.md, step 2.
-- ---------------------------------------------------------------------
CREATE MATERIALIZED VIEW IF NOT EXISTS adam_sandbox.bi_antebet_rounds_mv
TO adam_sandbox.bi_antebet_rounds
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
    toFloat64(0)                                    AS ante_bet,
    ''                                              AS bonus_type
FROM platform.slot_actions
WHERE status IN ('COMPLETED', 'FINALIZED')
  AND createdAt >= '2026-10-05 22:00:00'          -- <CUTOFF> (UTC) = 2026-10-06 00:00 Warsaw
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
      AND createdAt >= '2026-10-05 22:00:00'      -- <CUTOFF> (UTC), same as in 1a
)
WHERE ante_bet > 0 OR bonus_type != '';
