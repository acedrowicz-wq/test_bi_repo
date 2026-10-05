-- =====================================================================
-- Antebet: deployment order and backfill
--
-- 0. Test on StagePlatformCH first. The MVs from step 2 run on the insert
--    path of platform.slot_actions / platform.mysql_slot_actions_extra,
--    so it is worth agreeing this with the platform owner.
-- 1. 01_ddl.sql: CREATE DATABASE + the tables (bi_antebet_rounds,
--    bi_antebet_report, bi_antebet_report_recent).
-- 2. 01_ddl.sql: the incremental MVs (bi_antebet_rounds_mv,
--    bi_antebet_rounds_extra_mv), with <CUTOFF> set to a moment
--    LATER than the time you create them (e.g. the next full hour).
-- 3. After <CUTOFF> + ~15 min (PeerDB lag): backfill the rounds < <CUTOFF> (A, B).
-- 4. Backfill the report for closed days (C).
-- 5. 01_ddl.sql: the refreshable MVs (bi_antebet_mv, bi_antebet_recent_mv) + the view.
--
-- Run A and B day by day (on ProdCH, one day of B takes ~30-60 s).
-- {d:Date} = the day being processed (UTC); for the last day, use <CUTOFF>
-- as the upper bound.
-- =====================================================================

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
  AND createdAt >= {d:Date}
  AND createdAt <  {d:Date} + 1                   -- last day: < <CUTOFF>
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
      AND createdAt < '2026-10-06 00:00:00'       -- <CUTOFF>: does not duplicate rows from the MV
      AND slotActionMongoId IN
      (
          SELECT toString(mongoId)
          FROM platform.slot_actions
          WHERE createdAt >= {d:Date}
            AND createdAt <  {d:Date} + 1         -- last day: < <CUTOFF>
            AND status IN ('COMPLETED', 'FINALIZED')
            AND actionName IN ('spin', 'buy_spin')
      )
)
WHERE ante_bet > 0 OR bonus_type != '';

-- C. Report for closed days: the SELECT body of bi_antebet_mv from 01_ddl.sql
--    with the WITH block replaced by fixed bounds, e.g. one week at a time:
--
--    INSERT INTO adam_sandbox.bi_antebet_report
--    WITH toDate('2026-08-20') AS date_from, toDate('2026-08-26') AS date_to
--    SELECT ... (unchanged from bi_antebet_mv) ...
--
--    up to and including today-2. The first day (2026-08-20) will be
--    incomplete if the backfill starts on that day: rounds that started
--    earlier are cut off, just as in the original script.

-- D. Check after deployment (compare with the original script for one closed day)
-- SELECT spin_category, sum(total_rounds), sum(total_bet_amount), sum(total_win)
-- FROM adam_sandbox.bi_antebet_report_v
-- WHERE report_date = today() - 3
-- GROUP BY spin_category ORDER BY spin_category;
