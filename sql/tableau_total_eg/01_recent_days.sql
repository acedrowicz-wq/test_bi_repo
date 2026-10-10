-- Step 2. Operational query: live bets of the LAST 3 DAYS (UTC) with the
-- exact column names of the CSV "Total_EG_datasource" (Tableau).
--
-- Grain: 1 row = 1 live bet (platform.bets, deduplicated with FINAL).
-- Only the base (physical / row-level) fields are returned. The fields Tableau
-- calculates itself (period flags, parameters, formatted measures, COUNTDs)
-- stay in the workbook - see README.md, "Fields left to Tableau".
--
-- Requires: bi_sandbox.country_names_d (00_country_names.sql).
--
-- Performance:
--   * platform.bets: PARTITION BY toStartOfMonth(createdAt),
--     ORDER BY (toStartOfHour(createdAt), wlUserId, mongoId)
--     -> the createdAt bound prunes partitions AND granules (1st key column).
--   * FINAL on 3 days = ~250k rows, < 1 s.
--   * dictionaries (dictGet) instead of JOINs; the only JOIN is the 39-row partner list.

WITH
    toStartOfDay(now('UTC')) - INTERVAL 3 DAY                                    AS ts_from,   -- change the window here
    dictGetOrDefault('platform.whitelabels_d', 'name',  b.wlId, b.wlId)          AS wl_name,
    dictGetOrDefault('platform.whitelabels_d', 'label', b.wlId, '')              AS wl_label,
    dictGetOrDefault('bi_sandbox.country_names_d', 'name', b.country, b.country) AS country_name
