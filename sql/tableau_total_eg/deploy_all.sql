-- Total EG: full deployment = 00 + 02 + 03 without comments (sources: those files).
-- Run in the ProdCH SQL console as an admin, top to bottom. Replace <RANDOM_PASSWORD> first.
-- Then: SELECT view, status, exception FROM system.view_refreshes WHERE database = 'bi_sandbox' AND view LIKE 'bi_total_eg%';

-- ===== 00_country_names.sql =====
CREATE TABLE IF NOT EXISTS bi_sandbox.country_names
(
    code String,
    name String
)
ENGINE = MergeTree
ORDER BY code;

CREATE DICTIONARY IF NOT EXISTS bi_sandbox.country_names_d
(
    code String,
    name String
)
PRIMARY KEY code
SOURCE(CLICKHOUSE(DB 'bi_sandbox' TABLE 'country_names'))
LIFETIME(MIN 3600 MAX 7200)
LAYOUT(COMPLEX_KEY_HASHED());

TRUNCATE TABLE bi_sandbox.country_names;
INSERT INTO bi_sandbox.country_names (code, name) VALUES
('AD','Andorra'),('AE','United Arab Emirates'),('AF','Afghanistan'),('AG','Antigua and Barbuda'),
('AI','Anguilla'),('AL','Albania'),('AM','Armenia'),('AO','Angola'),('AQ','Antarctica'),
('AR','Argentina'),('AS','American Samoa'),('AT','Austria'),('AU','Australia'),('AW','Aruba'),
('AX','Åland Islands'),('AZ','Azerbaijan'),('BA','Bosnia and Herzegovina'),('BB','Barbados'),
('BD','Bangladesh'),('BE','Belgium'),('BF','Burkina Faso'),('BG','Bulgaria'),('BH','Bahrain'),
('BI','Burundi'),('BJ','Benin'),('BL','Saint Barthélemy'),('BM','Bermuda'),('BN','Brunei Darussalam'),
('BO','Bolivia (Plurinational State of)'),('BQ','Bonaire Sint Eustatius and Saba'),('BR','Brazil'),
('BS','Bahamas'),('BT','Bhutan'),('BV','Bouvet Island'),('BW','Botswana'),('BY','Belarus'),
('BZ','Belize'),('CA','Canada'),('CC','Cocos (Keeling) Islands'),('CD','Congo Democratic Republic of the'),
('CF','Central African Republic'),('CG','Congo'),('CH','Switzerland'),('CI','Côte d''Ivoire'),
('CK','Cook Islands'),('CL','Chile'),('CM','Cameroon'),('CN','China'),('CO','Colombia'),
('CR','Costa Rica'),('CU','Cuba'),('CV','Cabo Verde'),('CW','Curaçao'),('CX','Christmas Island'),
('CY','Cyprus'),('CZ','Czechia'),('DE','Germany'),('DJ','Djibouti'),('DK','Denmark'),('DM','Dominica'),
('DO','Dominican Republic'),('DZ','Algeria'),('EC','Ecuador'),('EE','Estonia'),('EG','Egypt'),
('EH','Western Sahara'),('ER','Eritrea'),('ES','Spain'),('ET','Ethiopia'),('FI','Finland'),('FJ','Fiji'),
('FK','Falkland Islands (Malvinas)'),('FM','Micronesia (Federated States of)'),('FO','Faroe Islands'),
('FR','France'),('GA','Gabon'),('GB','United Kingdom of Great Britain and Northern Ireland'),
('GD','Grenada'),('GE','Georgia'),('GF','French Guiana'),('GG','Guernsey'),('GH','Ghana'),
('GI','Gibraltar'),('GL','Greenland'),('GM','Gambia'),('GN','Guinea'),('GP','Guadeloupe'),
('GQ','Equatorial Guinea'),('GR','Greece'),('GS','South Georgia and the South Sandwich Islands'),
('GT','Guatemala'),('GU','Guam'),('GW','Guinea-Bissau'),('GY','Guyana'),('HK','Hong Kong'),
('HM','Heard Island and McDonald Islands'),('HN','Honduras'),('HR','Croatia'),('HT','Haiti'),
('HU','Hungary'),('ID','Indonesia'),('IE','Ireland'),('IL','Israel'),('IM','Isle of Man'),('IN','India'),
('IO','British Indian Ocean Territory'),('IQ','Iraq'),('IR','Iran (Islamic Republic of)'),('IS','Iceland'),
('IT','Italy'),('JE','Jersey'),('JM','Jamaica'),('JO','Jordan'),('JP','Japan'),('KE','Kenya'),
('KG','Kyrgyzstan'),('KH','Cambodia'),('KI','Kiribati'),('KM','Comoros'),('KN','Saint Kitts and Nevis'),
('KP','Korea (Democratic People''s Republic of)'),('KR','Korea Republic of'),('KW','Kuwait'),
('KY','Cayman Islands'),('KZ','Kazakhstan'),('LA','Lao People''s Democratic Republic'),('LB','Lebanon'),
('LC','Saint Lucia'),('LI','Liechtenstein'),('LK','Sri Lanka'),('LR','Liberia'),('LS','Lesotho'),
('LT','Lithuania'),('LU','Luxembourg'),('LV','Latvia'),('LY','Libya'),('MA','Morocco'),('MC','Monaco'),
('MD','Moldova Republic of'),('ME','Montenegro'),('MF','Saint Martin (French part)'),('MG','Madagascar'),
('MH','Marshall Islands'),('MK','North Macedonia'),('ML','Mali'),('MM','Myanmar'),('MN','Mongolia'),
('MO','Macao'),('MP','Northern Mariana Islands'),('MQ','Martinique'),('MR','Mauritania'),('MS','Montserrat'),
('MT','Malta'),('MU','Mauritius'),('MV','Maldives'),('MW','Malawi'),('MX','Mexico'),('MY','Malaysia'),
('MZ','Mozambique'),('NA','Namibia'),('NC','New Caledonia'),('NE','Niger'),('NF','Norfolk Island'),
('NG','Nigeria'),('NI','Nicaragua'),('NL','Netherlands'),('NO','Norway'),('NP','Nepal'),('NR','Nauru'),
('NU','Niue'),('NZ','New Zealand'),('OM','Oman'),('PA','Panama'),('PE','Peru'),('PF','French Polynesia'),
('PG','Papua New Guinea'),('PH','Philippines'),('PK','Pakistan'),('PL','Poland'),
('PM','Saint Pierre and Miquelon'),('PN','Pitcairn'),('PR','Puerto Rico'),('PS','Palestine State of'),
('PT','Portugal'),('PW','Palau'),('PY','Paraguay'),('QA','Qatar'),('RE','Réunion'),('RO','Romania'),
('RS','Serbia'),('RU','Russian Federation'),('RW','Rwanda'),('SA','Saudi Arabia'),('SB','Solomon Islands'),
('SC','Seychelles'),('SD','Sudan'),('SE','Sweden'),('SG','Singapore'),
('SH','Saint Helena Ascension and Tristan da Cunha'),('SI','Slovenia'),('SJ','Svalbard and Jan Mayen'),
('SK','Slovakia'),('SL','Sierra Leone'),('SM','San Marino'),('SN','Senegal'),('SO','Somalia'),
('SR','Suriname'),('SS','South Sudan'),('ST','Sao Tome and Principe'),('SV','El Salvador'),
('SX','Sint Maarten (Dutch part)'),('SY','Syrian Arab Republic'),('SZ','Eswatini'),
('TC','Turks and Caicos Islands'),('TD','Chad'),('TF','French Southern Territories'),('TG','Togo'),
('TH','Thailand'),('TJ','Tajikistan'),('TK','Tokelau'),('TL','Timor-Leste'),('TM','Turkmenistan'),
('TN','Tunisia'),('TO','Tonga'),('TR','Turkey'),('TT','Trinidad and Tobago'),('TV','Tuvalu'),
('TW','Taiwan Province of China'),('TZ','Tanzania United Republic of'),('UA','Ukraine'),('UG','Uganda'),
('UM','United States Minor Outlying Islands'),('US','United States of America'),('UY','Uruguay'),
('UZ','Uzbekistan'),('VA','Holy See'),('VC','Saint Vincent and the Grenadines'),
('VE','Venezuela (Bolivarian Republic of)'),('VG','Virgin Islands (British)'),('VI','Virgin Islands (U.S.)'),
('VN','Viet Nam'),('VU','Vanuatu'),('WF','Wallis and Futuna'),('WS','Samoa'),('YE','Yemen'),
('YT','Mayotte'),('ZA','South Africa'),('ZM','Zambia'),('ZW','Zimbabwe');

