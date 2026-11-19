/// Offline ISO 4217 world currency catalog and search helpers.
///
/// The backend accepts any valid 3-letter ISO 4217 code. This catalog lets the
/// phone offer every circulating world currency completely offline, along with
/// its symbol, full name, search keywords, and whether Frankfurter/ECB daily
/// rates are fetched automatically.
library;

/// Metadata for one ISO 4217 currency.
class CurrencyInfo {
  const CurrencyInfo({
    required this.code,
    required this.name,
    required this.symbol,
    this.keywords = const [],
    this.autoRates = false,
  });

  final String code;
  final String name;
  final String symbol;
  final List<String> keywords;

  /// True when the backend receives daily ECB/Frankfurter rates automatically.
  final bool autoRates;
}

/// Active circulating world currencies, sorted alphabetically by [CurrencyInfo.code].
const List<CurrencyInfo> allCurrencies = [
  CurrencyInfo(
    code: 'AED',
    name: 'UAE Dirham',
    symbol: 'د.إ',
    keywords: ['United Arab Emirates', 'Dubai', 'Abu Dhabi', 'Emirati'],
  ),
  CurrencyInfo(
    code: 'AFN',
    name: 'Afghan Afghani',
    symbol: '؋',
    keywords: ['Afghanistan', 'Kabul'],
  ),
  CurrencyInfo(
    code: 'ALL',
    name: 'Albanian Lek',
    symbol: 'L',
    keywords: ['Albania', 'Tirana'],
  ),
  CurrencyInfo(
    code: 'AMD',
    name: 'Armenian Dram',
    symbol: '֏',
    keywords: ['Armenia', 'Yerevan'],
  ),
  CurrencyInfo(
    code: 'ANG',
    name: 'Netherlands Antillean Guilder',
    symbol: 'ƒ',
    keywords: ['Curacao', 'Sint Maarten'],
  ),
  CurrencyInfo(
    code: 'AOA',
    name: 'Angolan Kwanza',
    symbol: 'Kz',
    keywords: ['Angola', 'Luanda'],
  ),
  CurrencyInfo(
    code: 'ARS',
    name: 'Argentine Peso',
    symbol: r'$',
    keywords: ['Argentina', 'Buenos Aires'],
  ),
  CurrencyInfo(
    code: 'AUD',
    name: 'Australian Dollar',
    symbol: r'A$',
    keywords: ['Australia', 'Sydney', 'Melbourne'],
    autoRates: true,
  ),
  CurrencyInfo(
    code: 'AWG',
    name: 'Aruban Florin',
    symbol: 'ƒ',
    keywords: ['Aruba'],
  ),
  CurrencyInfo(
    code: 'AZN',
    name: 'Azerbaijani Manat',
    symbol: '₼',
    keywords: ['Azerbaijan', 'Baku'],
  ),
  CurrencyInfo(
    code: 'BAM',
    name: 'Bosnia-Herzegovina Convertible Mark',
    symbol: 'KM',
    keywords: ['Bosnia', 'Herzegovina', 'Sarajevo'],
  ),
  CurrencyInfo(
    code: 'BBD',
    name: 'Barbadian Dollar',
    symbol: r'Bds$',
    keywords: ['Barbados', 'Bridgetown'],
  ),
  CurrencyInfo(
    code: 'BDT',
    name: 'Bangladeshi Taka',
    symbol: '৳',
    keywords: ['Bangladesh', 'Dhaka', 'taka'],
  ),
  CurrencyInfo(
    code: 'BGN',
    name: 'Bulgarian Lev',
    symbol: 'лв',
    keywords: ['Bulgaria', 'Sofia'],
    autoRates: true,
  ),
  CurrencyInfo(
    code: 'BHD',
    name: 'Bahraini Dinar',
    symbol: '.د.ب',
    keywords: ['Bahrain', 'Manama'],
  ),
  CurrencyInfo(
    code: 'BIF',
    name: 'Burundian Franc',
    symbol: 'FBu',
    keywords: ['Burundi'],
  ),
  CurrencyInfo(
    code: 'BMD',
    name: 'Bermudian Dollar',
    symbol: r'$',
    keywords: ['Bermuda'],
  ),
  CurrencyInfo(
    code: 'BND',
    name: 'Brunei Dollar',
    symbol: r'B$',
    keywords: ['Brunei'],
  ),
  CurrencyInfo(
    code: 'BOB',
    name: 'Bolivian Boliviano',
    symbol: 'Bs',
    keywords: ['Bolivia', 'La Paz'],
  ),
  CurrencyInfo(
    code: 'BRL',
    name: 'Brazilian Real',
    symbol: r'R$',
    keywords: ['Brazil', 'Sao Paulo', 'Rio'],
    autoRates: true,
  ),
  CurrencyInfo(
    code: 'BSD',
    name: 'Bahamian Dollar',
    symbol: r'B$',
    keywords: ['Bahamas', 'Nassau'],
  ),
  CurrencyInfo(
    code: 'BTN',
    name: 'Bhutanese Ngultrum',
    symbol: 'Nu.',
    keywords: ['Bhutan', 'Thimphu'],
  ),
  CurrencyInfo(
    code: 'BWP',
    name: 'Botswana Pula',
    symbol: 'P',
    keywords: ['Botswana', 'Gaborone'],
  ),
  CurrencyInfo(
    code: 'BYN',
    name: 'Belarusian Ruble',
    symbol: 'Br',
    keywords: ['Belarus', 'Minsk'],
  ),
  CurrencyInfo(
    code: 'BZD',
    name: 'Belize Dollar',
    symbol: r'BZ$',
    keywords: ['Belize'],
  ),
  CurrencyInfo(
    code: 'CAD',
    name: 'Canadian Dollar',
    symbol: r'CA$',
    keywords: ['Canada', 'Toronto', 'Vancouver', 'Ottawa'],
    autoRates: true,
  ),
  CurrencyInfo(
    code: 'CDF',
    name: 'Congolese Franc',
    symbol: 'FC',
    keywords: ['Congo', 'Kinshasa'],
  ),
  CurrencyInfo(
    code: 'CHF',
    name: 'Swiss Franc',
    symbol: 'CHF',
    keywords: ['Switzerland', 'Zurich', 'Geneva', 'Liechtenstein'],
    autoRates: true,
  ),
  CurrencyInfo(
    code: 'CLP',
    name: 'Chilean Peso',
    symbol: r'$',
    keywords: ['Chile', 'Santiago'],
  ),
  CurrencyInfo(
    code: 'CNY',
    name: 'Chinese Yuan',
    symbol: '¥',
    keywords: ['China', 'Beijing', 'Shanghai', 'renminbi', 'RMB'],
    autoRates: true,
  ),
  CurrencyInfo(
    code: 'COP',
    name: 'Colombian Peso',
    symbol: r'$',
    keywords: ['Colombia', 'Bogota'],
  ),
  CurrencyInfo(
    code: 'CRC',
    name: 'Costa Rican Colón',
    symbol: '₡',
    keywords: ['Costa Rica', 'San Jose', 'colon'],
  ),
  CurrencyInfo(
    code: 'CUP',
    name: 'Cuban Peso',
    symbol: r'$',
    keywords: ['Cuba', 'Havana'],
  ),
  CurrencyInfo(
    code: 'CVE',
    name: 'Cape Verdean Escudo',
    symbol: r'$',
    keywords: ['Cape Verde', 'Cabo Verde'],
  ),
  CurrencyInfo(
    code: 'CZK',
    name: 'Czech Koruna',
    symbol: 'Kč',
    keywords: ['Czechia', 'Czech Republic', 'Prague', 'crown'],
    autoRates: true,
  ),
  CurrencyInfo(
    code: 'DJF',
    name: 'Djiboutian Franc',
    symbol: 'Fdj',
    keywords: ['Djibouti'],
  ),
  CurrencyInfo(
    code: 'DKK',
    name: 'Danish Krone',
    symbol: 'kr',
    keywords: ['Denmark', 'Copenhagen', 'Greenland', 'Faroe'],
    autoRates: true,
  ),
  CurrencyInfo(
    code: 'DOP',
    name: 'Dominican Peso',
    symbol: r'RD$',
    keywords: ['Dominican Republic', 'Santo Domingo'],
  ),
  CurrencyInfo(
    code: 'DZD',
    name: 'Algerian Dinar',
    symbol: 'د.ج',
    keywords: ['Algeria', 'Algiers'],
  ),
  CurrencyInfo(
    code: 'EGP',
    name: 'Egyptian Pound',
    symbol: 'E£',
    keywords: ['Egypt', 'Cairo'],
  ),
  CurrencyInfo(
    code: 'ERN',
    name: 'Eritrean Nakfa',
    symbol: 'Nfk',
    keywords: ['Eritrea'],
  ),
  CurrencyInfo(
    code: 'ETB',
    name: 'Ethiopian Birr',
    symbol: 'Br',
    keywords: ['Ethiopia', 'Addis Ababa'],
  ),
  CurrencyInfo(
    code: 'EUR',
    name: 'Euro',
    symbol: '€',
    keywords: [
      'Eurozone',
      'Europe',
      'Germany',
      'France',
      'Italy',
      'Spain',
      'Netherlands',
      'Belgium',
      'Austria',
      'Ireland',
      'Portugal',
      'Finland',
      'Greece',
    ],
    autoRates: true,
  ),
  CurrencyInfo(
    code: 'FJD',
    name: 'Fijian Dollar',
    symbol: r'FJ$',
    keywords: ['Fiji'],
  ),
  CurrencyInfo(
    code: 'FKP',
    name: 'Falkland Islands Pound',
    symbol: '£',
    keywords: ['Falkland Islands'],
  ),
  CurrencyInfo(
    code: 'GBP',
    name: 'British Pound',
    symbol: '£',
    keywords: [
      'United Kingdom',
      'UK',
      'England',
      'Scotland',
      'Wales',
      'London',
      'sterling',
    ],
    autoRates: true,
  ),
  CurrencyInfo(
    code: 'GEL',
    name: 'Georgian Lari',
    symbol: '₾',
    keywords: ['Georgia', 'Tbilisi'],
  ),
  CurrencyInfo(
    code: 'GHS',
    name: 'Ghanaian Cedi',
    symbol: '₵',
    keywords: ['Ghana', 'Accra'],
  ),
  CurrencyInfo(
    code: 'GIP',
    name: 'Gibraltar Pound',
    symbol: '£',
    keywords: ['Gibraltar'],
  ),
  CurrencyInfo(
    code: 'GMD',
    name: 'Gambian Dalasi',
    symbol: 'D',
    keywords: ['Gambia'],
  ),
  CurrencyInfo(
    code: 'GNF',
    name: 'Guinean Franc',
    symbol: 'FG',
    keywords: ['Guinea', 'Conakry'],
  ),
  CurrencyInfo(
    code: 'GTQ',
    name: 'Guatemalan Quetzal',
    symbol: 'Q',
    keywords: ['Guatemala'],
  ),
  CurrencyInfo(
    code: 'GYD',
    name: 'Guyanese Dollar',
    symbol: r'G$',
    keywords: ['Guyana'],
  ),
  CurrencyInfo(
    code: 'HKD',
    name: 'Hong Kong Dollar',
    symbol: r'HK$',
    keywords: ['Hong Kong'],
    autoRates: true,
  ),
  CurrencyInfo(
    code: 'HNL',
    name: 'Honduran Lempira',
    symbol: 'L',
    keywords: ['Honduras'],
  ),
  CurrencyInfo(
    code: 'HTG',
    name: 'Haitian Gourde',
    symbol: 'G',
    keywords: ['Haiti'],
  ),
  CurrencyInfo(
    code: 'HUF',
    name: 'Hungarian Forint',
    symbol: 'Ft',
    keywords: ['Hungary', 'Budapest'],
    autoRates: true,
  ),
  CurrencyInfo(
    code: 'IDR',
    name: 'Indonesian Rupiah',
    symbol: 'Rp',
    keywords: ['Indonesia', 'Jakarta', 'Bali'],
    autoRates: true,
  ),
  CurrencyInfo(
    code: 'ILS',
    name: 'Israeli New Shekel',
    symbol: '₪',
    keywords: ['Israel', 'Tel Aviv', 'Jerusalem'],
    autoRates: true,
  ),
  CurrencyInfo(
    code: 'INR',
    name: 'Indian Rupee',
    symbol: '₹',
    keywords: ['India', 'Mumbai', 'Delhi', 'Bangalore'],
    autoRates: true,
  ),
  CurrencyInfo(
    code: 'IQD',
    name: 'Iraqi Dinar',
    symbol: 'ع.د',
    keywords: ['Iraq', 'Baghdad'],
  ),
  CurrencyInfo(
    code: 'IRR',
    name: 'Iranian Rial',
    symbol: '﷼',
    keywords: ['Iran', 'Tehran', 'toman'],
  ),
  CurrencyInfo(
    code: 'ISK',
    name: 'Icelandic Króna',
    symbol: 'kr',
    keywords: ['Iceland', 'Reykjavik', 'krona'],
    autoRates: true,
  ),
  CurrencyInfo(
    code: 'JMD',
    name: 'Jamaican Dollar',
    symbol: r'J$',
    keywords: ['Jamaica', 'Kingston'],
  ),
  CurrencyInfo(
    code: 'JOD',
    name: 'Jordanian Dinar',
    symbol: 'د.ا',
    keywords: ['Jordan', 'Amman'],
  ),
  CurrencyInfo(
    code: 'JPY',
    name: 'Japanese Yen',
    symbol: '¥',
    keywords: ['Japan', 'Tokyo', 'Osaka'],
    autoRates: true,
  ),
  CurrencyInfo(
    code: 'KES',
    name: 'Kenyan Shilling',
    symbol: 'KSh',
    keywords: ['Kenya', 'Nairobi'],
  ),
  CurrencyInfo(
    code: 'KGS',
    name: 'Kyrgyzstani Som',
    symbol: 'с',
    keywords: ['Kyrgyzstan', 'Bishkek'],
  ),
  CurrencyInfo(
    code: 'KHR',
    name: 'Cambodian Riel',
    symbol: '៛',
    keywords: ['Cambodia', 'Phnom Penh'],
  ),
  CurrencyInfo(
    code: 'KMF',
    name: 'Comorian Franc',
    symbol: 'CF',
    keywords: ['Comoros'],
  ),
  CurrencyInfo(
    code: 'KPW',
    name: 'North Korean Won',
    symbol: '₩',
    keywords: ['North Korea', 'Pyongyang'],
  ),
  CurrencyInfo(
    code: 'KRW',
    name: 'South Korean Won',
    symbol: '₩',
    keywords: ['South Korea', 'Korea', 'Seoul'],
    autoRates: true,
  ),
  CurrencyInfo(
    code: 'KWD',
    name: 'Kuwaiti Dinar',
    symbol: 'د.ك',
    keywords: ['Kuwait'],
  ),
  CurrencyInfo(
    code: 'KYD',
    name: 'Cayman Islands Dollar',
    symbol: r'CI$',
    keywords: ['Cayman Islands'],
  ),
  CurrencyInfo(
    code: 'KZT',
    name: 'Kazakhstani Tenge',
    symbol: '₸',
    keywords: ['Kazakhstan', 'Almaty', 'Astana'],
  ),
  CurrencyInfo(
    code: 'LAK',
    name: 'Lao Kip',
    symbol: '₭',
    keywords: ['Laos', 'Vientiane'],
  ),
  CurrencyInfo(
    code: 'LBP',
    name: 'Lebanese Pound',
    symbol: 'ل.ل',
    keywords: ['Lebanon', 'Beirut'],
  ),
  CurrencyInfo(
    code: 'LKR',
    name: 'Sri Lankan Rupee',
    symbol: 'Rs',
    keywords: ['Sri Lanka', 'Colombo'],
  ),
  CurrencyInfo(
    code: 'LRD',
    name: 'Liberian Dollar',
    symbol: r'L$',
    keywords: ['Liberia'],
  ),
  CurrencyInfo(
    code: 'LSL',
    name: 'Lesotho Loti',
    symbol: 'L',
    keywords: ['Lesotho'],
  ),
  CurrencyInfo(
    code: 'LYD',
    name: 'Libyan Dinar',
    symbol: 'ل.د',
    keywords: ['Libya', 'Tripoli'],
  ),
  CurrencyInfo(
    code: 'MAD',
    name: 'Moroccan Dirham',
    symbol: 'د.م.',
    keywords: ['Morocco', 'Casablanca', 'Rabat'],
  ),
  CurrencyInfo(
    code: 'MDL',
    name: 'Moldovan Leu',
    symbol: 'L',
    keywords: ['Moldova', 'Chisinau'],
  ),
  CurrencyInfo(
    code: 'MGA',
    name: 'Malagasy Ariary',
    symbol: 'Ar',
    keywords: ['Madagascar'],
  ),
  CurrencyInfo(
    code: 'MKD',
    name: 'Macedonian Denar',
    symbol: 'ден',
    keywords: ['North Macedonia', 'Skopje'],
  ),
  CurrencyInfo(
    code: 'MMK',
    name: 'Myanmar Kyat',
    symbol: 'K',
    keywords: ['Myanmar', 'Burma', 'Yangon'],
  ),
  CurrencyInfo(
    code: 'MNT',
    name: 'Mongolian Tugrik',
    symbol: '₮',
    keywords: ['Mongolia', 'Ulaanbaatar', 'togrog'],
  ),
  CurrencyInfo(
    code: 'MOP',
    name: 'Macanese Pataca',
    symbol: r'MOP$',
    keywords: ['Macau', 'Macao'],
  ),
  CurrencyInfo(
    code: 'MRU',
    name: 'Mauritanian Ouguiya',
    symbol: 'UM',
    keywords: ['Mauritania'],
  ),
  CurrencyInfo(
    code: 'MUR',
    name: 'Mauritian Rupee',
    symbol: '₨',
    keywords: ['Mauritius'],
  ),
  CurrencyInfo(
    code: 'MVR',
    name: 'Maldivian Rufiyaa',
    symbol: 'Rf',
    keywords: ['Maldives', 'Male'],
  ),
  CurrencyInfo(
    code: 'MWK',
    name: 'Malawian Kwacha',
    symbol: 'MK',
    keywords: ['Malawi'],
  ),
  CurrencyInfo(
    code: 'MXN',
    name: 'Mexican Peso',
    symbol: r'MX$',
    keywords: ['Mexico', 'Mexico City'],
    autoRates: true,
  ),
  CurrencyInfo(
    code: 'MYR',
    name: 'Malaysian Ringgit',
    symbol: 'RM',
    keywords: ['Malaysia', 'Kuala Lumpur'],
    autoRates: true,
  ),
  CurrencyInfo(
    code: 'MZN',
    name: 'Mozambican Metical',
    symbol: 'MT',
    keywords: ['Mozambique', 'Maputo'],
  ),
  CurrencyInfo(
    code: 'NAD',
    name: 'Namibian Dollar',
    symbol: r'N$',
    keywords: ['Namibia', 'Windhoek'],
  ),
  CurrencyInfo(
    code: 'NGN',
    name: 'Nigerian Naira',
    symbol: '₦',
    keywords: ['Nigeria', 'Lagos', 'Abuja'],
  ),
  CurrencyInfo(
    code: 'NIO',
    name: 'Nicaraguan Córdoba',
    symbol: r'C$',
    keywords: ['Nicaragua', 'Managua', 'cordoba'],
  ),
  CurrencyInfo(
    code: 'NOK',
    name: 'Norwegian Krone',
    symbol: 'kr',
    keywords: ['Norway', 'Oslo'],
    autoRates: true,
  ),
  CurrencyInfo(
    code: 'NPR',
    name: 'Nepalese Rupee',
    symbol: '₨',
    keywords: ['Nepal', 'Kathmandu'],
  ),
  CurrencyInfo(
    code: 'NZD',
    name: 'New Zealand Dollar',
    symbol: r'NZ$',
    keywords: ['New Zealand', 'Auckland', 'Wellington', 'kiwi'],
    autoRates: true,
  ),
  CurrencyInfo(
    code: 'OMR',
    name: 'Omani Rial',
    symbol: 'ر.ع.',
    keywords: ['Oman', 'Muscat'],
  ),
  CurrencyInfo(
    code: 'PAB',
    name: 'Panamanian Balboa',
    symbol: 'B/.',
    keywords: ['Panama'],
  ),
  CurrencyInfo(
    code: 'PEN',
    name: 'Peruvian Sol',
    symbol: 'S/',
    keywords: ['Peru', 'Lima'],
  ),
  CurrencyInfo(
    code: 'PGK',
    name: 'Papua New Guinean Kina',
    symbol: 'K',
    keywords: ['Papua New Guinea'],
  ),
  CurrencyInfo(
    code: 'PHP',
    name: 'Philippine Peso',
    symbol: '₱',
    keywords: ['Philippines', 'Manila'],
    autoRates: true,
  ),
  CurrencyInfo(
    code: 'PKR',
    name: 'Pakistani Rupee',
    symbol: '₨',
    keywords: ['Pakistan', 'Karachi', 'Lahore', 'Islamabad'],
  ),
  CurrencyInfo(
    code: 'PLN',
    name: 'Polish Zloty',
    symbol: 'zł',
    keywords: ['Poland', 'Warsaw', 'Krakow'],
    autoRates: true,
  ),
  CurrencyInfo(
    code: 'PYG',
    name: 'Paraguayan Guaraní',
    symbol: '₲',
    keywords: ['Paraguay', 'Asuncion', 'guarani'],
  ),
  CurrencyInfo(
    code: 'QAR',
    name: 'Qatari Riyal',
    symbol: 'ر.ق',
    keywords: ['Qatar', 'Doha'],
  ),
  CurrencyInfo(
    code: 'RON',
    name: 'Romanian Leu',
    symbol: 'lei',
    keywords: ['Romania', 'Bucharest'],
    autoRates: true,
  ),
  CurrencyInfo(
    code: 'RSD',
    name: 'Serbian Dinar',
    symbol: 'дин.',
    keywords: ['Serbia', 'Belgrade'],
  ),
  CurrencyInfo(
    code: 'RUB',
    name: 'Russian Ruble',
    symbol: '₽',
    keywords: ['Russia', 'Moscow'],
  ),
  CurrencyInfo(
    code: 'RWF',
    name: 'Rwandan Franc',
    symbol: 'FRw',
    keywords: ['Rwanda', 'Kigali'],
  ),
  CurrencyInfo(
    code: 'SAR',
    name: 'Saudi Riyal',
    symbol: '﷼',
    keywords: ['Saudi Arabia', 'Riyadh', 'Jeddah'],
  ),
  CurrencyInfo(
    code: 'SBD',
    name: 'Solomon Islands Dollar',
    symbol: r'SI$',
    keywords: ['Solomon Islands'],
  ),
  CurrencyInfo(
    code: 'SCR',
    name: 'Seychellois Rupee',
    symbol: '₨',
    keywords: ['Seychelles'],
  ),
  CurrencyInfo(
    code: 'SDG',
    name: 'Sudanese Pound',
    symbol: 'ج.س.',
    keywords: ['Sudan', 'Khartoum'],
  ),
  CurrencyInfo(
    code: 'SEK',
    name: 'Swedish Krona',
    symbol: 'kr',
    keywords: ['Sweden', 'Stockholm'],
    autoRates: true,
  ),
  CurrencyInfo(
    code: 'SGD',
    name: 'Singapore Dollar',
    symbol: r'S$',
    keywords: ['Singapore'],
    autoRates: true,
  ),
  CurrencyInfo(
    code: 'SHP',
    name: 'Saint Helena Pound',
    symbol: '£',
    keywords: ['Saint Helena'],
  ),
  CurrencyInfo(
    code: 'SLE',
    name: 'Sierra Leonean Leone',
    symbol: 'Le',
    keywords: ['Sierra Leone'],
  ),
  CurrencyInfo(
    code: 'SOS',
    name: 'Somali Shilling',
    symbol: 'Sh',
    keywords: ['Somalia', 'Mogadishu'],
  ),
  CurrencyInfo(
    code: 'SRD',
    name: 'Surinamese Dollar',
    symbol: r'$',
    keywords: ['Suriname'],
  ),
  CurrencyInfo(
    code: 'SSP',
    name: 'South Sudanese Pound',
    symbol: '£',
    keywords: ['South Sudan'],
  ),
  CurrencyInfo(
    code: 'STN',
    name: 'São Tomé and Príncipe Dobra',
    symbol: 'Db',
    keywords: ['Sao Tome', 'Principe'],
  ),
  CurrencyInfo(
    code: 'SYP',
    name: 'Syrian Pound',
    symbol: '£',
    keywords: ['Syria', 'Damascus'],
  ),
  CurrencyInfo(
    code: 'SZL',
    name: 'Swazi Lilangeni',
    symbol: 'E',
    keywords: ['Eswatini', 'Swaziland'],
  ),
  CurrencyInfo(
    code: 'THB',
    name: 'Thai Baht',
    symbol: '฿',
    keywords: ['Thailand', 'Bangkok'],
    autoRates: true,
  ),
  CurrencyInfo(
    code: 'TJS',
    name: 'Tajikistani Somoni',
    symbol: 'ЅМ',
    keywords: ['Tajikistan', 'Dushanbe'],
  ),
  CurrencyInfo(
    code: 'TMT',
    name: 'Turkmenistani Manat',
    symbol: 'm',
    keywords: ['Turkmenistan', 'Ashgabat'],
  ),
  CurrencyInfo(
    code: 'TND',
    name: 'Tunisian Dinar',
    symbol: 'د.ت',
    keywords: ['Tunisia', 'Tunis'],
  ),
  CurrencyInfo(
    code: 'TOP',
    name: 'Tongan Paʻanga',
    symbol: r'T$',
    keywords: ['Tonga', 'paanga'],
  ),
  CurrencyInfo(
    code: 'TRY',
    name: 'Turkish Lira',
    symbol: '₺',
    keywords: ['Turkey', 'Turkiye', 'Istanbul', 'Ankara'],
    autoRates: true,
  ),
  CurrencyInfo(
    code: 'TTD',
    name: 'Trinidad and Tobago Dollar',
    symbol: r'TT$',
    keywords: ['Trinidad', 'Tobago'],
  ),
  CurrencyInfo(
    code: 'TWD',
    name: 'New Taiwan Dollar',
    symbol: r'NT$',
    keywords: ['Taiwan', 'Taipei'],
  ),
  CurrencyInfo(
    code: 'TZS',
    name: 'Tanzanian Shilling',
    symbol: 'TSh',
    keywords: ['Tanzania', 'Dar es Salaam'],
  ),
  CurrencyInfo(
    code: 'UAH',
    name: 'Ukrainian Hryvnia',
    symbol: '₴',
    keywords: ['Ukraine', 'Kyiv'],
  ),
  CurrencyInfo(
    code: 'UGX',
    name: 'Ugandan Shilling',
    symbol: 'USh',
    keywords: ['Uganda', 'Kampala'],
  ),
  CurrencyInfo(
    code: 'USD',
    name: 'US Dollar',
    symbol: r'$',
    keywords: ['United States', 'USA', 'America', 'New York'],
    autoRates: true,
  ),
  CurrencyInfo(
    code: 'UYU',
    name: 'Uruguayan Peso',
    symbol: r'$U',
    keywords: ['Uruguay', 'Montevideo'],
  ),
  CurrencyInfo(
    code: 'UZS',
    name: 'Uzbekistani Som',
    symbol: 'soʻm',
    keywords: ['Uzbekistan', 'Tashkent'],
  ),
  CurrencyInfo(
    code: 'VES',
    name: 'Venezuelan Bolívar',
    symbol: 'Bs.S',
    keywords: ['Venezuela', 'Caracas', 'bolivar'],
  ),
  CurrencyInfo(
    code: 'VND',
    name: 'Vietnamese Dong',
    symbol: '₫',
    keywords: ['Vietnam', 'Hanoi', 'Ho Chi Minh'],
  ),
  CurrencyInfo(
    code: 'VUV',
    name: 'Vanuatu Vatu',
    symbol: 'VT',
    keywords: ['Vanuatu'],
  ),
  CurrencyInfo(
    code: 'WST',
    name: 'Samoan Tala',
    symbol: r'WS$',
    keywords: ['Samoa'],
  ),
  CurrencyInfo(
    code: 'XAF',
    name: 'Central African CFA Franc',
    symbol: 'FCFA',
    keywords: ['Cameroon', 'Gabon', 'Chad', 'Central Africa', 'CFA'],
  ),
  CurrencyInfo(
    code: 'XCD',
    name: 'East Caribbean Dollar',
    symbol: r'EC$',
    keywords: [
      'East Caribbean',
      'Antigua',
      'Dominica',
      'Grenada',
      'Saint Lucia',
    ],
  ),
  CurrencyInfo(
    code: 'XOF',
    name: 'West African CFA Franc',
    symbol: 'CFA',
    keywords: [
      'Senegal',
      'Ivory Coast',
      'Cote dIvoire',
      'Mali',
      'Burkina Faso',
      'Togo',
      'Benin',
      'Niger',
      'West Africa',
    ],
  ),
  CurrencyInfo(
    code: 'XPF',
    name: 'CFP Franc',
    symbol: '₣',
    keywords: ['French Polynesia', 'Tahiti', 'New Caledonia'],
  ),
  CurrencyInfo(
    code: 'YER',
    name: 'Yemeni Rial',
    symbol: '﷼',
    keywords: ['Yemen', 'Sanaa'],
  ),
  CurrencyInfo(
    code: 'ZAR',
    name: 'South African Rand',
    symbol: 'R',
    keywords: ['South Africa', 'Johannesburg', 'Cape Town'],
    autoRates: true,
  ),
  CurrencyInfo(
    code: 'ZMW',
    name: 'Zambian Kwacha',
    symbol: 'ZK',
    keywords: ['Zambia', 'Lusaka'],
  ),
  CurrencyInfo(
    code: 'ZWG',
    name: 'Zimbabwe Gold',
    symbol: 'ZiG',
    keywords: ['Zimbabwe', 'Harare', 'zig'],
  ),
];