SELECT
    CAST(NULL AS Nullable(String))                                      AS "actionName",              -- slot branch, empty for live
    toStartOfMonth(b.createdAt)                                         AS "Agregated date",          -- Date
    nullIf(b.autoplay, '')                                              AS "autoplay",
    toDate(b.createdAt)                                                 AS "Bet_day_date",            -- Date, UTC day
    CAST(NULL AS Nullable(String))                                      AS "browser",
    CAST(NULL AS Nullable(String))                                      AS "browser_cmd",
    replaceRegexpAll(wl_name, '\\.prod$|-pragmatic|_v1|vegangster1', '') AS "Casino name",
    b.country                                                           AS "country",
    CAST(NULL AS Nullable(String))                                      AS "Country Code",
    country_name                                                        AS "Country Name",
    CAST(NULL AS Nullable(DateTime('UTC')))                             AS "Created datetime",
    toDateTime(toStartOfHour(b.createdAt), 'UTC')                       AS "Created hour",            -- DateTime, UTC
    CAST(NULL AS Nullable(DateTime('UTC')))                             AS "createdAt-1",
    CAST(NULL AS Nullable(DateTime('UTC')))                             AS "createdAt-2",
    CAST(NULL AS Nullable(DateTime('UTC')))                             AS "createdAt-3",
    b.currency                                                          AS "currency",
    CAST(NULL AS Nullable(String))                                      AS "dealer_name",
    CAST(NULL AS Nullable(String))                                      AS "device",
    CAST(NULL AS Nullable(String))                                      AS "device_cmd",
    CAST(NULL AS Nullable(String))                                      AS "dpi_cmd",
    nullIf(replaceAll(ifNull(toString(b.freeSpins), ''), '\0', ''), '') AS "freeSpins",               -- FixedString padded with \0
    b.freespinTransactionMode                                           AS "freespinTransactionMode",
    replaceAll(b.gameId, '_', ' ')                                      AS "Game name",
    CAST(NULL AS Nullable(String))                                      AS "gameFamily",
    b.gameId                                                            AS "gameId",
    CAST(NULL AS Nullable(String))                                      AS "GameName",
    CAST(NULL AS Nullable(String))                                      AS "iframeResolution_cmd",
    CAST(NULL AS Nullable(String))                                      AS "ip",
    wl_label                                                            AS "label",
    toString(b.mongoId)                                                 AS "mongoId",                 -- bet id
    toString(b.playerMongoId)                                           AS "mongoId-2",               -- player id (players.mongoId)
    CAST(NULL AS Nullable(String))                                      AS "mongoId-3",
    CAST(NULL AS Nullable(String))                                      AS "name",
    CAST(NULL AS Nullable(String))                                      AS "os",
    CAST(NULL AS Nullable(String))                                      AS "os_cmd",
    nullIf(p.partner_name, '')                                          AS "partner_name",
    CAST(NULL AS Nullable(String))                                      AS "platform_cmd",
    toString(b.playerMongoId)                                           AS "playerMongoId",
    CAST(NULL AS Nullable(String))                                      AS "playerMongoId-1",
    'Live'                                                              AS "Product name",
    country_name                                                        AS "real_country",
    country_name                                                        AS "Regions",
    CAST(NULL AS Nullable(String))                                      AS "result",
    toString(b.roundMongoId)                                            AS "roundMongoId",
    toDate(b.createdAt)                                                 AS "Scaf date",
    CAST(NULL AS Nullable(String))                                      AS "screenResolution_cmd",
    CAST(NULL AS Nullable(String))                                      AS "Session mongo id",
    CAST(NULL AS Nullable(String))                                      AS "Session status",
    CAST(NULL AS Nullable(String))                                      AS "sex",
    b.status                                                            AS "status",
    CAST(NULL AS Nullable(String))                                      AS "status-2",
    -- 1:1 with the old source, INCLUDING its bug: %M = month name in ClickHouse,
    -- so the "minutes" are 'October'. Warsaw time. Correct format: '%Y-%m-%d %H:%i:%S'.
    formatDateTime(b.statusUpdatedAt, '%Y-%m-%d %H:%M:%S', 'Europe/Warsaw') AS "statusUpdatedAt_str",
    b.currency                                                          AS "symbol",
    'localhost/CHTotalEGoverview2026/sqlproxy'                          AS "Table Names",             -- constants: the old union labels
    'localhost/CHJoinedroundsandbets2026/sqlproxy'                      AS "Table Names-1",
    CAST(NULL AS Nullable(String))                                      AS "timeToPlay_cmd",
    CAST(NULL AS Nullable(String))                                      AS "title",
    dictGetOrDefault('platform.currency_d', 'title', b.currency, '')    AS "Title",
    toString(b.tokenMongoId)                                            AS "tokenMongoId",
    dictGetOrDefault('platform.currency_d', 'type', b.currency, '')     AS "Type",                    -- regular / virtual
    CAST(NULL AS Nullable(String))                                      AS "type",
    CAST(NULL AS Nullable(DateTime('UTC')))                             AS "updatedAt-1",
    formatDateTime(b.updatedAt, '%Y-%m-%d %H:%M:%S', 'Europe/Warsaw')   AS "updatedAt_str",           -- same bug as above
    CAST(NULL AS Nullable(String))                                      AS "wl label",
    wl_name                                                             AS "wl name",
    b.wlId                                                              AS "wlId",
    b.wlUserId                                                          AS "wlUserId",
    CAST(NULL AS Nullable(String))                                      AS "wlUserId-2",
    CAST(NULL AS Nullable(Float64))                                     AS "all_rounds",
    b.betSize                                                           AS "betSize",                 -- Decimal(30,12), player currency
    CAST(NULL AS Nullable(String))                                      AS "id",
    toUInt32(toUnixTimestamp(b.createdAt))                              AS "incremental_id",          -- = unix time of createdAt (UTC)
    CAST(NULL AS Nullable(UInt8))                                       AS "is_time_empty",
    dictGetOrDefault('platform.currency_d', 'isFun', b.currency, toUInt8(0)) AS "isFun",
    CAST(NULL AS Nullable(Float64))                                     AS "muted_button_clicks",
    CAST(NULL AS Nullable(Float64))                                     AS "muted_rounds",
    CAST(NULL AS Nullable(Int64))                                       AS "playerId",
    CAST(NULL AS Nullable(Int64))                                       AS "playerId-1",
    CAST(NULL AS Nullable(Int64))                                       AS "playerId-2",
    CAST(NULL AS Nullable(String))                                      AS "round_id",
    CAST(NULL AS Nullable(String))                                      AS "roundId",
    CAST(NULL AS Nullable(String))                                      AS "spin mongoId",
    CAST(NULL AS Nullable(Float64))                                     AS "Spins rounds",
    b.convertedBet                                                      AS "Sum of bet €",            -- EUR, Decimal(16,4)
    b.convertedWin                                                      AS "Sum of win €",            -- EUR, Decimal(16,4)
    CAST(NULL AS Nullable(Float64))                                     AS "timeToEndJoin_in_seconds",
    dictGetOrDefault('platform.whitelabels_d', 'isTest', b.wlId, toUInt8(0)) AS "wl is test",
    CAST(NULL AS Nullable(UInt8))                                       AS "wl is test ",             -- trailing space, as in the CSV
    b.won                                                               AS "won",                     -- Decimal(30,12), player currency

    -- native columns: not in the CSV (hidden fields are not exported by Tableau),
    -- returned so that calculations referring to hidden base fields keep working
    b.createdAt                                                         AS "createdAt",
    b.updatedAt                                                         AS "updatedAt",
    b.statusUpdatedAt                                                   AS "statusUpdatedAt",
    b.convertedBet                                                      AS "convertedBet",
    b.convertedWin                                                      AS "convertedWin",
    b.roundNumId                                                        AS "roundNumId",
    b.tenantId                                                          AS "tenantId"
FROM platform.bets AS b FINAL
LEFT JOIN
(
    -- partner = the partner whose wls list contains the casino (the old source's rule;
    -- casinos missing from every list get an empty partner, e.g. yaycasinocomna, acornfunna)
    SELECT arrayJoin(JSONExtract(wls, 'Array(String)')) AS wl_id, any(name) AS partner_name
    FROM platform.partners_d
    GROUP BY wl_id
) AS p ON p.wl_id = b.wlId
WHERE b.createdAt >= ts_from
  AND b.status = 'COMPLETED'                                                          -- settled bets only (the CSV has only COMPLETED)
  AND dictGetOrDefault('platform.whitelabels_d', 'isTest', b.wlId, toUInt8(0)) = 0    -- no test casinos
  AND dictGetOrDefault('platform.currency_d', 'isFun', b.currency, toUInt8(0)) = 0    -- no fun currencies
;