SYSTEM RELOAD DICTIONARY bi_sandbox.country_names_d;

SELECT count() FROM bi_sandbox.country_names;
SELECT dictGetOrDefault('bi_sandbox.country_names_d', 'name', 'KR', 'KR'),
       dictGetOrDefault('bi_sandbox.country_names_d', 'name', 'CD', 'CD'),
       dictGetOrDefault('bi_sandbox.country_names_d', 'name', 'XK', 'XK');

-- ===== 02_history_tables.sql =====
CREATE USER IF NOT EXISTS bi_total_eg_definer
    IDENTIFIED WITH sha256_password BY '<RANDOM_PASSWORD>'
    HOST NONE;

GRANT SELECT  ON platform.bets               TO bi_total_eg_definer;
GRANT SELECT  ON platform.slot_actions       TO bi_total_eg_definer;
GRANT SELECT  ON platform.partners_d         TO bi_total_eg_definer;
GRANT dictGet ON platform.partners_d         TO bi_total_eg_definer;
GRANT dictGet ON platform.whitelabels_d      TO bi_total_eg_definer;
GRANT dictGet ON platform.currency_d         TO bi_total_eg_definer;
GRANT dictGet ON bi_sandbox.country_names_d  TO bi_total_eg_definer;
GRANT SELECT, INSERT, CREATE TABLE, DROP TABLE, TRUNCATE ON bi_sandbox.* TO bi_total_eg_definer;