final Map<String, CurrencyInfo> _byCode = {
  for (final c in allCurrencies) c.code: c,
};

/// Looks up [code] (case-insensitive), returning a safe fallback when unknown.
CurrencyInfo currencyInfo(String code) {
  final upper = code.trim().toUpperCase();
  return _byCode[upper] ??
      CurrencyInfo(code: upper, name: upper, symbol: upper);
}

/// Short display label such as `BDT · Bangladeshi Taka`.
String currencyLabel(String code) {
  final info = currencyInfo(code);
  return info.name == info.code ? info.code : '${info.code} · ${info.name}';
}

/// Searches [pool] by ISO code, full name, symbol, or country/alias keywords.
///
/// Matches are ordered by relevance:
/// 0. Exact ISO code
/// 1. ISO code prefix
/// 2. Exact symbol
/// 3. Word prefix in name or keyword
/// 4. Substring anywhere else
/// Ties break with [CurrencyInfo.autoRates] first, then alphabetically by code.
List<CurrencyInfo> searchCurrencies(
  String query, {
  Iterable<CurrencyInfo> pool = allCurrencies,
}) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return pool.toList();

  final scored = <(int, CurrencyInfo)>[];
  for (final c in pool) {
    final rank = _matchRank(c, q);
    if (rank != null) scored.add((rank, c));
  }
  scored.sort((a, b) {
    final byRank = a.$1.compareTo(b.$1);
    if (byRank != 0) return byRank;
    if (a.$2.autoRates != b.$2.autoRates) return a.$2.autoRates ? -1 : 1;
    return a.$2.code.compareTo(b.$2.code);
  });
  return [for (final item in scored) item.$2];
}

