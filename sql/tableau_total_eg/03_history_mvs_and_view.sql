-- Step 3b. Loading (refreshable MVs) and the view Tableau connects to.
-- Requires 00_country_names.sql and 02_history_tables.sql.
--
-- Why refreshable MVs and not an incremental MV on platform.bets:
--   * platform.bets is a ReplacingMergeTree fed by PeerDB: every status change
--     inserts a new version of the bet, so an incremental MV would see each
--     version (duplicates / stale statuses) and would sit on the production
--     insert path (an MV error = a stalled replication).
--   * a refreshable MV reads platform.bets FINAL in its own schedule and is
--     completely decoupled from the insert path.
--
-- | What                          | Object                       | How often                         |
-- |-------------------------------|------------------------------|-----------------------------------|
-- | history + closed days         | bi_total_eg_bets_mv          | every 5 min, 92 days per run      |
-- |   (<= today-2 UTC)            |   -> bi_total_eg_bets        |   (catch-up ~80 min, 2022-12-01+, |
-- |                               |                              |   then +1 day after UTC midnight) |
-- | open days (today-1, today)    | bi_total_eg_bets_recent_mv   | every 15 min, full replace        |
-- |                               |   -> bi_total_eg_bets_recent |                                   |
-- | Tableau                       | bi_total_eg_v (view)         | live                              |

-- ---------------------------------------------------------------------
-- 1. History + closed days -> bi_total_eg_bets (APPEND)
--    One run = ~6 M bets (one month measured on ProdCH: 1.94 M rows, 0.6 s).
--    Each run appends the 92 days after max(bet_date) in the table, up to
--    today-2. Empty table -> it starts from start_day. Once the history is
--    loaded it appends 1 day per day (first run after UTC midnight) and the
--    other runs read nothing (date_to < date_from).
-- ---------------------------------------------------------------------
CREATE MATERIALIZED VIEW IF NOT EXISTS bi_sandbox.bi_total_eg_bets_mv
REFRESH EVERY 5 MINUTE
APPEND TO bi_sandbox.bi_total_eg_bets
DEFINER = bi_total_eg_definer SQL SECURITY DEFINER
AS
WITH
    toDate('2022-12-01')                                                         AS start_day,   -- first data in platform.bets
    toDate(now(), 'UTC')                                                         AS today,
    greatest((SELECT max(bet_date) FROM bi_sandbox.bi_total_eg_bets) + 1, start_day) AS date_from,
    least(date_from + 91, today - 2)                                             AS date_to      -- date_to < date_from = nothing to do
SELECT
    toDate(b.createdAt)                                                          AS bet_date,
    b.createdAt                                                                  AS created_at,
    b.updatedAt                                                                  AS updated_at,
    b.statusUpdatedAt                                                            AS status_updated_at,
    toString(b.mongoId)                                                          AS mongo_id,
    toString(b.playerMongoId)                                                    AS player_mongo_id,
    toString(b.roundMongoId)                                                     AS round_mongo_id,
    toString(b.tokenMongoId)                                                     AS token_mongo_id,
    b.roundNumId                                                                 AS round_num_id,
    b.wlId                                                                       AS wl_id,
    dictGetOrDefault('platform.whitelabels_d', 'name',   b.wlId, b.wlId)         AS wl_name,
    dictGetOrDefault('platform.whitelabels_d', 'label',  b.wlId, '')             AS wl_label,
    dictGetOrDefault('platform.whitelabels_d', 'isTest', b.wlId, toUInt8(0))     AS wl_is_test,
    nullIf(p.partner_name, '')                                                   AS partner_name,
    b.wlUserId                                                                   AS wl_user_id,
    b.tenantId                                                                   AS tenant_id,
    b.gameId                                                                     AS game_id,
    b.country                                                                    AS country,
    dictGetOrDefault('bi_sandbox.country_names_d', 'name', b.country, b.country) AS country_name,
    b.currency                                                                   AS currency,
    dictGetOrDefault('platform.currency_d', 'title', b.currency, '')             AS currency_title,
    ifNull(dictGetOrDefault('platform.currency_d', 'type', b.currency, ''), '')  AS currency_type,
    dictGetOrDefault('platform.currency_d', 'isFun', b.currency, toUInt8(0))     AS is_fun,
    b.status                                                                     AS status,
    nullIf(b.autoplay, '')                                                       AS autoplay,
    nullIf(replaceAll(ifNull(toString(b.freeSpins), ''), '\0', ''), '')          AS free_spins,
    b.freespinTransactionMode                                                    AS freespin_transaction_mode,
    b.betSize                                                                    AS bet_size,
    b.won                                                                        AS won,
    b.convertedBet                                                               AS converted_bet,
    b.convertedWin                                                               AS converted_win,
    now()                                                                        AS loaded_at