CREATE TABLE IF NOT EXISTS bi_sandbox.bi_total_eg_hourly
(
    product                    LowCardinality(String),              -- 'Live' / 'Slots'
    hour                       DateTime('UTC'),
    bet_date                   Date,

    wl_id                      LowCardinality(String),
    wl_name                    LowCardinality(String),
    wl_label                   LowCardinality(String),
    wl_is_test                 UInt8,
    partner_name               LowCardinality(Nullable(String)),
    wl_user_id                 String,
    player_mongo_id            String,
    token_mongo_id             String,

    game_id                    LowCardinality(String),
    country                    LowCardinality(String),
    country_name               LowCardinality(String),

    currency                   LowCardinality(String),
    currency_title             LowCardinality(String),
    currency_type              LowCardinality(String),
    is_fun                     UInt8,

    status                     LowCardinality(String),
    free_spins                 Nullable(String),
    freespin_transaction_mode  LowCardinality(Nullable(String)),

    round_mongo_id             String,                              -- live round; '' for slots
    action_name                LowCardinality(String),              -- slot action; '' for live
    autoplay                   Nullable(String),

    bets                       UInt64,
    slot_rounds                Nullable(UInt64),
    bet_size                   Decimal(38, 12),
    won                        Decimal(38, 12),
    converted_bet              Decimal(38, 4),
    converted_win              Decimal(38, 4),
    last_updated_at            DateTime64(6, 'UTC'),
    last_status_updated_at     DateTime64(6, 'UTC'),

    loaded_at                  DateTime DEFAULT now()
)
ENGINE = MergeTree
PARTITION BY toYYYYMM(bet_date)
ORDER BY (bet_date, product, wl_id, game_id, hour);

CREATE TABLE IF NOT EXISTS bi_sandbox.bi_total_eg_hourly_recent
AS bi_sandbox.bi_total_eg_hourly
ENGINE = MergeTree
PARTITION BY toYYYYMM(bet_date)
ORDER BY (bet_date, product, wl_id, game_id, hour);

