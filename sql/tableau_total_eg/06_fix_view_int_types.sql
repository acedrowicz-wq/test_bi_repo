-- Step 6 (2026-10-10). Integer columns of the view as signed types: Tableau's ClickHouse driver reads
-- UInt64 as a string ("mongoId", "Spins rounds" could not be summed).
--   "mongoId", "Spins rounds", "incremental_id" -> Int64;  "isFun", "wl is test" -> Int32.
-- Only the view is replaced: no data is touched, the MVs keep loading. Run in the ProdCH SQL console.
-- In Tableau afterwards: Data -> Refresh (the fields become numbers; INT() wrappers can be removed).

CREATE OR REPLACE VIEW bi_sandbox.bi_total_eg_v
AS
WITH
    (SELECT maxIf(bet_date, product = 'Live')  FROM bi_sandbox.bi_total_eg_hourly) AS hist_max_live,
    (SELECT maxIf(bet_date, product = 'Slots') FROM bi_sandbox.bi_total_eg_hourly) AS hist_max_slots
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
    CAST(NULL AS Nullable(String))                                      AS "spin mongoId",
    toInt64(slot_rounds)                                                AS "Spins rounds",            -- MEASURE: slot rounds (SUM); NULL for live
    converted_bet                                                       AS "Sum of bet €",            -- sum, EUR
    converted_win                                                       AS "Sum of win €",            -- sum, EUR
    CAST(NULL AS Nullable(Float64))                                     AS "timeToEndJoin_in_seconds",
    toInt32(wl_is_test)                                                 AS "wl is test",
    CAST(NULL AS Nullable(Int32))                                       AS "wl is test ",
    won                                                                 AS "won"                      -- sum, player currency
FROM
(
    SELECT * FROM bi_sandbox.bi_total_eg_hourly
    UNION ALL
    SELECT * FROM bi_sandbox.bi_total_eg_hourly_recent
    WHERE bet_date > if(product = 'Live', hist_max_live, hist_max_slots)
);

-- check: no UInt* left
SELECT name, type FROM system.columns
WHERE database = 'bi_sandbox' AND table = 'bi_total_eg_v' AND type LIKE '%UInt%';