FROM platform.bets AS b FINAL
LEFT JOIN
(
    SELECT arrayJoin(JSONExtract(wls, 'Array(String)')) AS wl_id, any(name) AS partner_name
    FROM platform.partners_d
    GROUP BY wl_id
) AS p ON p.wl_id = b.wlId
WHERE date_to >= date_from                                                       -- nothing to do = nothing is read
  AND b.createdAt >= toDateTime64(date_from, 6, 'UTC')
  AND b.createdAt <  toDateTime64(date_to + 1, 6, 'UTC')
  AND b.status = 'COMPLETED'
  AND dictGetOrDefault('platform.whitelabels_d', 'isTest', b.wlId, toUInt8(0)) = 0
  AND dictGetOrDefault('platform.currency_d', 'isFun', b.currency, toUInt8(0)) = 0;

-- ---------------------------------------------------------------------
-- 2. Open days -> bi_total_eg_bets_recent (full replace, atomic swap)
--    Everything after the last closed day (at most the last 3 days).
-- ---------------------------------------------------------------------
CREATE MATERIALIZED VIEW IF NOT EXISTS bi_sandbox.bi_total_eg_bets_recent_mv
REFRESH EVERY 15 MINUTE
TO bi_sandbox.bi_total_eg_bets_recent
DEFINER = bi_total_eg_definer SQL SECURITY DEFINER
AS
WITH
    toDate(now(), 'UTC')                                                         AS today,
    greatest((SELECT max(bet_date) FROM bi_sandbox.bi_total_eg_bets) + 1, today - 3) AS date_from
SELECT
    toDate(b.createdAt)                                                          AS bet_date,
    b.createdAt                                                                  AS created_at,
    b.updatedAt                                                                  AS updated_at,
    b.statusUpdatedAt                                                            AS status_updated_at,
    toString(b.mongoId)                                                          AS mongo_id,
    toString(b.playerMongoId)                                                    AS player_mongo_id,
    toString(b.roundMongoId)                                                     AS round_mongo_id,
    toString(b.tokenMongoId)                                                     AS token_mongo_id,
    b.roundNumId                                                                 AS round_num_id,
    b.wlId                                                                       AS wl_id,
    dictGetOrDefault('platform.whitelabels_d', 'name',   b.wlId, b.wlId)         AS wl_name,
    dictGetOrDefault('platform.whitelabels_d', 'label',  b.wlId, '')             AS wl_label,
    dictGetOrDefault('platform.whitelabels_d', 'isTest', b.wlId, toUInt8(0))     AS wl_is_test,
    nullIf(p.partner_name, '')                                                   AS partner_name,
    b.wlUserId                                                                   AS wl_user_id,
    b.tenantId                                                                   AS tenant_id,
    b.gameId                                                                     AS game_id,
    b.country                                                                    AS country,
    dictGetOrDefault('bi_sandbox.country_names_d', 'name', b.country, b.country) AS country_name,
    b.currency                                                                   AS currency,
    dictGetOrDefault('platform.currency_d', 'title', b.currency, '')             AS currency_title,
    ifNull(dictGetOrDefault('platform.currency_d', 'type', b.currency, ''), '')  AS currency_type,
    dictGetOrDefault('platform.currency_d', 'isFun', b.currency, toUInt8(0))     AS is_fun,
    b.status                                                                     AS status,
    nullIf(b.autoplay, '')                                                       AS autoplay,
    nullIf(replaceAll(ifNull(toString(b.freeSpins), ''), '\0', ''), '')          AS free_spins,
    b.freespinTransactionMode                                                    AS freespin_transaction_mode,
    b.betSize                                                                    AS bet_size,
    b.won                                                                        AS won,
    b.convertedBet                                                               AS converted_bet,
    b.convertedWin                                                               AS converted_win,
    now()                                                                        AS loaded_at