-- ===== 03_history_mvs_and_view.sql =====
CREATE MATERIALIZED VIEW IF NOT EXISTS bi_sandbox.bi_total_eg_live_mv
REFRESH EVERY 5 MINUTE
APPEND TO bi_sandbox.bi_total_eg_hourly
DEFINER = bi_total_eg_definer SQL SECURITY DEFINER
AS
WITH
    toDate('2022-12-19')                                                           AS start_day,
    toDate(now(), 'UTC')                                                         AS today,
    greatest((SELECT maxIf(bet_date, product = 'Live') FROM bi_sandbox.bi_total_eg_hourly) + 1, start_day) AS date_from,
    least(date_from + 91, today - 2)                                             AS date_to
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
    dictGetOrDefault('bi_sandbox.country_names_d', 'name', b.country, b.country) AS country_name,
    b.currency                                                                 AS currency,
    dictGetOrDefault('platform.currency_d', 'title', b.currency, '')           AS currency_title,
    ifNull(dictGetOrDefault('platform.currency_d', 'type', b.currency, ''), '') AS currency_type,
    dictGetOrDefault('platform.currency_d', 'isFun', b.currency, toUInt8(0))   AS is_fun,
    b.status                                                                   AS status,
    nullIf(replaceAll(ifNull(toString(b.freeSpins), ''), '\0', ''), '')       AS free_spins,
    b.freespinTransactionMode                                                  AS freespin_transaction_mode,
    toString(b.roundMongoId)                                                     AS round_mongo_id,
    ''                                                                           AS action_name,
    nullIf(b.autoplay, '')                                                       AS autoplay,
    uniqExact(b.mongoId)                                                         AS bets,
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
  AND date_to >= date_from
  AND b.status IN ('COMPLETED', 'FINALIZED')
  AND dictGetOrDefault('platform.whitelabels_d', 'isTest', b.wlId, toUInt8(0)) = 0
  AND dictGetOrDefault('platform.currency_d', 'isFun', b.currency, toUInt8(0)) = 0
GROUP BY hour, wl_id, wl_user_id, player_mongo_id, token_mongo_id, game_id, country, currency, status, free_spins, freespin_transaction_mode, round_mongo_id, autoplay
SETTINGS max_bytes_before_external_group_by = 8000000000;

CREATE MATERIALIZED VIEW IF NOT EXISTS bi_sandbox.bi_total_eg_slots_mv
REFRESH EVERY 1 MINUTE
APPEND TO bi_sandbox.bi_total_eg_hourly
DEFINER = bi_total_eg_definer SQL SECURITY DEFINER
AS
WITH
    toDate('2024-10-29')                                                           AS start_day,
    toDate(now(), 'UTC')                                                         AS today,
    greatest((SELECT maxIf(bet_date, product = 'Slots') FROM bi_sandbox.bi_total_eg_hourly) + 1, start_day) AS date_from,
    least(date_from + 2, today - 2)                                             AS date_to
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
    dictGetOrDefault('bi_sandbox.country_names_d', 'name', s.country, s.country) AS country_name,
    s.currency                                                                 AS currency,
    dictGetOrDefault('platform.currency_d', 'title', s.currency, '')           AS currency_title,
    ifNull(dictGetOrDefault('platform.currency_d', 'type', s.currency, ''), '') AS currency_type,
    dictGetOrDefault('platform.currency_d', 'isFun', s.currency, toUInt8(0))   AS is_fun,
    s.status                                                                   AS status,
    nullIf(replaceAll(ifNull(toString(s.freeSpins), ''), '\0', ''), '')       AS free_spins,
    s.freespinTransactionMode                                                  AS freespin_transaction_mode,
    ''                                                                           AS round_mongo_id,
    s.actionName                                                                 AS action_name,
    CAST(NULL AS Nullable(String))                                               AS autoplay,
    uniqExactIf(s.mongoId, s.betSize > 0)                                        AS bets,
    uniqExactIf((s.roundNumId, s.playerMongoId), s.roundStarted = 1)            AS slot_rounds,
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
WHERE s.createdAt >= toDateTime64(date_from, 6, 'UTC')
  AND s.createdAt <  toDateTime64(date_to + 1, 6, 'UTC')
  AND date_to >= date_from
  AND s.status IN ('COMPLETED', 'FINALIZED', 'INTERNAL_TRANSACTION')
  AND dictGetOrDefault('platform.whitelabels_d', 'isTest', s.wlId, toUInt8(0)) = 0
  AND dictGetOrDefault('platform.currency_d', 'isFun', s.currency, toUInt8(0)) = 0
