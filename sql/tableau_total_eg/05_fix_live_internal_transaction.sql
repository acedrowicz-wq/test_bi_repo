-- Step 5 (2026-10-10). Live now also counts INTERNAL_TRANSACTION bets (live free spins), like the backoffice.
-- Live bets with that status exist only from 2025-12-05, so only Live days from that date are reloaded.
-- Slots are not touched (their MV keeps loading). Run top to bottom in the ProdCH SQL console.
-- Afterwards the live MV continues from the last remaining Live day and reaches today-2 by itself.

-- 1. stop the two MVs that read platform.bets
DROP VIEW IF EXISTS bi_sandbox.bi_total_eg_live_mv;
DROP VIEW IF EXISTS bi_sandbox.bi_total_eg_recent_mv;

-- 2. remove the Live days that miss the free-spin bets (waits until the delete is done)
ALTER TABLE bi_sandbox.bi_total_eg_hourly
    DELETE WHERE product = 'Live' AND bet_date >= '2025-12-05'
    SETTINGS mutations_sync = 2;

-- 3. the two MVs with the new status filter (same as 03_history_mvs_and_view.sql)
CREATE MATERIALIZED VIEW IF NOT EXISTS bi_sandbox.bi_total_eg_live_mv
REFRESH EVERY 5 MINUTE
APPEND TO bi_sandbox.bi_total_eg_hourly
DEFINER = bi_total_eg_definer SQL SECURITY DEFINER
AS
WITH
    toDate('2022-12-19')                                                           AS start_day,
    toDate(now(), 'UTC')                                                         AS today,
    greatest((SELECT maxIf(bet_date, product = 'Live') FROM bi_sandbox.bi_total_eg_hourly) + 1, start_day) AS date_from,
    least(date_from + 91, today - 2)                                             AS date_to      -- date_to < date_from = nothing to do
SELECT
    'Live'                                                                       AS product,
    toDateTime(toStartOfHour(b.createdAt), 'UTC')                             AS hour,
    toDate(hour)                                                                 AS bet_date,
    b.wlId                                                                     AS wl_id,
    dictGetOrDefault('platform.whitelabels_d', 'name',   b.wlId, b.wlId)       AS wl_name,
    dictGetOrDefault('platform.whitelabels_d', 'label',  b.wlId, '')           AS wl_label,
    dictGetOrDefault('platform.whitelabels_d', 'isTest', b.wlId, toUInt8(0))   AS wl_is_test,
    nullIf(any(p.partner_name), '')                                              AS partner_name,
    b.wlUserId                                                                 AS wl_user_id,
    toString(b.playerMongoId)                                                  AS player_mongo_id,
    toString(b.tokenMongoId)                                                   AS token_mongo_id,
    b.gameId                                                                   AS game_id,
    b.country                                                                  AS country,
    b.currency                                                                 AS currency,
    dictGetOrDefault('platform.currency_d', 'title', b.currency, '')           AS currency_title,
    ifNull(dictGetOrDefault('platform.currency_d', 'type', b.currency, ''), '') AS currency_type,
    dictGetOrDefault('platform.currency_d', 'isFun', b.currency, toUInt8(0))   AS is_fun,
    b.status                                                                   AS status,
    nullIf(replaceAll(ifNull(toString(b.freeSpins), ''), '\0', ''), '')       AS free_spins,
    b.freespinTransactionMode                                                  AS freespin_transaction_mode,
    toString(b.roundMongoId)                                                     AS round_mongo_id,   -- live: a round is shared by many players, so it stays in the grain (exact COUNTD of rounds)
    ''                                                                           AS action_name,
    nullIf(b.autoplay, '')                                                       AS autoplay,
    uniqExact(b.mongoId)                                                         AS bets,             -- unique bets
    CAST(NULL AS Nullable(UInt64))                                               AS slot_rounds,
    sum(b.betSize)                                                             AS bet_size,
    sum(b.won)                                                                 AS won,
    sum(b.convertedBet)                                                        AS converted_bet,
    sum(b.convertedWin)                                                        AS converted_win,
    max(b.updatedAt)                                                           AS last_updated_at,
    max(b.statusUpdatedAt)                                                     AS last_status_updated_at,
    now()                                                                        AS loaded_at
