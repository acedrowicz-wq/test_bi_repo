-- Step 2. Operational query: the LAST 3 DAYS (UTC), hourly grain, with the exact
-- column names of the CSV "Total_EG_datasource" (Tableau). Live + Slots.
--
-- Grain (1 row): hour (UTC) x product x casino x game x currency x country x player
--                x session (tokenMongoId) x status x free-spin context
--                + live: round (roundMongoId)   + slots: action (actionName).
-- There is no single-bet information: "mongoId" is the NUMBER OF UNIQUE BETS of the row
-- (a measure, SUM in Tableau), "Spins rounds" the number of slot rounds (SUM).
-- COUNTD of players ("wlUserId", "playerMongoId"), sessions ("tokenMongoId") and live
-- rounds ("roundMongoId") stay exact, because those ids are part of the grain.
-- Fields Tableau computes itself (period flags, parameters, formatted measures) stay in
-- the workbook - see README.md.
--
-- Self-contained: no objects needed (country names are inlined with transform()).
-- Performance: platform.bets and platform.slot_actions are PARTITION BY toStartOfMonth(createdAt),
-- ORDER BY (toStartOfHour(createdAt), wlUserId, mongoId): the createdAt bound prunes partitions
-- and granules. Measured on ProdCH: 1 day of slots (22 M actions -> 0.5 M rows) = ~4 s;
-- live is ~1% of that.