GROUP BY hour, wl_id, wl_user_id, player_mongo_id, token_mongo_id, game_id, country, currency, status, free_spins, freespin_transaction_mode, action_name
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
        dictGetOrDefault('bi_sandbox.country_names_d', 'name', b.country, b.country) AS country_name,
        b.currency                                                                 AS currency,
        dictGetOrDefault('platform.currency_d', 'title', b.currency, '')           AS currency_title,
        ifNull(dictGetOrDefault('platform.currency_d', 'type', b.currency, ''), '') AS currency_type,
        dictGetOrDefault('platform.currency_d', 'isFun', b.currency, toUInt8(0))   AS is_fun,
        b.status                                                                   AS status,
        nullIf(replaceAll(ifNull(toString(b.freeSpins), ''), '\0', ''), '')       AS free_spins,
        b.freespinTransactionMode                                                  AS freespin_transaction_mode,
        toString(b.roundMongoId)                                                     AS round_mongo_id,
        ''                                                                           AS action_name,
        nullIf(b.autoplay, '')                                                       AS autoplay,
        uniqExact(b.mongoId)                                                         AS bets,
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
      AND b.status IN ('COMPLETED', 'FINALIZED')
      AND dictGetOrDefault('platform.whitelabels_d', 'isTest', b.wlId, toUInt8(0)) = 0
      AND dictGetOrDefault('platform.currency_d', 'isFun', b.currency, toUInt8(0)) = 0
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
        dictGetOrDefault('bi_sandbox.country_names_d', 'name', s.country, s.country) AS country_name,
        s.currency                                                                 AS currency,
        dictGetOrDefault('platform.currency_d', 'title', s.currency, '')           AS currency_title,
        ifNull(dictGetOrDefault('platform.currency_d', 'type', s.currency, ''), '') AS currency_type,
        dictGetOrDefault('platform.currency_d', 'isFun', s.currency, toUInt8(0))   AS is_fun,
        s.status                                                                   AS status,
        nullIf(replaceAll(ifNull(toString(s.freeSpins), ''), '\0', ''), '')       AS free_spins,
        s.freespinTransactionMode                                                  AS freespin_transaction_mode,
        ''                                                                           AS round_mongo_id,
        s.actionName                                                                 AS action_name,
        CAST(NULL AS Nullable(String))                                               AS autoplay,
        uniqExactIf(s.mongoId, s.betSize > 0)                                        AS bets,
        uniqExactIf((s.roundNumId, s.playerMongoId), s.roundStarted = 1)            AS slot_rounds,
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
      AND s.status IN ('COMPLETED', 'FINALIZED', 'INTERNAL_TRANSACTION')
      AND dictGetOrDefault('platform.whitelabels_d', 'isTest', s.wlId, toUInt8(0)) = 0
      AND dictGetOrDefault('platform.currency_d', 'isFun', s.currency, toUInt8(0)) = 0
    GROUP BY hour, wl_id, wl_user_id, player_mongo_id, token_mongo_id, game_id, country, currency, status, free_spins, freespin_transaction_mode, action_name
)
SETTINGS max_bytes_before_external_group_by = 8000000000;

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
    bets                                                                AS "mongoId",
    player_mongo_id                                                     AS "mongoId-2",
    CAST(NULL AS Nullable(String))                                      AS "mongoId-3",
    CAST(NULL AS Nullable(String))                                      AS "name",
    CAST(NULL AS Nullable(String))                                      AS "os",
    CAST(NULL AS Nullable(String))                                      AS "os_cmd",
    partner_name                                                        AS "partner_name",
    CAST(NULL AS Nullable(String))                                      AS "platform_cmd",
    player_mongo_id                                                     AS "playerMongoId",
    CAST(NULL AS Nullable(String))                                      AS "playerMongoId-1",
    product                                                             AS "Product name",
    country_name                                                        AS "real_country",
    country_name                                                        AS "Regions",
    CAST(NULL AS Nullable(String))                                      AS "result",
    nullIf(round_mongo_id, '')                                          AS "roundMongoId",
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
    token_mongo_id                                                      AS "tokenMongoId",
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
    bet_size                                                            AS "betSize",
    CAST(NULL AS Nullable(String))                                      AS "id",
    toUInt32(toUnixTimestamp(hour))                                     AS "incremental_id",
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
    slot_rounds                                                         AS "Spins rounds",
    converted_bet                                                       AS "Sum of bet €",
    converted_win                                                       AS "Sum of win €",
    CAST(NULL AS Nullable(Float64))                                     AS "timeToEndJoin_in_seconds",
    wl_is_test                                                          AS "wl is test",
    CAST(NULL AS Nullable(UInt8))                                       AS "wl is test ",
    won                                                                 AS "won"
FROM
(
    SELECT * FROM bi_sandbox.bi_total_eg_hourly
    UNION ALL
    SELECT * FROM bi_sandbox.bi_total_eg_hourly_recent
    WHERE bet_date > if(product = 'Live', hist_max_live, hist_max_slots)
);
