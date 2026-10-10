-- Active players by free-spin usage (tableau_fs_player_filter.md): the view vs the Backoffice, per product and day.
-- Read-only. Change the two dates. "without_fs" is what Tableau shows for "Without FS".
-- exact_backoffice_logic = players with a bet without free spins in platform.agg_players_daily (settlement day, exact)
-- approx_backoffice_screen = the Backoffice Games Report figure (platform.agg_daily, uniqCombined64, approximate)
WITH toDate('2026-10-07') AS d_from, toDate('2026-10-08') AS d_to
SELECT v.product, v.d, v.without_fs, v.total - v.without_fs AS fs_only, v.total,
       e.players AS exact_backoffice_logic, a.players AS approx_backoffice_screen
FROM
(
    SELECT "Product name" AS product, "Bet_day_date" AS d,
           uniqExactIf(("wlId", "wlUserId"), "freeSpins" IS NULL AND "mongoId" > 0) AS without_fs,
           uniqExactIf(("wlId", "wlUserId"), ("freeSpins" IS NULL AND "mongoId" > 0) OR "freeSpins" IS NOT NULL) AS total
    FROM bi_sandbox.bi_total_eg_v
    WHERE "Bet_day_date" BETWEEN d_from AND d_to
    GROUP BY product, d
) AS v
LEFT JOIN
(
    SELECT if(source = 'live', 'Live', 'Slots') AS product, day AS d, uniqExact(wlId, wlUserId) AS players
    FROM
    (
        SELECT source, day, wlId, wlUserId
        FROM platform.agg_players_daily
        WHERE day BETWEEN d_from AND d_to AND isTest = 0 AND isFun = 0 AND isPromo = 0
        GROUP BY source, day, wlId, wlUserId
        HAVING sumMerge(countBetsState) > 0
    )
    GROUP BY product, d
) AS e ON e.product = v.product AND e.d = v.d
LEFT JOIN
(
    SELECT if(source = 'live', 'Live', 'Slots') AS product, day AS d, uniqCombined64Merge(uniqPlayersState) AS players
    FROM platform.agg_daily
    WHERE day BETWEEN d_from AND d_to AND isTest = 0 AND isFun = 0 AND isPromo = 0
    GROUP BY product, d
) AS a ON a.product = v.product AND a.d = v.d
ORDER BY v.product, v.d;
