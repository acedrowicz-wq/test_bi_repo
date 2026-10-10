-- Step 4. Checks after the deployment (all read-only).

-- 1. Refresh status of both MVs (exception = error)
SELECT view, status, last_success_time, next_refresh_time, exception
FROM system.view_refreshes
WHERE database = 'bi_sandbox' AND view LIKE 'bi_total_eg%';

-- 2. Coverage: the history must reach today-2, recent must start right after it
SELECT 'history' AS part, min(bet_date), max(bet_date), count() FROM bi_sandbox.bi_total_eg_bets
UNION ALL
SELECT 'recent', min(bet_date), max(bet_date), count() FROM bi_sandbox.bi_total_eg_bets_recent;

-- 3. No duplicates in the view (expected: 0)
SELECT count() - uniqExact("mongoId") AS duplicates
FROM bi_sandbox.bi_total_eg_v
WHERE "Bet_day_date" >= today() - 7;

-- 4. View vs source, per day (expected: identical for closed days)
SELECT v.d, v.bets, s.bets, v.bet_eur, s.bet_eur, v.win_eur, s.win_eur
FROM
(
    SELECT "Bet_day_date" AS d, count() AS bets, sum("Sum of bet €") AS bet_eur, sum("Sum of win €") AS win_eur
    FROM bi_sandbox.bi_total_eg_v
    WHERE "Bet_day_date" BETWEEN today() - 10 AND today() - 2
    GROUP BY d
) AS v
FULL JOIN
(
    SELECT toDate(createdAt) AS d, count() AS bets, sum(convertedBet) AS bet_eur, sum(convertedWin) AS win_eur
    FROM platform.bets FINAL
    WHERE createdAt >= toDateTime64(today() - 10, 6, 'UTC')
      AND createdAt <  toDateTime64(today() - 1, 6, 'UTC')
      AND status = 'COMPLETED'
      AND dictGetOrDefault('platform.whitelabels_d', 'isTest', wlId, toUInt8(0)) = 0
      AND dictGetOrDefault('platform.currency_d', 'isFun', currency, toUInt8(0)) = 0
    GROUP BY d
) AS s USING d
ORDER BY d;

-- 5. Against the backoffice aggregate (live, real money, settlement day = agg_daily.day).
--    Small differences are expected: agg_daily keys on toDate(updatedAt) and converts at the
--    daily rate, the view keys on toDate(createdAt) and uses convertedBet (rate at bet time).
SELECT day, sumMerge(countBetsState) AS bets, sumMerge(convertedBetState) AS bet_eur, sumMerge(convertedWinState) AS win_eur
FROM platform.agg_daily
WHERE day BETWEEN today() - 10 AND today() - 2
  AND source = 'live' AND isTest = 0 AND isFun = 0 AND isPromo = 0
GROUP BY day
ORDER BY day;

-- 6. The CSV day (2026-10-09, phoenix_roulette). Expected: 7,351 bets, EUR 49,977.92 bet, EUR 42,755.28 win.
--    The CSV has 8,441 rows / 7,304 unique bets (README, findings #1 and #2).
SELECT count(), uniqExact("mongoId"), sum("Sum of bet €"), sum("Sum of win €"), uniqExact("wlId")
FROM bi_sandbox.bi_total_eg_v
WHERE "Bet_day_date" = '2026-10-09' AND "gameId" = 'phoenix_roulette';