FROM platform.bets AS b FINAL
LEFT JOIN
(
    SELECT arrayJoin(JSONExtract(wls, 'Array(String)')) AS wl_id, any(name) AS partner_name
    FROM platform.partners_d
    GROUP BY wl_id
) AS p ON p.wl_id = b.wlId
WHERE b.createdAt >= toDateTime64(date_from, 6, 'UTC')
  AND b.createdAt <  toDateTime64(date_to + 1, 6, 'UTC')
  AND date_to >= date_from                                                     -- nothing to do = nothing is read
  AND b.status IN ('COMPLETED', 'FINALIZED', 'INTERNAL_TRANSACTION')             -- settled; INTERNAL_TRANSACTION = live free spins (from 2025-12-05)
  AND dictGetOrDefault('platform.whitelabels_d', 'isTest', b.wlId, toUInt8(0)) = 0    -- no test casinos
  AND dictGetOrDefault('platform.currency_d', 'isFun', b.currency, toUInt8(0)) = 0    -- no fun currencies
GROUP BY hour, wl_id, wl_user_id, player_mongo_id, token_mongo_id, game_id, country, currency, status, free_spins, freespin_transaction_mode, round_mongo_id, autoplay
SETTINGS max_bytes_before_external_group_by = 8000000000;

CREATE MATERIALIZED VIEW IF NOT EXISTS bi_sandbox.bi_total_eg_recent_mv
REFRESH EVERY 15 MINUTE
TO bi_sandbox.bi_total_eg_hourly_recent
DEFINER = bi_total_eg_definer SQL SECURITY DEFINER
AS
WITH
    toDate(now(), 'UTC')                                                         AS today,
    greatest((SELECT maxIf(bet_date, product = 'Live')  FROM bi_sandbox.bi_total_eg_hourly) + 1, today - 3) AS date_from_live,
    greatest((SELECT maxIf(bet_date, product = 'Slots') FROM bi_sandbox.bi_total_eg_hourly) + 1, today - 3) AS date_from_slots
