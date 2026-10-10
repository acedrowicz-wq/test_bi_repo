-- Step 4. Checks after the deployment (all read-only).

-- 1. Refresh status of the MVs (exception = error)
SELECT view, status, last_success_time, next_refresh_time, exception
FROM system.view_refreshes
WHERE database = 'bi_sandbox' AND view LIKE 'bi_total_eg%';

-- 2. Coverage per product: the history must reach today-2, recent must start right after it
SELECT 'history' AS part, product, min(bet_date), max(bet_date), count(), sum(bets)
FROM bi_sandbox.bi_total_eg_hourly GROUP BY product
UNION ALL
SELECT 'recent', product, min(bet_date), max(bet_date), count(), sum(bets)
FROM bi_sandbox.bi_total_eg_hourly_recent GROUP BY product
ORDER BY product, part;

-- 3. No day counted twice in the view (expected: 0 rows): every (product, day) of the view
--    must come from exactly one of the two tables.
SELECT v.product, v.d, v.n AS view_rows, h.n AS history_rows, r.n AS recent_rows
FROM (SELECT "Product name" AS product, "Bet_day_date" AS d, count() AS n FROM bi_sandbox.bi_total_eg_v GROUP BY product, d) AS v
LEFT JOIN (SELECT product, bet_date AS d, count() AS n FROM bi_sandbox.bi_total_eg_hourly GROUP BY product, d) AS h USING (product, d)
LEFT JOIN (SELECT product, bet_date AS d, count() AS n FROM bi_sandbox.bi_total_eg_hourly_recent GROUP BY product, d) AS r USING (product, d)
WHERE v.n != if(h.n > 0, h.n, r.n)
LIMIT 20;

-- 4. View vs backoffice per day and product (agg_daily, all promo flags).
--    Expected: slot bets / EUR within a few cents per day (as on 2026-10-09: 21,243,902 vs 21,243,870 bets,
--    EUR 18,347,296.29 vs 18,347,296.13). Live: agg_daily keys on the settlement day, the view on createdAt.
SELECT v.product, v.d, v.bets, a.bets AS agg_bets, v.bet_eur, a.bet_eur AS agg_bet_eur, v.win_eur, a.win_eur AS agg_win_eur
FROM
(
    SELECT "Product name" AS product, "Bet_day_date" AS d,
           sum("mongoId") AS bets, sum("Sum of bet €") AS bet_eur, sum("Sum of win €") AS win_eur
    FROM bi_sandbox.bi_total_eg_v
    WHERE "Bet_day_date" BETWEEN today() - 9 AND today() - 2
    GROUP BY product, d
) AS v
LEFT JOIN
(
    SELECT if(source = 'live', 'Live', 'Slots') AS product, day AS d,
           sumMerge(countBetsState) AS bets, sumMerge(convertedBetState) AS bet_eur, sumMerge(convertedWinState) AS win_eur
    FROM platform.agg_daily
    WHERE day BETWEEN today() - 9 AND today() - 2 AND isTest = 0 AND isFun = 0
    GROUP BY product, d
) AS a ON a.product = v.product AND a.d = v.d
ORDER BY v.product, v.d;

-- 5. The CSV day (2026-10-09, phoenix_roulette, live). Expected with status COMPLETED:
--    7,351 bets, EUR 49,977.92 bet, EUR 42,755.28 win (the CSV: 8,441 rows / 7,304 unique bets, README #1 #2).
SELECT sum("mongoId"), sum("Sum of bet €"), sum("Sum of win €"), uniqExact("wlId"), uniqExact("roundMongoId") AS live_rounds
FROM bi_sandbox.bi_total_eg_v
WHERE "Bet_day_date" = '2026-10-09' AND "gameId" = 'phoenix_roulette' AND "status" = 'COMPLETED';

-- 6. Slot rounds add up (expected: equal)
SELECT sum("slot_rounds") AS summed,
       (SELECT uniqExact(roundNumId, playerMongoId) FROM platform.slot_actions
        WHERE createdAt >= toDateTime64(today() - 2, 6, 'UTC') AND createdAt < toDateTime64(today() - 1, 6, 'UTC')
          AND roundStarted = 1 AND status IN ('COMPLETED', 'FINALIZED', 'INTERNAL_TRANSACTION')
          AND dictGetOrDefault('platform.whitelabels_d', 'isTest', wlId, toUInt8(0)) = 0
          AND dictGetOrDefault('platform.currency_d', 'isFun', currency, toUInt8(0)) = 0) AS exact
FROM bi_sandbox.bi_total_eg_v
WHERE "Product name" = 'Slots' AND "Bet_day_date" = today() - 2;
