# Shared SQL fragments; gen.py assembles 01/03 from them so the live/slots logic and the
# Tableau alias layer exist in exactly one place.

PARTNERS = """LEFT JOIN
(
    -- partner = the partner whose wls list contains the casino (old source's rule)
    SELECT arrayJoin(JSONExtract(wls, 'Array(String)')) AS wl_id, any(name) AS partner_name
    FROM platform.partners_d
    GROUP BY wl_id
) AS p ON p.wl_id = {a}.wlId"""

COMMON_DIMS = """    toDateTime(toStartOfHour({a}.createdAt), 'UTC')                             AS hour,
    toDate(hour)                                                                 AS bet_date,
    {a}.wlId                                                                     AS wl_id,
    dictGetOrDefault('platform.whitelabels_d', 'name',   {a}.wlId, {a}.wlId)       AS wl_name,
    dictGetOrDefault('platform.whitelabels_d', 'label',  {a}.wlId, '')           AS wl_label,
    dictGetOrDefault('platform.whitelabels_d', 'isTest', {a}.wlId, toUInt8(0))   AS wl_is_test,
    nullIf(any(p.partner_name), '')                                              AS partner_name,
    {a}.wlUserId                                                                 AS wl_user_id,
    toString({a}.playerMongoId)                                                  AS player_mongo_id,
    toString({a}.tokenMongoId)                                                   AS token_mongo_id,
    {a}.gameId                                                                   AS game_id,
    {a}.country                                                                  AS country,
    dictGetOrDefault('bi_sandbox.country_names_d', 'name', {a}.country, {a}.country) AS country_name,
    {a}.currency                                                                 AS currency,
    dictGetOrDefault('platform.currency_d', 'title', {a}.currency, '')           AS currency_title,
    ifNull(dictGetOrDefault('platform.currency_d', 'type', {a}.currency, ''), '') AS currency_type,
    dictGetOrDefault('platform.currency_d', 'isFun', {a}.currency, toUInt8(0))   AS is_fun,
    {a}.status                                                                   AS status,
    nullIf(replaceAll(ifNull(toString({a}.freeSpins), ''), '\\0', ''), '')       AS free_spins,
    {a}.freespinTransactionMode                                                  AS freespin_transaction_mode,"""

COMMON_MEASURES = """    sum({a}.betSize)                                                             AS bet_size,
    sum({a}.won)                                                                 AS won,
    sum({a}.convertedBet)                                                        AS converted_bet,
    sum({a}.convertedWin)                                                        AS converted_win,
    max({a}.updatedAt)                                                           AS last_updated_at,
    max({a}.statusUpdatedAt)                                                     AS last_status_updated_at,
    now()                                                                        AS loaded_at"""

FILTERS = """  AND dictGetOrDefault('platform.whitelabels_d', 'isTest', {a}.wlId, toUInt8(0)) = 0    -- no test casinos
  AND dictGetOrDefault('platform.currency_d', 'isFun', {a}.currency, toUInt8(0)) = 0    -- no fun currencies"""

GROUP_COMMON = "hour, wl_id, wl_user_id, player_mongo_id, token_mongo_id, game_id, country, currency, status, free_spins, freespin_transaction_mode"

def live(where_time):
    a = 'b'
    return f"""SELECT
    'Live'                                                                       AS product,
{COMMON_DIMS.format(a=a)}
    toString(b.roundMongoId)                                                     AS round_mongo_id,   -- live: a round is shared by many players, so it stays in the grain (exact COUNTD of rounds)
    ''                                                                           AS action_name,
    nullIf(b.autoplay, '')                                                       AS autoplay,
    uniqExact(b.mongoId)                                                         AS bets,             -- unique bets
    CAST(NULL AS Nullable(UInt64))                                               AS slot_rounds,
{COMMON_MEASURES.format(a=a)}
FROM platform.bets AS b FINAL
{PARTNERS.format(a=a)}
WHERE {where_time.format(a=a)}
  AND b.status IN ('COMPLETED', 'FINALIZED')                                     -- settled bets
{FILTERS.format(a=a)}
GROUP BY {GROUP_COMMON}, round_mongo_id, autoplay"""

def slots(where_time):
    a = 's'
    return f"""SELECT
    'Slots'                                                                      AS product,
{COMMON_DIMS.format(a=a)}
    ''                                                                           AS round_mongo_id,   -- slots: 1 round = 1 player, counted in slot_rounds
    s.actionName                                                                 AS action_name,
    CAST(NULL AS Nullable(String))                                               AS autoplay,
    uniqExactIf(s.mongoId, s.betSize > 0)                                        AS bets,             -- unique bets = actions with a stake
    uniqExactIf((s.roundNumId, s.playerMongoId), s.roundStarted = 1)            AS slot_rounds,      -- counted on the starting action only -> summable
{COMMON_MEASURES.format(a=a)}
FROM platform.slot_actions AS s FINAL
{PARTNERS.format(a=a)}
WHERE {where_time.format(a=a)}
  AND s.status IN ('COMPLETED', 'FINALIZED', 'INTERNAL_TRANSACTION')             -- settled; INTERNAL_TRANSACTION = final-only free-spin wins
{FILTERS.format(a=a)}
GROUP BY {GROUP_COMMON}, action_name"""