SELECT
    nullIf(action_name, '')                                             AS "actionName",
    toStartOfMonth(bet_date)                                            AS "Agregated date",
    autoplay                                                            AS "autoplay",
    bet_date                                                            AS "Bet_day_date",
    CAST(NULL AS Nullable(String))                                      AS "browser",
    CAST(NULL AS Nullable(String))                                      AS "browser_cmd",
    replaceRegexpAll(wl_name, '\\.prod$|-pragmatic|_v1|vegangster1', '') AS "Casino name",
    country                                                             AS "country",
    CAST(NULL AS Nullable(String))                                      AS "Country Code",
    transform(toString(country), ['AD','AE','AF','AG','AI','AL','AM','AO','AQ','AR','AS','AT','AU','AW','AX','AZ','BA','BB','BD','BE','BF','BG','BH','BI','BJ','BL','BM','BN','BO','BQ','BR','BS','BT','BV','BW','BY','BZ','CA','CC','CD','CF','CG','CH','CI','CK','CL','CM','CN','CO','CR','CU','CV','CW','CX','CY','CZ','DE','DJ','DK','DM','DO','DZ','EC','EE','EG','EH','ER','ES','ET','FI','FJ','FK','FM','FO','FR','GA','GB','GD','GE','GF','GG','GH','GI','GL','GM','GN','GP','GQ','GR','GS','GT','GU','GW','GY','HK','HM','HN','HR','HT','HU','ID','IE','IL','IM','IN','IO','IQ','IR','IS','IT','JE','JM','JO','JP','KE','KG','KH','KI','KM','KN','KP','KR','KW','KY','KZ','LA','LB','LC','LI','LK','LR','LS','LT','LU','LV','LY','MA','MC','MD','ME','MF','MG','MH','MK','ML','MM','MN','MO','MP','MQ','MR','MS','MT','MU','MV','MW','MX','MY','MZ','NA','NC','NE','NF','NG','NI','NL','NO','NP','NR','NU','NZ','OM','PA','PE','PF','PG','PH','PK','PL','PM','PN','PR','PS','PT','PW','PY','QA','RE','RO','RS','RU','RW','SA','SB','SC','SD','SE','SG','SH','SI','SJ','SK','SL','SM','SN','SO','SR','SS','ST','SV','SX','SY','SZ','TC','TD','TF','TG','TH','TJ','TK','TL','TM','TN','TO','TR','TT','TV','TW','TZ','UA','UG','UM','US','UY','UZ','VA','VC','VE','VG','VI','VN','VU','WF','WS','YE','YT','ZA','ZM','ZW'], ['Andorra','United Arab Emirates','Afghanistan','Antigua and Barbuda','Anguilla','Albania','Armenia','Angola','Antarctica','Argentina','American Samoa','Austria','Australia','Aruba','Åland Islands','Azerbaijan','Bosnia and Herzegovina','Barbados','Bangladesh','Belgium','Burkina Faso','Bulgaria','Bahrain','Burundi','Benin','Saint Barthélemy','Bermuda','Brunei Darussalam','Bolivia (Plurinational State of)','Bonaire Sint Eustatius and Saba','Brazil','Bahamas','Bhutan','Bouvet Island','Botswana','Belarus','Belize','Canada','Cocos (Keeling) Islands','Congo Democratic Republic of the','Central African Republic','Congo','Switzerland','Côte d''Ivoire','Cook Islands','Chile','Cameroon','China','Colombia','Costa Rica','Cuba','Cabo Verde','Curaçao','Christmas Island','Cyprus','Czechia','Germany','Djibouti','Denmark','Dominica','Dominican Republic','Algeria','Ecuador','Estonia','Egypt','Western Sahara','Eritrea','Spain','Ethiopia','Finland','Fiji','Falkland Islands (Malvinas)','Micronesia (Federated States of)','Faroe Islands','France','Gabon','United Kingdom of Great Britain and Northern Ireland','Grenada','Georgia','French Guiana','Guernsey','Ghana','Gibraltar','Greenland','Gambia','Guinea','Guadeloupe','Equatorial Guinea','Greece','South Georgia and the South Sandwich Islands','Guatemala','Guam','Guinea-Bissau','Guyana','Hong Kong','Heard Island and McDonald Islands','Honduras','Croatia','Haiti','Hungary','Indonesia','Ireland','Israel','Isle of Man','India','British Indian Ocean Territory','Iraq','Iran (Islamic Republic of)','Iceland','Italy','Jersey','Jamaica','Jordan','Japan','Kenya','Kyrgyzstan','Cambodia','Kiribati','Comoros','Saint Kitts and Nevis','Korea (Democratic People''s Republic of)','Korea Republic of','Kuwait','Cayman Islands','Kazakhstan','Lao People''s Democratic Republic','Lebanon','Saint Lucia','Liechtenstein','Sri Lanka','Liberia','Lesotho','Lithuania','Luxembourg','Latvia','Libya','Morocco','Monaco','Moldova Republic of','Montenegro','Saint Martin (French part)','Madagascar','Marshall Islands','North Macedonia','Mali','Myanmar','Mongolia','Macao','Northern Mariana Islands','Martinique','Mauritania','Montserrat','Malta','Mauritius','Maldives','Malawi','Mexico','Malaysia','Mozambique','Namibia','New Caledonia','Niger','Norfolk Island','Nigeria','Nicaragua','Netherlands','Norway','Nepal','Nauru','Niue','New Zealand','Oman','Panama','Peru','French Polynesia','Papua New Guinea','Philippines','Pakistan','Poland','Saint Pierre and Miquelon','Pitcairn','Puerto Rico','Palestine State of','Portugal','Palau','Paraguay','Qatar','Réunion','Romania','Serbia','Russian Federation','Rwanda','Saudi Arabia','Solomon Islands','Seychelles','Sudan','Sweden','Singapore','Saint Helena Ascension and Tristan da Cunha','Slovenia','Svalbard and Jan Mayen','Slovakia','Sierra Leone','San Marino','Senegal','Somalia','Suriname','South Sudan','Sao Tome and Principe','El Salvador','Sint Maarten (Dutch part)','Syrian Arab Republic','Eswatini','Turks and Caicos Islands','Chad','French Southern Territories','Togo','Thailand','Tajikistan','Tokelau','Timor-Leste','Turkmenistan','Tunisia','Tonga','Turkey','Trinidad and Tobago','Tuvalu','Taiwan Province of China','Tanzania United Republic of','Ukraine','Uganda','United States Minor Outlying Islands','United States of America','Uruguay','Uzbekistan','Holy See','Saint Vincent and the Grenadines','Venezuela (Bolivarian Republic of)','Virgin Islands (British)','Virgin Islands (U.S.)','Viet Nam','Vanuatu','Wallis and Futuna','Samoa','Yemen','Mayotte','South Africa','Zambia','Zimbabwe'], toString(country)) AS "Country Name",   -- unknown code -> the code
    "Country Name"                                                      AS "Country_name",
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
    toInt64(bets)                                                       AS "mongoId",                 -- MEASURE: number of unique bets (SUM in Tableau)
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
    "Country Name"                                                      AS "real_country",
    "Country Name"                                                      AS "Regions",
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
    toInt64(toUnixTimestamp(hour))                                      AS "incremental_id",          -- unix time of the hour
    CAST(NULL AS Nullable(Int32))                                       AS "is_time_empty",
    toInt32(is_fun)                                                     AS "isFun",
    CAST(NULL AS Nullable(Float64))                                     AS "muted_button_clicks",
    CAST(NULL AS Nullable(Float64))                                     AS "muted_rounds",
    CAST(NULL AS Nullable(Int64))                                       AS "playerId",
    CAST(NULL AS Nullable(Int64))                                       AS "playerId-1",
    CAST(NULL AS Nullable(Int64))                                       AS "playerId-2",
    CAST(NULL AS Nullable(String))                                      AS "round_id",
    CAST(NULL AS Nullable(String))                                      AS "roundId",
    toInt64(actions)                                                    AS "spin mongoId",            -- MEASURE: unique slot actions (SUM); NULL for live
    toInt64(slot_rounds)                                                AS "slot_rounds",             -- MEASURE: slot rounds started (SUM); NULL for live. Not "Spins rounds": that is a workbook calculation
    converted_bet                                                       AS "Sum of bet €",            -- sum, EUR
    converted_win                                                       AS "Sum of win €",            -- sum, EUR
    CAST(NULL AS Nullable(Float64))                                     AS "timeToEndJoin_in_seconds",
    toInt32(wl_is_test)                                                 AS "wl is test",
    CAST(NULL AS Nullable(Int32))                                       AS "wl is test ",
    won                                                                 AS "won"                      -- sum, player currency