SELECT * FROM
(
    SELECT
        'Live'                                                                       AS product,
        toDateTime(toStartOfHour(b.createdAt), 'UTC')                             AS hour,
        toDate(hour)                                                                 AS bet_date,
        b.wlId                                                                     AS wl_id,
        dictGetOrDefault('platform.whitelabels_d', 'name',   b.wlId, b.wlId)       AS wl_name,
        dictGetOrDefault('platform.whitelabels_d', 'label',  b.wlId, '')           AS wl_label,
        dictGetOrDefault('platform.whitelabels_d', 'isTest', b.wlId, toUInt8(0))   AS wl_is_test,
        nullIf(any(p.partner_name), '')                                              AS partner_name,
        b.wlUserId                                                                 AS wl_user_id,
        toString(b.playerMongoId)                                                  AS player_mongo_id,
        toString(b.tokenMongoId)                                                   AS token_mongo_id,
        b.gameId                                                                   AS game_id,
        b.country                                                                  AS country,
        b.currency                                                                 AS currency,
        dictGetOrDefault('platform.currency_d', 'title', b.currency, '')           AS currency_title,
        ifNull(dictGetOrDefault('platform.currency_d', 'type', b.currency, ''), '') AS currency_type,
        dictGetOrDefault('platform.currency_d', 'isFun', b.currency, toUInt8(0))   AS is_fun,
        b.status                                                                   AS status,
        nullIf(replaceAll(ifNull(toString(b.freeSpins), ''), '\0', ''), '')       AS free_spins,
        b.freespinTransactionMode                                                  AS freespin_transaction_mode,
        toString(b.roundMongoId)                                                     AS round_mongo_id,   -- live: a round is shared by many players, so it stays in the grain (exact COUNTD of rounds)
        ''                                                                           AS action_name,
        nullIf(b.autoplay, '')                                                       AS autoplay,
        uniqExact(b.mongoId)                                                         AS bets,             -- unique bets
        CAST(NULL AS Nullable(UInt64))                                               AS slot_rounds,
        sum(b.betSize)                                                             AS bet_size,
        sum(b.won)                                                                 AS won,
        sum(b.convertedBet)                                                        AS converted_bet,
        sum(b.convertedWin)                                                        AS converted_win,
        max(b.updatedAt)                                                           AS last_updated_at,
        max(b.statusUpdatedAt)                                                     AS last_status_updated_at,
        now()                                                                        AS loaded_at
    FROM platform.bets AS b FINAL
    LEFT JOIN
    (
        SELECT arrayJoin(JSONExtract(wls, 'Array(String)')) AS wl_id, any(name) AS partner_name
        FROM platform.partners_d
        GROUP BY wl_id
    ) AS p ON p.wl_id = b.wlId
    WHERE b.createdAt >= toDateTime64(date_from_live, 6, 'UTC')
      AND b.status IN ('COMPLETED', 'FINALIZED', 'INTERNAL_TRANSACTION')             -- settled; INTERNAL_TRANSACTION = live free spins (from 2025-12-05)
      AND dictGetOrDefault('platform.whitelabels_d', 'isTest', b.wlId, toUInt8(0)) = 0    -- no test casinos
      AND dictGetOrDefault('platform.currency_d', 'isFun', b.currency, toUInt8(0)) = 0    -- no fun currencies
    GROUP BY hour, wl_id, wl_user_id, player_mongo_id, token_mongo_id, game_id, country, currency, status, free_spins, freespin_transaction_mode, round_mongo_id, autoplay

    UNION ALL

    SELECT
        'Slots'                                                                      AS product,
        toDateTime(toStartOfHour(s.createdAt), 'UTC')                             AS hour,
        toDate(hour)                                                                 AS bet_date,
        s.wlId                                                                     AS wl_id,
        dictGetOrDefault('platform.whitelabels_d', 'name',   s.wlId, s.wlId)       AS wl_name,
        dictGetOrDefault('platform.whitelabels_d', 'label',  s.wlId, '')           AS wl_label,
        dictGetOrDefault('platform.whitelabels_d', 'isTest', s.wlId, toUInt8(0))   AS wl_is_test,
        nullIf(any(p.partner_name), '')                                              AS partner_name,
        s.wlUserId                                                                 AS wl_user_id,
        toString(s.playerMongoId)                                                  AS player_mongo_id,
        toString(s.tokenMongoId)                                                   AS token_mongo_id,
        s.gameId                                                                   AS game_id,
        s.country                                                                  AS country,
        s.currency                                                                 AS currency,
        dictGetOrDefault('platform.currency_d', 'title', s.currency, '')           AS currency_title,
        ifNull(dictGetOrDefault('platform.currency_d', 'type', s.currency, ''), '') AS currency_type,
        dictGetOrDefault('platform.currency_d', 'isFun', s.currency, toUInt8(0))   AS is_fun,
        s.status                                                                   AS status,
        nullIf(replaceAll(ifNull(toString(s.freeSpins), ''), '\0', ''), '')       AS free_spins,
        s.freespinTransactionMode                                                  AS freespin_transaction_mode,
        ''                                                                           AS round_mongo_id,   -- slots: 1 round = 1 player, counted in slot_rounds
        s.actionName                                                                 AS action_name,
        CAST(NULL AS Nullable(String))                                               AS autoplay,
        uniqExactIf(s.mongoId, s.betSize > 0)                                        AS bets,             -- unique bets = actions with a stake
        uniqExactIf((s.roundNumId, s.playerMongoId), s.roundStarted = 1)            AS slot_rounds,      -- counted on the starting action only -> summable
        sum(s.betSize)                                                             AS bet_size,
        sum(s.won)                                                                 AS won,
        sum(s.convertedBet)                                                        AS converted_bet,
        sum(s.convertedWin)                                                        AS converted_win,
        max(s.updatedAt)                                                           AS last_updated_at,
        max(s.statusUpdatedAt)                                                     AS last_status_updated_at,
        now()                                                                        AS loaded_at
    FROM platform.slot_actions AS s FINAL
    LEFT JOIN
    (
        SELECT arrayJoin(JSONExtract(wls, 'Array(String)')) AS wl_id, any(name) AS partner_name
        FROM platform.partners_d
        GROUP BY wl_id
    ) AS p ON p.wl_id = s.wlId
    WHERE s.createdAt >= toDateTime64(date_from_slots, 6, 'UTC')
      AND s.status IN ('COMPLETED', 'FINALIZED', 'INTERNAL_TRANSACTION')             -- settled; INTERNAL_TRANSACTION = final-only free-spin wins
      AND dictGetOrDefault('platform.whitelabels_d', 'isTest', s.wlId, toUInt8(0)) = 0    -- no test casinos
      AND dictGetOrDefault('platform.currency_d', 'isFun', s.currency, toUInt8(0)) = 0    -- no fun currencies
    GROUP BY hour, wl_id, wl_user_id, player_mongo_id, token_mongo_id, game_id, country, currency, status, free_spins, freespin_transaction_mode, action_name
)
SETTINGS max_bytes_before_external_group_by = 8000000000;

-- 4. check: no errors; Live max(bet_date) grows again, recent is refreshed
SELECT view, status, last_success_time, exception
FROM system.view_refreshes WHERE database = 'bi_sandbox' AND view LIKE 'bi_total_eg%';
SELECT product, min(bet_date), max(bet_date), count(), sum(bets)
FROM bi_sandbox.bi_total_eg_hourly GROUP BY product;
