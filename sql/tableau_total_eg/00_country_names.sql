-- Step 0. Country names (ISO 3166-1 alpha-2 -> English short name).
--
-- ClickHouse has no country-name table: platform.bets.country is an ISO code.
-- The CSV of the old Tableau source has 4 identical name columns
-- ("Country Name", "Country_name", "real_country", "Regions") in the ISO 3166-1
-- English short-name style WITH COMMAS REMOVED ("Korea Republic of",
-- "Congo Democratic Republic of the") and the pre-2022 "Turkey".
-- The 57 codes present in the CSV were checked 1:1; the rest follow the same rule.
-- An unknown code (XK, T1, 'unknown', '') falls back to the code itself (dictGetOrDefault).

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

-- check: 249 rows, and the CSV examples
SELECT count() FROM bi_sandbox.country_names;
SELECT dictGetOrDefault('bi_sandbox.country_names_d', 'name', 'KR', 'KR'),   -- Korea Republic of
       dictGetOrDefault('bi_sandbox.country_names_d', 'name', 'CD', 'CD'),   -- Congo Democratic Republic of the
       dictGetOrDefault('bi_sandbox.country_names_d', 'name', 'XK', 'XK');   -- XK (fallback = code)