int? _matchRank(CurrencyInfo c, String q) {
  final code = c.code.toLowerCase();
  if (code == q) return 0;
  if (code.startsWith(q)) return 1;

  final sym = c.symbol.toLowerCase();
  if (sym == q) return 2;

  final name = c.name.toLowerCase();
  final nameWords = name.split(RegExp(r'[\s\-]+'));
  if (nameWords.any((w) => w.startsWith(q))) return 3;

  for (final k in c.keywords) {
    final kl = k.toLowerCase();
    if (kl.split(RegExp(r'[\s\-]+')).any((w) => w.startsWith(q))) return 3;
  }

  if (name.contains(q) ||
      sym.contains(q) ||
      code.contains(q) ||
      c.keywords.any((k) => k.toLowerCase().contains(q))) {
    return 4;
  }
  return null;
}

/// Ordered, deduplicated currency codes to pin at the top of the picker.
List<String> suggestedCurrencyCodes({
  required String selected,
  String? detectedCode,
  Iterable<String> accountCodes = const [],
  List<String> fallbacks = const ['USD', 'EUR', 'GBP'],
}) {
  final out = <String>[];
  final seen = <String>{};
  void add(String? raw) {
    if (raw == null) return;
    final code = raw.trim().toUpperCase();
    if (code.length != 3 || !seen.add(code)) return;
    out.add(code);
  }

  add(selected);
  add(detectedCode);
  for (final c in accountCodes) {
    add(c);
  }
  for (final c in fallbacks) {
    add(c);
  }
  return out;
}