# technical name -> CSV name. One row = one (hour, product, casino, game, currency, country,
# player, session[, live round][, slot action], status, free-spin context).
ALIASES = """    nullIf(action_name, '')                                             AS "actionName",
    toStartOfMonth(bet_date)                                            AS "Agregated date",
    autoplay                                                            AS "autoplay",
    bet_date                                                            AS "Bet_day_date",
    CAST(NULL AS Nullable(String))                                      AS "browser",
    CAST(NULL AS Nullable(String))                                      AS "browser_cmd",
    replaceRegexpAll(wl_name, '\\\\.prod$|-pragmatic|_v1|vegangster1', '') AS "Casino name",
    country                                                             AS "country",
    CAST(NULL AS Nullable(String))                                      AS "Country Code",
    country_name                                                        AS "Country Name",
    country_name                                                        AS "Country_name",
    CAST(NULL AS Nullable(DateTime('UTC')))                             AS "Created datetime",
    hour                                                                AS "Created hour",
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
    bets                                                                AS "mongoId",                 -- MEASURE: number of unique bets (SUM in Tableau)
    player_mongo_id                                                     AS "mongoId-2",               -- player id
    CAST(NULL AS Nullable(String))                                      AS "mongoId-3",
    CAST(NULL AS Nullable(String))                                      AS "name",
    CAST(NULL AS Nullable(String))                                      AS "os",
    CAST(NULL AS Nullable(String))                                      AS "os_cmd",
    partner_name                                                        AS "partner_name",
    CAST(NULL AS Nullable(String))                                      AS "platform_cmd",
    player_mongo_id                                                     AS "playerMongoId",
    CAST(NULL AS Nullable(String))                                      AS "playerMongoId-1",
    product                                                             AS "Product name",            -- Live / Slots
    country_name                                                        AS "real_country",
    country_name                                                        AS "Regions",
    CAST(NULL AS Nullable(String))                                      AS "result",
    nullIf(round_mongo_id, '')                                          AS "roundMongoId",            -- live only (COUNTD = live rounds)
    bet_date                                                            AS "Scaf date",
    CAST(NULL AS Nullable(String))                                      AS "screenResolution_cmd",
    CAST(NULL AS Nullable(String))                                      AS "Session mongo id",
    CAST(NULL AS Nullable(String))                                      AS "Session status",
    CAST(NULL AS Nullable(String))                                      AS "sex",
    status                                                              AS "status",
    CAST(NULL AS Nullable(String))                                      AS "status-2",
    -- latest timestamp of the row, Warsaw time, old source's format incl. its %M (= month name) bug
    formatDateTime(last_status_updated_at, '%Y-%m-%d %H:%M:%S', 'Europe/Warsaw') AS "statusUpdatedAt_str",
    currency                                                            AS "symbol",
    'localhost/CHTotalEGoverview2026/sqlproxy'                          AS "Table Names",
    'localhost/CHJoinedroundsandbets2026/sqlproxy'                      AS "Table Names-1",
    CAST(NULL AS Nullable(String))                                      AS "timeToPlay_cmd",
    CAST(NULL AS Nullable(String))                                      AS "title",
    currency_title                                                      AS "Title",
    token_mongo_id                                                      AS "tokenMongoId",            -- session id (COUNTD = sessions)
    currency_type                                                       AS "Type",
    CAST(NULL AS Nullable(String))                                      AS "type",
    CAST(NULL AS Nullable(DateTime('UTC')))                             AS "updatedAt-1",
    formatDateTime(last_updated_at, '%Y-%m-%d %H:%M:%S', 'Europe/Warsaw') AS "updatedAt_str",
    CAST(NULL AS Nullable(String))                                      AS "wl label",
    wl_name                                                             AS "wl name",
    wl_id                                                               AS "wlId",
    wl_user_id                                                          AS "wlUserId",
    CAST(NULL AS Nullable(String))                                      AS "wlUserId-2",
    CAST(NULL AS Nullable(Float64))                                     AS "all_rounds",
    bet_size                                                            AS "betSize",                 -- sum, player currency
    CAST(NULL AS Nullable(String))                                      AS "id",
    toUInt32(toUnixTimestamp(hour))                                     AS "incremental_id",          -- unix time of the hour
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
    slot_rounds                                                         AS "Spins rounds",            -- MEASURE: slot rounds (SUM); NULL for live
    converted_bet                                                       AS "Sum of bet €",            -- sum, EUR
    converted_win                                                       AS "Sum of win €",            -- sum, EUR
    CAST(NULL AS Nullable(Float64))                                     AS "timeToEndJoin_in_seconds",
    wl_is_test                                                          AS "wl is test",
    CAST(NULL AS Nullable(UInt8))                                       AS "wl is test ",
    won                                                                 AS "won"                      -- sum, player currency"""