FROM
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
        CAST(NULL AS Nullable(UInt64))                                               AS actions,
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
        -- partner = the partner whose wls list contains the casino (old source's rule)
        SELECT arrayJoin(JSONExtract(wls, 'Array(String)')) AS wl_id, any(name) AS partner_name
        FROM platform.partners_d
        GROUP BY wl_id
    ) AS p ON p.wl_id = b.wlId
    WHERE b.createdAt >= toStartOfDay(now('UTC')) - INTERVAL 3 DAY                   -- the window: last 3 days (UTC)
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
        toNullable(uniqExact(s.mongoId))                                             AS actions,          -- unique slot actions ("spin mongoId")
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
        -- partner = the partner whose wls list contains the casino (old source's rule)
        SELECT arrayJoin(JSONExtract(wls, 'Array(String)')) AS wl_id, any(name) AS partner_name
        FROM platform.partners_d
        GROUP BY wl_id
    ) AS p ON p.wl_id = s.wlId
    WHERE s.createdAt >= toStartOfDay(now('UTC')) - INTERVAL 3 DAY                   -- the window: last 3 days (UTC)
      AND (s.status IN ('COMPLETED', 'FINALIZED', 'INTERNAL_TRANSACTION')            -- settled; INTERNAL_TRANSACTION = final-only free-spin wins
           OR (s.status = '' AND s.actionName IN ('bonus_init', 'hyperspin_init')))  -- bonus starts: empty status, no money, counted by the workbook calculation Spins rounds
      AND dictGetOrDefault('platform.whitelabels_d', 'isTest', s.wlId, toUInt8(0)) = 0    -- no test casinos
      AND dictGetOrDefault('platform.currency_d', 'isFun', s.currency, toUInt8(0)) = 0    -- no fun currencies
    GROUP BY hour, wl_id, wl_user_id, player_mongo_id, token_mongo_id, game_id, country, currency, status, free_spins, freespin_transaction_mode, action_name
)
SETTINGS max_bytes_before_external_group_by = 8000000000;