FROM platform.bets AS b FINAL
LEFT JOIN
(
    SELECT arrayJoin(JSONExtract(wls, 'Array(String)')) AS wl_id, any(name) AS partner_name
    FROM platform.partners_d
    GROUP BY wl_id
) AS p ON p.wl_id = b.wlId
WHERE b.createdAt >= toDateTime64(date_from, 6, 'UTC')
  AND b.status = 'COMPLETED'
  AND dictGetOrDefault('platform.whitelabels_d', 'isTest', b.wlId, toUInt8(0)) = 0
  AND dictGetOrDefault('platform.currency_d', 'isFun', b.currency, toUInt8(0)) = 0;

-- ---------------------------------------------------------------------
-- 3. The view for Tableau: history + open days, with the CSV column names.
--    `recent` is cut at max(bet_date) of the history, so a day that was just
--    appended to the history is never counted twice (the two MVs run
--    independently, up to 15 min apart).
--    Column list, names, types and order = 01_recent_days.sql.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW bi_sandbox.bi_total_eg_v
AS
SELECT
    CAST(NULL AS Nullable(String))                                      AS "actionName",
    toStartOfMonth(bet_date)                                            AS "Agregated date",
    autoplay                                                            AS "autoplay",
    bet_date                                                            AS "Bet_day_date",
    CAST(NULL AS Nullable(String))                                      AS "browser",
    CAST(NULL AS Nullable(String))                                      AS "browser_cmd",
    replaceRegexpAll(wl_name, '\\.prod$|-pragmatic|_v1|vegangster1', '') AS "Casino name",
    country                                                             AS "country",
    CAST(NULL AS Nullable(String))                                      AS "Country Code",
    country_name                                                        AS "Country Name",
    CAST(NULL AS Nullable(DateTime('UTC')))                             AS "Created datetime",
    toDateTime(toStartOfHour(created_at), 'UTC')                        AS "Created hour",
    CAST(NULL AS Nullable(DateTime('UTC')))                             AS "createdAt-1",
    CAST(NULL AS Nullable(DateTime('UTC')))                             AS "createdAt-2",
    CAST(NULL AS Nullable(DateTime('UTC')))                             AS "createdAt-3",
    currency                                                            AS "currency",
    CAST(NULL AS Nullable(String))                                      AS "dealer_name",
    CAST(NULL AS Nullable(String))                                      AS "device",
    CAST(NULL AS Nullable(String))                                      AS "device_cmd",
    CAST(NULL AS Nullable(String))                                      AS "dpi_cmd",
    free_spins                                                          AS "freeSpins",
    freespin_transaction_mode                                           AS "freespinTransactionMode",
    replaceAll(game_id, '_', ' ')                                       AS "Game name",
    CAST(NULL AS Nullable(String))                                      AS "gameFamily",
    game_id                                                             AS "gameId",
    CAST(NULL AS Nullable(String))                                      AS "GameName",
    CAST(NULL AS Nullable(String))                                      AS "iframeResolution_cmd",
    CAST(NULL AS Nullable(String))                                      AS "ip",
    wl_label                                                            AS "label",
    mongo_id                                                            AS "mongoId",
    player_mongo_id                                                     AS "mongoId-2",
    CAST(NULL AS Nullable(String))                                      AS "mongoId-3",
    CAST(NULL AS Nullable(String))                                      AS "name",
    CAST(NULL AS Nullable(String))                                      AS "os",
    CAST(NULL AS Nullable(String))                                      AS "os_cmd",
    partner_name                                                        AS "partner_name",
    CAST(NULL AS Nullable(String))                                      AS "platform_cmd",
    player_mongo_id                                                     AS "playerMongoId",
    CAST(NULL AS Nullable(String))                                      AS "playerMongoId-1",
    'Live'                                                              AS "Product name",
    country_name                                                        AS "real_country",
    country_name                                                        AS "Regions",
    CAST(NULL AS Nullable(String))                                      AS "result",
    round_mongo_id                                                      AS "roundMongoId",
    bet_date                                                            AS "Scaf date",
    CAST(NULL AS Nullable(String))                                      AS "screenResolution_cmd",
    CAST(NULL AS Nullable(String))                                      AS "Session mongo id",
    CAST(NULL AS Nullable(String))                                      AS "Session status",
    CAST(NULL AS Nullable(String))                                      AS "sex",
    status                                                              AS "status",
    CAST(NULL AS Nullable(String))                                      AS "status-2",
    formatDateTime(status_updated_at, '%Y-%m-%d %H:%M:%S', 'Europe/Warsaw') AS "statusUpdatedAt_str",  -- old source's format, incl. its %M bug
    currency                                                            AS "symbol",
    'localhost/CHTotalEGoverview2026/sqlproxy'                          AS "Table Names",
    'localhost/CHJoinedroundsandbets2026/sqlproxy'                      AS "Table Names-1",
    CAST(NULL AS Nullable(String))                                      AS "timeToPlay_cmd",
    CAST(NULL AS Nullable(String))                                      AS "title",
    currency_title                                                      AS "Title",
    token_mongo_id                                                      AS "tokenMongoId",
    currency_type                                                       AS "Type",
    CAST(NULL AS Nullable(String))                                      AS "type",
    CAST(NULL AS Nullable(DateTime('UTC')))                             AS "updatedAt-1",
    formatDateTime(updated_at, '%Y-%m-%d %H:%M:%S', 'Europe/Warsaw')    AS "updatedAt_str",
    CAST(NULL AS Nullable(String))                                      AS "wl label",
    wl_name                                                             AS "wl name",
    wl_id                                                               AS "wlId",
    wl_user_id                                                          AS "wlUserId",
    CAST(NULL AS Nullable(String))                                      AS "wlUserId-2",
    CAST(NULL AS Nullable(Float64))                                     AS "all_rounds",
    bet_size                                                            AS "betSize",
    CAST(NULL AS Nullable(String))                                      AS "id",
    toUInt32(toUnixTimestamp(created_at))                               AS "incremental_id",
    CAST(NULL AS Nullable(UInt8))                                       AS "is_time_empty",
    is_fun                                                              AS "isFun",
    CAST(NULL AS Nullable(Float64))                                     AS "muted_button_clicks",
    CAST(NULL AS Nullable(Float64))                                     AS "muted_rounds",
    CAST(NULL AS Nullable(Int64))                                       AS "playerId",
    CAST(NULL AS Nullable(Int64))                                       AS "playerId-1",
    CAST(NULL AS Nullable(Int64))                                       AS "playerId-2",
    CAST(NULL AS Nullable(String))                                      AS "round_id",
    CAST(NULL AS Nullable(String))                                      AS "roundId",
    CAST(NULL AS Nullable(String))                                      AS "spin mongoId",
    CAST(NULL AS Nullable(Float64))                                     AS "Spins rounds",
    converted_bet                                                       AS "Sum of bet €",
    converted_win                                                       AS "Sum of win €",
    CAST(NULL AS Nullable(Float64))                                     AS "timeToEndJoin_in_seconds",
    wl_is_test                                                          AS "wl is test",
    CAST(NULL AS Nullable(UInt8))                                       AS "wl is test ",
    won                                                                 AS "won",
    created_at                                                          AS "createdAt",
    updated_at                                                          AS "updatedAt",
    status_updated_at                                                   AS "statusUpdatedAt",
    converted_bet                                                       AS "convertedBet",
    converted_win                                                       AS "convertedWin",
    round_num_id                                                        AS "roundNumId",
    tenant_id                                                           AS "tenantId"
FROM
(
    SELECT * FROM bi_sandbox.bi_total_eg_bets
    UNION ALL
    SELECT * FROM bi_sandbox.bi_total_eg_bets_recent
    WHERE bet_date > (SELECT max(bet_date) FROM bi_sandbox.bi_total_eg_bets)
);
