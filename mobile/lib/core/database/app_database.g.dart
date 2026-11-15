// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $LocalMetaTable extends LocalMeta
    with TableInfo<$LocalMetaTable, LocalMetaData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalMetaTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_meta';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalMetaData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  LocalMetaData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalMetaData(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
    );
  }

  @override
  $LocalMetaTable createAlias(String alias) {
    return $LocalMetaTable(attachedDatabase, alias);
  }
}

class LocalMetaData extends DataClass implements Insertable<LocalMetaData> {
  final String key;
  final String value;
  const LocalMetaData({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  LocalMetaCompanion toCompanion(bool nullToAbsent) {
    return LocalMetaCompanion(key: Value(key), value: Value(value));
  }

  factory LocalMetaData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalMetaData(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
    };
  }

  LocalMetaData copyWith({String? key, String? value}) =>
      LocalMetaData(key: key ?? this.key, value: value ?? this.value);
  LocalMetaData copyWithCompanion(LocalMetaCompanion data) {
    return LocalMetaData(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalMetaData(')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalMetaData &&
          other.key == this.key &&
          other.value == this.value);
}

class LocalMetaCompanion extends UpdateCompanion<LocalMetaData> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const LocalMetaCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalMetaCompanion.insert({
    required String key,
    required String value,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value);
  static Insertable<LocalMetaData> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalMetaCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<int>? rowid,
  }) {
    return LocalMetaCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalMetaCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AccountsTable extends Accounts with TableInfo<$AccountsTable, Account> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AccountsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _serverVersionMeta = const VerificationMeta(
    'serverVersion',
  );
  @override
  late final GeneratedColumn<int> serverVersion = GeneratedColumn<int>(
    'server_version',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 60,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _currencyMeta = const VerificationMeta(
    'currency',
  );
  @override
  late final GeneratedColumn<String> currency = GeneratedColumn<String>(
    'currency',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 3,
      maxTextLength: 3,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _openingBalanceMinorMeta =
      const VerificationMeta('openingBalanceMinor');
  @override
  late final GeneratedColumn<int> openingBalanceMinor = GeneratedColumn<int>(
    'opening_balance_minor',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _iconMeta = const VerificationMeta('icon');
  @override
  late final GeneratedColumn<String> icon = GeneratedColumn<String>(
    'icon',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _colorMeta = const VerificationMeta('color');
  @override
  late final GeneratedColumn<String> color = GeneratedColumn<String>(
    'color',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _archivedMeta = const VerificationMeta(
    'archived',
  );
  @override
  late final GeneratedColumn<bool> archived = GeneratedColumn<bool>(
    'archived',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("archived" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _sortOrderMeta = const VerificationMeta(
    'sortOrder',
  );
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    updatedAt,
    deletedAt,
    serverVersion,
    name,
    type,
    currency,
    openingBalanceMinor,
    icon,
    color,
    archived,
    sortOrder,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'accounts';
  @override
  VerificationContext validateIntegrity(
    Insertable<Account> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('server_version')) {
      context.handle(
        _serverVersionMeta,
        serverVersion.isAcceptableOrUnknown(
          data['server_version']!,
          _serverVersionMeta,
        ),
      );
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('currency')) {
      context.handle(
        _currencyMeta,
        currency.isAcceptableOrUnknown(data['currency']!, _currencyMeta),
      );
    } else if (isInserting) {
      context.missing(_currencyMeta);
    }
    if (data.containsKey('opening_balance_minor')) {
      context.handle(
        _openingBalanceMinorMeta,
        openingBalanceMinor.isAcceptableOrUnknown(
          data['opening_balance_minor']!,
          _openingBalanceMinorMeta,
        ),
      );
    }
    if (data.containsKey('icon')) {
      context.handle(
        _iconMeta,
        icon.isAcceptableOrUnknown(data['icon']!, _iconMeta),
      );
    }
    if (data.containsKey('color')) {
      context.handle(
        _colorMeta,
        color.isAcceptableOrUnknown(data['color']!, _colorMeta),
      );
    }
    if (data.containsKey('archived')) {
      context.handle(
        _archivedMeta,
        archived.isAcceptableOrUnknown(data['archived']!, _archivedMeta),
      );
    }
    if (data.containsKey('sort_order')) {
      context.handle(
        _sortOrderMeta,
        sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Account map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Account(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
      serverVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}server_version'],
      ),
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}type'],
      )!,
      currency: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}currency'],
      )!,
      openingBalanceMinor: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}opening_balance_minor'],
      )!,
      icon: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}icon'],
      )!,
      color: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}color'],
      )!,
      archived: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}archived'],
      )!,
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      )!,
    );
  }

  @override
  $AccountsTable createAlias(String alias) {
    return $AccountsTable(attachedDatabase, alias);
  }
}

class Account extends DataClass implements Insertable<Account> {
  /// Client-generated UUID v7.
  final String id;

  /// When this row was last edited (on any device). The newer edit wins.
  final DateTime updatedAt;

  /// Soft delete: the row stays so the deletion can sync.
  final DateTime? deletedAt;

  /// The server's version of this row; null until it reached the server.
  final int? serverVersion;
  final String name;

  /// cash, bank, card, ewallet, savings, other
  final String type;
  final String currency;
  final int openingBalanceMinor;
  final String icon;
  final String color;
  final bool archived;
  final int sortOrder;
  const Account({
    required this.id,
    required this.updatedAt,
    this.deletedAt,
    this.serverVersion,
    required this.name,
    required this.type,
    required this.currency,
    required this.openingBalanceMinor,
    required this.icon,
    required this.color,
    required this.archived,
    required this.sortOrder,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    if (!nullToAbsent || serverVersion != null) {
      map['server_version'] = Variable<int>(serverVersion);
    }
    map['name'] = Variable<String>(name);
    map['type'] = Variable<String>(type);
    map['currency'] = Variable<String>(currency);
    map['opening_balance_minor'] = Variable<int>(openingBalanceMinor);
    map['icon'] = Variable<String>(icon);
    map['color'] = Variable<String>(color);
    map['archived'] = Variable<bool>(archived);
    map['sort_order'] = Variable<int>(sortOrder);
    return map;
  }

  AccountsCompanion toCompanion(bool nullToAbsent) {
    return AccountsCompanion(
      id: Value(id),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      serverVersion: serverVersion == null && nullToAbsent
          ? const Value.absent()
          : Value(serverVersion),
      name: Value(name),
      type: Value(type),
      currency: Value(currency),
      openingBalanceMinor: Value(openingBalanceMinor),
      icon: Value(icon),
      color: Value(color),
      archived: Value(archived),
      sortOrder: Value(sortOrder),
    );
  }

  factory Account.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Account(
      id: serializer.fromJson<String>(json['id']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
      serverVersion: serializer.fromJson<int?>(json['serverVersion']),
      name: serializer.fromJson<String>(json['name']),
      type: serializer.fromJson<String>(json['type']),
      currency: serializer.fromJson<String>(json['currency']),
      openingBalanceMinor: serializer.fromJson<int>(
        json['openingBalanceMinor'],
      ),
      icon: serializer.fromJson<String>(json['icon']),
      color: serializer.fromJson<String>(json['color']),
      archived: serializer.fromJson<bool>(json['archived']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
      'serverVersion': serializer.toJson<int?>(serverVersion),
      'name': serializer.toJson<String>(name),
      'type': serializer.toJson<String>(type),
      'currency': serializer.toJson<String>(currency),
      'openingBalanceMinor': serializer.toJson<int>(openingBalanceMinor),
      'icon': serializer.toJson<String>(icon),
      'color': serializer.toJson<String>(color),
      'archived': serializer.toJson<bool>(archived),
      'sortOrder': serializer.toJson<int>(sortOrder),
    };
  }

  Account copyWith({
    String? id,
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
    Value<int?> serverVersion = const Value.absent(),
    String? name,
    String? type,
    String? currency,
    int? openingBalanceMinor,
    String? icon,
    String? color,
    bool? archived,
    int? sortOrder,
  }) => Account(
    id: id ?? this.id,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    serverVersion: serverVersion.present
        ? serverVersion.value
        : this.serverVersion,
    name: name ?? this.name,
    type: type ?? this.type,
    currency: currency ?? this.currency,
    openingBalanceMinor: openingBalanceMinor ?? this.openingBalanceMinor,
    icon: icon ?? this.icon,
    color: color ?? this.color,
    archived: archived ?? this.archived,
    sortOrder: sortOrder ?? this.sortOrder,
  );
  Account copyWithCompanion(AccountsCompanion data) {
    return Account(
      id: data.id.present ? data.id.value : this.id,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      serverVersion: data.serverVersion.present
          ? data.serverVersion.value
          : this.serverVersion,
      name: data.name.present ? data.name.value : this.name,
      type: data.type.present ? data.type.value : this.type,
      currency: data.currency.present ? data.currency.value : this.currency,
      openingBalanceMinor: data.openingBalanceMinor.present
          ? data.openingBalanceMinor.value
          : this.openingBalanceMinor,
      icon: data.icon.present ? data.icon.value : this.icon,
      color: data.color.present ? data.color.value : this.color,
      archived: data.archived.present ? data.archived.value : this.archived,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Account(')
          ..write('id: $id, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('serverVersion: $serverVersion, ')
          ..write('name: $name, ')
          ..write('type: $type, ')
          ..write('currency: $currency, ')
          ..write('openingBalanceMinor: $openingBalanceMinor, ')
          ..write('icon: $icon, ')
          ..write('color: $color, ')
          ..write('archived: $archived, ')
          ..write('sortOrder: $sortOrder')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    updatedAt,
    deletedAt,
    serverVersion,
    name,
    type,
    currency,
    openingBalanceMinor,
    icon,
    color,
    archived,
    sortOrder,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Account &&
          other.id == this.id &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.serverVersion == this.serverVersion &&
          other.name == this.name &&
          other.type == this.type &&
          other.currency == this.currency &&
          other.openingBalanceMinor == this.openingBalanceMinor &&
          other.icon == this.icon &&
          other.color == this.color &&
          other.archived == this.archived &&
          other.sortOrder == this.sortOrder);
}

class AccountsCompanion extends UpdateCompanion<Account> {
  final Value<String> id;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<int?> serverVersion;
  final Value<String> name;
  final Value<String> type;
  final Value<String> currency;
  final Value<int> openingBalanceMinor;
  final Value<String> icon;
  final Value<String> color;
  final Value<bool> archived;
  final Value<int> sortOrder;
  final Value<int> rowid;
  const AccountsCompanion({
    this.id = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.serverVersion = const Value.absent(),
    this.name = const Value.absent(),
    this.type = const Value.absent(),
    this.currency = const Value.absent(),
    this.openingBalanceMinor = const Value.absent(),
    this.icon = const Value.absent(),
    this.color = const Value.absent(),
    this.archived = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AccountsCompanion.insert({
    required String id,
    required DateTime updatedAt,
    this.deletedAt = const Value.absent(),
    this.serverVersion = const Value.absent(),
    required String name,
    required String type,
    required String currency,
    this.openingBalanceMinor = const Value.absent(),
    this.icon = const Value.absent(),
    this.color = const Value.absent(),
    this.archived = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       updatedAt = Value(updatedAt),
       name = Value(name),
       type = Value(type),
       currency = Value(currency);
  static Insertable<Account> custom({
    Expression<String>? id,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<int>? serverVersion,
    Expression<String>? name,
    Expression<String>? type,
    Expression<String>? currency,
    Expression<int>? openingBalanceMinor,
    Expression<String>? icon,
    Expression<String>? color,
    Expression<bool>? archived,
    Expression<int>? sortOrder,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (serverVersion != null) 'server_version': serverVersion,
      if (name != null) 'name': name,
      if (type != null) 'type': type,
      if (currency != null) 'currency': currency,
      if (openingBalanceMinor != null)
        'opening_balance_minor': openingBalanceMinor,
      if (icon != null) 'icon': icon,
      if (color != null) 'color': color,
      if (archived != null) 'archived': archived,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AccountsCompanion copyWith({
    Value<String>? id,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<int?>? serverVersion,
    Value<String>? name,
    Value<String>? type,
    Value<String>? currency,
    Value<int>? openingBalanceMinor,
    Value<String>? icon,
    Value<String>? color,
    Value<bool>? archived,
    Value<int>? sortOrder,
    Value<int>? rowid,
  }) {
    return AccountsCompanion(
      id: id ?? this.id,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      serverVersion: serverVersion ?? this.serverVersion,
      name: name ?? this.name,
      type: type ?? this.type,
      currency: currency ?? this.currency,
      openingBalanceMinor: openingBalanceMinor ?? this.openingBalanceMinor,
      icon: icon ?? this.icon,
      color: color ?? this.color,
      archived: archived ?? this.archived,
      sortOrder: sortOrder ?? this.sortOrder,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (serverVersion.present) {
      map['server_version'] = Variable<int>(serverVersion.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (currency.present) {
      map['currency'] = Variable<String>(currency.value);
    }
    if (openingBalanceMinor.present) {
      map['opening_balance_minor'] = Variable<int>(openingBalanceMinor.value);
    }
    if (icon.present) {
      map['icon'] = Variable<String>(icon.value);
    }
    if (color.present) {
      map['color'] = Variable<String>(color.value);
    }
    if (archived.present) {
      map['archived'] = Variable<bool>(archived.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AccountsCompanion(')
          ..write('id: $id, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('serverVersion: $serverVersion, ')
          ..write('name: $name, ')
          ..write('type: $type, ')
          ..write('currency: $currency, ')
          ..write('openingBalanceMinor: $openingBalanceMinor, ')
          ..write('icon: $icon, ')
          ..write('color: $color, ')
          ..write('archived: $archived, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CategoriesTable extends Categories
    with TableInfo<$CategoriesTable, Category> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CategoriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _serverVersionMeta = const VerificationMeta(
    'serverVersion',
  );
  @override
  late final GeneratedColumn<int> serverVersion = GeneratedColumn<int>(
    'server_version',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _parentIdMeta = const VerificationMeta(
    'parentId',
  );
  @override
  late final GeneratedColumn<String> parentId = GeneratedColumn<String>(
    'parent_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 40,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _iconMeta = const VerificationMeta('icon');
  @override
  late final GeneratedColumn<String> icon = GeneratedColumn<String>(
    'icon',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _colorMeta = const VerificationMeta('color');
  @override
  late final GeneratedColumn<String> color = GeneratedColumn<String>(
    'color',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _sortOrderMeta = const VerificationMeta(
    'sortOrder',
  );
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    updatedAt,
    deletedAt,
    serverVersion,
    parentId,
    name,
    kind,
    icon,
    color,
    sortOrder,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'categories';
  @override
  VerificationContext validateIntegrity(
    Insertable<Category> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('server_version')) {
      context.handle(
        _serverVersionMeta,
        serverVersion.isAcceptableOrUnknown(
          data['server_version']!,
          _serverVersionMeta,
        ),
      );
    }
    if (data.containsKey('parent_id')) {
      context.handle(
        _parentIdMeta,
        parentId.isAcceptableOrUnknown(data['parent_id']!, _parentIdMeta),
      );
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('icon')) {
      context.handle(
        _iconMeta,
        icon.isAcceptableOrUnknown(data['icon']!, _iconMeta),
      );
    }
    if (data.containsKey('color')) {
      context.handle(
        _colorMeta,
        color.isAcceptableOrUnknown(data['color']!, _colorMeta),
      );
    }
    if (data.containsKey('sort_order')) {
      context.handle(
        _sortOrderMeta,
        sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Category map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Category(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
      serverVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}server_version'],
      ),
      parentId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}parent_id'],
      ),
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      icon: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}icon'],
      )!,
      color: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}color'],
      )!,
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      )!,
    );
  }

  @override
  $CategoriesTable createAlias(String alias) {
    return $CategoriesTable(attachedDatabase, alias);
  }
}

class Category extends DataClass implements Insertable<Category> {
  /// Client-generated UUID v7.
  final String id;

  /// When this row was last edited (on any device). The newer edit wins.
  final DateTime updatedAt;

  /// Soft delete: the row stays so the deletion can sync.
  final DateTime? deletedAt;

  /// The server's version of this row; null until it reached the server.
  final int? serverVersion;
  final String? parentId;
  final String name;

  /// income or expense
  final String kind;
  final String icon;
  final String color;
  final int sortOrder;
  const Category({
    required this.id,
    required this.updatedAt,
    this.deletedAt,
    this.serverVersion,
    this.parentId,
    required this.name,
    required this.kind,
    required this.icon,
    required this.color,
    required this.sortOrder,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    if (!nullToAbsent || serverVersion != null) {
      map['server_version'] = Variable<int>(serverVersion);
    }
    if (!nullToAbsent || parentId != null) {
      map['parent_id'] = Variable<String>(parentId);
    }
    map['name'] = Variable<String>(name);
    map['kind'] = Variable<String>(kind);
    map['icon'] = Variable<String>(icon);
    map['color'] = Variable<String>(color);
    map['sort_order'] = Variable<int>(sortOrder);
    return map;
  }

  CategoriesCompanion toCompanion(bool nullToAbsent) {
    return CategoriesCompanion(
      id: Value(id),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      serverVersion: serverVersion == null && nullToAbsent
          ? const Value.absent()
          : Value(serverVersion),
      parentId: parentId == null && nullToAbsent
          ? const Value.absent()
          : Value(parentId),
      name: Value(name),
      kind: Value(kind),
      icon: Value(icon),
      color: Value(color),
      sortOrder: Value(sortOrder),
    );
  }

  factory Category.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Category(
      id: serializer.fromJson<String>(json['id']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
      serverVersion: serializer.fromJson<int?>(json['serverVersion']),
      parentId: serializer.fromJson<String?>(json['parentId']),
      name: serializer.fromJson<String>(json['name']),
      kind: serializer.fromJson<String>(json['kind']),
      icon: serializer.fromJson<String>(json['icon']),
      color: serializer.fromJson<String>(json['color']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
      'serverVersion': serializer.toJson<int?>(serverVersion),
      'parentId': serializer.toJson<String?>(parentId),
      'name': serializer.toJson<String>(name),
      'kind': serializer.toJson<String>(kind),
      'icon': serializer.toJson<String>(icon),
      'color': serializer.toJson<String>(color),
      'sortOrder': serializer.toJson<int>(sortOrder),
    };
  }

  Category copyWith({
    String? id,
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
    Value<int?> serverVersion = const Value.absent(),
    Value<String?> parentId = const Value.absent(),
    String? name,
    String? kind,
    String? icon,
    String? color,
    int? sortOrder,
  }) => Category(
    id: id ?? this.id,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    serverVersion: serverVersion.present
        ? serverVersion.value
        : this.serverVersion,
    parentId: parentId.present ? parentId.value : this.parentId,
    name: name ?? this.name,
    kind: kind ?? this.kind,
    icon: icon ?? this.icon,
    color: color ?? this.color,
    sortOrder: sortOrder ?? this.sortOrder,
  );
  Category copyWithCompanion(CategoriesCompanion data) {
    return Category(
      id: data.id.present ? data.id.value : this.id,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      serverVersion: data.serverVersion.present
          ? data.serverVersion.value
          : this.serverVersion,
      parentId: data.parentId.present ? data.parentId.value : this.parentId,
      name: data.name.present ? data.name.value : this.name,
      kind: data.kind.present ? data.kind.value : this.kind,
      icon: data.icon.present ? data.icon.value : this.icon,
      color: data.color.present ? data.color.value : this.color,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Category(')
          ..write('id: $id, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('serverVersion: $serverVersion, ')
          ..write('parentId: $parentId, ')
          ..write('name: $name, ')
          ..write('kind: $kind, ')
          ..write('icon: $icon, ')
          ..write('color: $color, ')
          ..write('sortOrder: $sortOrder')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    updatedAt,
    deletedAt,
    serverVersion,
    parentId,
    name,
    kind,
    icon,
    color,
    sortOrder,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Category &&
          other.id == this.id &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.serverVersion == this.serverVersion &&
          other.parentId == this.parentId &&
          other.name == this.name &&
          other.kind == this.kind &&
          other.icon == this.icon &&
          other.color == this.color &&
          other.sortOrder == this.sortOrder);
}

class CategoriesCompanion extends UpdateCompanion<Category> {
  final Value<String> id;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<int?> serverVersion;
  final Value<String?> parentId;
  final Value<String> name;
  final Value<String> kind;
  final Value<String> icon;
  final Value<String> color;
  final Value<int> sortOrder;
  final Value<int> rowid;
  const CategoriesCompanion({
    this.id = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.serverVersion = const Value.absent(),
    this.parentId = const Value.absent(),
    this.name = const Value.absent(),
    this.kind = const Value.absent(),
    this.icon = const Value.absent(),
    this.color = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CategoriesCompanion.insert({
    required String id,
    required DateTime updatedAt,
    this.deletedAt = const Value.absent(),
    this.serverVersion = const Value.absent(),
    this.parentId = const Value.absent(),
    required String name,
    required String kind,
    this.icon = const Value.absent(),
    this.color = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       updatedAt = Value(updatedAt),
       name = Value(name),
       kind = Value(kind);
  static Insertable<Category> custom({
    Expression<String>? id,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<int>? serverVersion,
    Expression<String>? parentId,
    Expression<String>? name,
    Expression<String>? kind,
    Expression<String>? icon,
    Expression<String>? color,
    Expression<int>? sortOrder,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (serverVersion != null) 'server_version': serverVersion,
      if (parentId != null) 'parent_id': parentId,
      if (name != null) 'name': name,
      if (kind != null) 'kind': kind,
      if (icon != null) 'icon': icon,
      if (color != null) 'color': color,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CategoriesCompanion copyWith({
    Value<String>? id,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<int?>? serverVersion,
    Value<String?>? parentId,
    Value<String>? name,
    Value<String>? kind,
    Value<String>? icon,
    Value<String>? color,
    Value<int>? sortOrder,
    Value<int>? rowid,
  }) {
    return CategoriesCompanion(
      id: id ?? this.id,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      serverVersion: serverVersion ?? this.serverVersion,
      parentId: parentId ?? this.parentId,
      name: name ?? this.name,
      kind: kind ?? this.kind,
      icon: icon ?? this.icon,
      color: color ?? this.color,
      sortOrder: sortOrder ?? this.sortOrder,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (serverVersion.present) {
      map['server_version'] = Variable<int>(serverVersion.value);
    }
    if (parentId.present) {
      map['parent_id'] = Variable<String>(parentId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (icon.present) {
      map['icon'] = Variable<String>(icon.value);
    }
    if (color.present) {
      map['color'] = Variable<String>(color.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CategoriesCompanion(')
          ..write('id: $id, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('serverVersion: $serverVersion, ')
          ..write('parentId: $parentId, ')
          ..write('name: $name, ')
          ..write('kind: $kind, ')
          ..write('icon: $icon, ')
          ..write('color: $color, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TransactionsTable extends Transactions
    with TableInfo<$TransactionsTable, MoneyTransaction> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TransactionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _serverVersionMeta = const VerificationMeta(
    'serverVersion',
  );
  @override
  late final GeneratedColumn<int> serverVersion = GeneratedColumn<int>(
    'server_version',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _accountIdMeta = const VerificationMeta(
    'accountId',
  );
  @override
  late final GeneratedColumn<String> accountId = GeneratedColumn<String>(
    'account_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _categoryIdMeta = const VerificationMeta(
    'categoryId',
  );
  @override
  late final GeneratedColumn<String> categoryId = GeneratedColumn<String>(
    'category_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _amountMinorMeta = const VerificationMeta(
    'amountMinor',
  );
  @override
  late final GeneratedColumn<int> amountMinor = GeneratedColumn<int>(
    'amount_minor',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _currencyMeta = const VerificationMeta(
    'currency',
  );
  @override
  late final GeneratedColumn<String> currency = GeneratedColumn<String>(
    'currency',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 3,
      maxTextLength: 3,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _amountBaseMinorMeta = const VerificationMeta(
    'amountBaseMinor',
  );
  @override
  late final GeneratedColumn<int> amountBaseMinor = GeneratedColumn<int>(
    'amount_base_minor',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _fxRateToBaseMeta = const VerificationMeta(
    'fxRateToBase',
  );
  @override
  late final GeneratedColumn<String> fxRateToBase = GeneratedColumn<String>(
    'fx_rate_to_base',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _transferAccountIdMeta = const VerificationMeta(
    'transferAccountId',
  );
  @override
  late final GeneratedColumn<String> transferAccountId =
      GeneratedColumn<String>(
        'transfer_account_id',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _transferAmountMinorMeta =
      const VerificationMeta('transferAmountMinor');
  @override
  late final GeneratedColumn<int> transferAmountMinor = GeneratedColumn<int>(
    'transfer_amount_minor',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _occurredAtMeta = const VerificationMeta(
    'occurredAt',
  );
  @override
  late final GeneratedColumn<DateTime> occurredAt = GeneratedColumn<DateTime>(
    'occurred_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _localDateMeta = const VerificationMeta(
    'localDate',
  );
  @override
  late final GeneratedColumn<String> localDate = GeneratedColumn<String>(
    'local_date',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 10,
      maxTextLength: 10,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  @override
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
    'note',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    updatedAt,
    deletedAt,
    serverVersion,
    accountId,
    categoryId,
    kind,
    amountMinor,
    currency,
    amountBaseMinor,
    fxRateToBase,
    transferAccountId,
    transferAmountMinor,
    occurredAt,
    localDate,
    note,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'transactions';
  @override
  VerificationContext validateIntegrity(
    Insertable<MoneyTransaction> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('server_version')) {
      context.handle(
        _serverVersionMeta,
        serverVersion.isAcceptableOrUnknown(
          data['server_version']!,
          _serverVersionMeta,
        ),
      );
    }
    if (data.containsKey('account_id')) {
      context.handle(
        _accountIdMeta,
        accountId.isAcceptableOrUnknown(data['account_id']!, _accountIdMeta),
      );
    } else if (isInserting) {
      context.missing(_accountIdMeta);
    }
    if (data.containsKey('category_id')) {
      context.handle(
        _categoryIdMeta,
        categoryId.isAcceptableOrUnknown(data['category_id']!, _categoryIdMeta),
      );
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('amount_minor')) {
      context.handle(
        _amountMinorMeta,
        amountMinor.isAcceptableOrUnknown(
          data['amount_minor']!,
          _amountMinorMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_amountMinorMeta);
    }
    if (data.containsKey('currency')) {
      context.handle(
        _currencyMeta,
        currency.isAcceptableOrUnknown(data['currency']!, _currencyMeta),
      );
    } else if (isInserting) {
      context.missing(_currencyMeta);
    }
    if (data.containsKey('amount_base_minor')) {
      context.handle(
        _amountBaseMinorMeta,
        amountBaseMinor.isAcceptableOrUnknown(
          data['amount_base_minor']!,
          _amountBaseMinorMeta,
        ),
      );
    }
    if (data.containsKey('fx_rate_to_base')) {
      context.handle(
        _fxRateToBaseMeta,
        fxRateToBase.isAcceptableOrUnknown(
          data['fx_rate_to_base']!,
          _fxRateToBaseMeta,
        ),
      );
    }
    if (data.containsKey('transfer_account_id')) {
      context.handle(
        _transferAccountIdMeta,
        transferAccountId.isAcceptableOrUnknown(
          data['transfer_account_id']!,
          _transferAccountIdMeta,
        ),
      );
    }
    if (data.containsKey('transfer_amount_minor')) {
      context.handle(
        _transferAmountMinorMeta,
        transferAmountMinor.isAcceptableOrUnknown(
          data['transfer_amount_minor']!,
          _transferAmountMinorMeta,
        ),
      );
    }
    if (data.containsKey('occurred_at')) {
      context.handle(
        _occurredAtMeta,
        occurredAt.isAcceptableOrUnknown(data['occurred_at']!, _occurredAtMeta),
      );
    } else if (isInserting) {
      context.missing(_occurredAtMeta);
    }
    if (data.containsKey('local_date')) {
      context.handle(
        _localDateMeta,
        localDate.isAcceptableOrUnknown(data['local_date']!, _localDateMeta),
      );
    } else if (isInserting) {
      context.missing(_localDateMeta);
    }
    if (data.containsKey('note')) {
      context.handle(
        _noteMeta,
        note.isAcceptableOrUnknown(data['note']!, _noteMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  MoneyTransaction map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MoneyTransaction(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
      serverVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}server_version'],
      ),
      accountId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}account_id'],
      )!,
      categoryId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}category_id'],
      ),
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      amountMinor: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}amount_minor'],
      )!,
      currency: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}currency'],
      )!,
      amountBaseMinor: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}amount_base_minor'],
      ),
      fxRateToBase: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}fx_rate_to_base'],
      ),
      transferAccountId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}transfer_account_id'],
      ),
      transferAmountMinor: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}transfer_amount_minor'],
      ),
      occurredAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}occurred_at'],
      )!,
      localDate: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}local_date'],
      )!,
      note: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note'],
      )!,
    );
  }

  @override
  $TransactionsTable createAlias(String alias) {
    return $TransactionsTable(attachedDatabase, alias);
  }
}

class MoneyTransaction extends DataClass
    implements Insertable<MoneyTransaction> {
  /// Client-generated UUID v7.
  final String id;

  /// When this row was last edited (on any device). The newer edit wins.
  final DateTime updatedAt;

  /// Soft delete: the row stays so the deletion can sync.
  final DateTime? deletedAt;

  /// The server's version of this row; null until it reached the server.
  final int? serverVersion;
  final String accountId;
  final String? categoryId;

  /// income, expense or transfer
  final String kind;

  /// Always positive; the kind says in or out.
  final int amountMinor;
  final String currency;

  /// Set by the server (same currency: rate 1). Null until known.
  final int? amountBaseMinor;
  final String? fxRateToBase;
  final String? transferAccountId;
  final int? transferAmountMinor;
  final DateTime occurredAt;

  /// YYYY-MM-DD where the user was. Months and budgets use this.
  final String localDate;
  final String note;
  const MoneyTransaction({
    required this.id,
    required this.updatedAt,
    this.deletedAt,
    this.serverVersion,
    required this.accountId,
    this.categoryId,
    required this.kind,
    required this.amountMinor,
    required this.currency,
    this.amountBaseMinor,
    this.fxRateToBase,
    this.transferAccountId,
    this.transferAmountMinor,
    required this.occurredAt,
    required this.localDate,
    required this.note,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    if (!nullToAbsent || serverVersion != null) {
      map['server_version'] = Variable<int>(serverVersion);
    }
    map['account_id'] = Variable<String>(accountId);
    if (!nullToAbsent || categoryId != null) {
      map['category_id'] = Variable<String>(categoryId);
    }
    map['kind'] = Variable<String>(kind);
    map['amount_minor'] = Variable<int>(amountMinor);
    map['currency'] = Variable<String>(currency);
    if (!nullToAbsent || amountBaseMinor != null) {
      map['amount_base_minor'] = Variable<int>(amountBaseMinor);
    }
    if (!nullToAbsent || fxRateToBase != null) {
      map['fx_rate_to_base'] = Variable<String>(fxRateToBase);
    }
    if (!nullToAbsent || transferAccountId != null) {
      map['transfer_account_id'] = Variable<String>(transferAccountId);
    }
    if (!nullToAbsent || transferAmountMinor != null) {
      map['transfer_amount_minor'] = Variable<int>(transferAmountMinor);
    }
    map['occurred_at'] = Variable<DateTime>(occurredAt);
    map['local_date'] = Variable<String>(localDate);
    map['note'] = Variable<String>(note);
    return map;
  }

  TransactionsCompanion toCompanion(bool nullToAbsent) {
    return TransactionsCompanion(
      id: Value(id),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      serverVersion: serverVersion == null && nullToAbsent
          ? const Value.absent()
          : Value(serverVersion),
      accountId: Value(accountId),
      categoryId: categoryId == null && nullToAbsent
          ? const Value.absent()
          : Value(categoryId),
      kind: Value(kind),
      amountMinor: Value(amountMinor),
      currency: Value(currency),
      amountBaseMinor: amountBaseMinor == null && nullToAbsent
          ? const Value.absent()
          : Value(amountBaseMinor),
      fxRateToBase: fxRateToBase == null && nullToAbsent
          ? const Value.absent()
          : Value(fxRateToBase),
      transferAccountId: transferAccountId == null && nullToAbsent
          ? const Value.absent()
          : Value(transferAccountId),
      transferAmountMinor: transferAmountMinor == null && nullToAbsent
          ? const Value.absent()
          : Value(transferAmountMinor),
      occurredAt: Value(occurredAt),
      localDate: Value(localDate),
      note: Value(note),
    );
  }

  factory MoneyTransaction.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MoneyTransaction(
      id: serializer.fromJson<String>(json['id']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
      serverVersion: serializer.fromJson<int?>(json['serverVersion']),
      accountId: serializer.fromJson<String>(json['accountId']),
      categoryId: serializer.fromJson<String?>(json['categoryId']),
      kind: serializer.fromJson<String>(json['kind']),
      amountMinor: serializer.fromJson<int>(json['amountMinor']),
      currency: serializer.fromJson<String>(json['currency']),
      amountBaseMinor: serializer.fromJson<int?>(json['amountBaseMinor']),
      fxRateToBase: serializer.fromJson<String?>(json['fxRateToBase']),
      transferAccountId: serializer.fromJson<String?>(
        json['transferAccountId'],
      ),
      transferAmountMinor: serializer.fromJson<int?>(
        json['transferAmountMinor'],
      ),
      occurredAt: serializer.fromJson<DateTime>(json['occurredAt']),
      localDate: serializer.fromJson<String>(json['localDate']),
      note: serializer.fromJson<String>(json['note']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
      'serverVersion': serializer.toJson<int?>(serverVersion),
      'accountId': serializer.toJson<String>(accountId),
      'categoryId': serializer.toJson<String?>(categoryId),
      'kind': serializer.toJson<String>(kind),
      'amountMinor': serializer.toJson<int>(amountMinor),
      'currency': serializer.toJson<String>(currency),
      'amountBaseMinor': serializer.toJson<int?>(amountBaseMinor),
      'fxRateToBase': serializer.toJson<String?>(fxRateToBase),
      'transferAccountId': serializer.toJson<String?>(transferAccountId),
      'transferAmountMinor': serializer.toJson<int?>(transferAmountMinor),
      'occurredAt': serializer.toJson<DateTime>(occurredAt),
      'localDate': serializer.toJson<String>(localDate),
      'note': serializer.toJson<String>(note),
    };
  }

  MoneyTransaction copyWith({
    String? id,
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
    Value<int?> serverVersion = const Value.absent(),
    String? accountId,
    Value<String?> categoryId = const Value.absent(),
    String? kind,
    int? amountMinor,
    String? currency,
    Value<int?> amountBaseMinor = const Value.absent(),
    Value<String?> fxRateToBase = const Value.absent(),
    Value<String?> transferAccountId = const Value.absent(),
    Value<int?> transferAmountMinor = const Value.absent(),
    DateTime? occurredAt,
    String? localDate,
    String? note,
  }) => MoneyTransaction(
    id: id ?? this.id,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    serverVersion: serverVersion.present
        ? serverVersion.value
        : this.serverVersion,
    accountId: accountId ?? this.accountId,
    categoryId: categoryId.present ? categoryId.value : this.categoryId,
    kind: kind ?? this.kind,
    amountMinor: amountMinor ?? this.amountMinor,
    currency: currency ?? this.currency,
    amountBaseMinor: amountBaseMinor.present
        ? amountBaseMinor.value
        : this.amountBaseMinor,
    fxRateToBase: fxRateToBase.present ? fxRateToBase.value : this.fxRateToBase,
    transferAccountId: transferAccountId.present
        ? transferAccountId.value
        : this.transferAccountId,
    transferAmountMinor: transferAmountMinor.present
        ? transferAmountMinor.value
        : this.transferAmountMinor,
    occurredAt: occurredAt ?? this.occurredAt,
    localDate: localDate ?? this.localDate,
    note: note ?? this.note,
  );
  MoneyTransaction copyWithCompanion(TransactionsCompanion data) {
    return MoneyTransaction(
      id: data.id.present ? data.id.value : this.id,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      serverVersion: data.serverVersion.present
          ? data.serverVersion.value
          : this.serverVersion,
      accountId: data.accountId.present ? data.accountId.value : this.accountId,
      categoryId: data.categoryId.present
          ? data.categoryId.value
          : this.categoryId,
      kind: data.kind.present ? data.kind.value : this.kind,
      amountMinor: data.amountMinor.present
          ? data.amountMinor.value
          : this.amountMinor,
      currency: data.currency.present ? data.currency.value : this.currency,
      amountBaseMinor: data.amountBaseMinor.present
          ? data.amountBaseMinor.value
          : this.amountBaseMinor,
      fxRateToBase: data.fxRateToBase.present
          ? data.fxRateToBase.value
          : this.fxRateToBase,
      transferAccountId: data.transferAccountId.present
          ? data.transferAccountId.value
          : this.transferAccountId,
      transferAmountMinor: data.transferAmountMinor.present
          ? data.transferAmountMinor.value
          : this.transferAmountMinor,
      occurredAt: data.occurredAt.present
          ? data.occurredAt.value
          : this.occurredAt,
      localDate: data.localDate.present ? data.localDate.value : this.localDate,
      note: data.note.present ? data.note.value : this.note,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MoneyTransaction(')
          ..write('id: $id, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('serverVersion: $serverVersion, ')
          ..write('accountId: $accountId, ')
          ..write('categoryId: $categoryId, ')
          ..write('kind: $kind, ')
          ..write('amountMinor: $amountMinor, ')
          ..write('currency: $currency, ')
          ..write('amountBaseMinor: $amountBaseMinor, ')
          ..write('fxRateToBase: $fxRateToBase, ')
          ..write('transferAccountId: $transferAccountId, ')
          ..write('transferAmountMinor: $transferAmountMinor, ')
          ..write('occurredAt: $occurredAt, ')
          ..write('localDate: $localDate, ')
          ..write('note: $note')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    updatedAt,
    deletedAt,
    serverVersion,
    accountId,
    categoryId,
    kind,
    amountMinor,
    currency,
    amountBaseMinor,
    fxRateToBase,
    transferAccountId,
    transferAmountMinor,
    occurredAt,
    localDate,
    note,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MoneyTransaction &&
          other.id == this.id &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.serverVersion == this.serverVersion &&
          other.accountId == this.accountId &&
          other.categoryId == this.categoryId &&
          other.kind == this.kind &&
          other.amountMinor == this.amountMinor &&
          other.currency == this.currency &&
          other.amountBaseMinor == this.amountBaseMinor &&
          other.fxRateToBase == this.fxRateToBase &&
          other.transferAccountId == this.transferAccountId &&
          other.transferAmountMinor == this.transferAmountMinor &&
          other.occurredAt == this.occurredAt &&
          other.localDate == this.localDate &&
          other.note == this.note);
}

class TransactionsCompanion extends UpdateCompanion<MoneyTransaction> {
  final Value<String> id;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<int?> serverVersion;
  final Value<String> accountId;
  final Value<String?> categoryId;
  final Value<String> kind;
  final Value<int> amountMinor;
  final Value<String> currency;
  final Value<int?> amountBaseMinor;
  final Value<String?> fxRateToBase;
  final Value<String?> transferAccountId;
  final Value<int?> transferAmountMinor;
  final Value<DateTime> occurredAt;
  final Value<String> localDate;
  final Value<String> note;
  final Value<int> rowid;
  const TransactionsCompanion({
    this.id = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.serverVersion = const Value.absent(),
    this.accountId = const Value.absent(),
    this.categoryId = const Value.absent(),
    this.kind = const Value.absent(),
    this.amountMinor = const Value.absent(),
    this.currency = const Value.absent(),
    this.amountBaseMinor = const Value.absent(),
    this.fxRateToBase = const Value.absent(),
    this.transferAccountId = const Value.absent(),
    this.transferAmountMinor = const Value.absent(),
    this.occurredAt = const Value.absent(),
    this.localDate = const Value.absent(),
    this.note = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TransactionsCompanion.insert({
    required String id,
    required DateTime updatedAt,
    this.deletedAt = const Value.absent(),
    this.serverVersion = const Value.absent(),
    required String accountId,
    this.categoryId = const Value.absent(),
    required String kind,
    required int amountMinor,
    required String currency,
    this.amountBaseMinor = const Value.absent(),
    this.fxRateToBase = const Value.absent(),
    this.transferAccountId = const Value.absent(),
    this.transferAmountMinor = const Value.absent(),
    required DateTime occurredAt,
    required String localDate,
    this.note = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       updatedAt = Value(updatedAt),
       accountId = Value(accountId),
       kind = Value(kind),
       amountMinor = Value(amountMinor),
       currency = Value(currency),
       occurredAt = Value(occurredAt),
       localDate = Value(localDate);
  static Insertable<MoneyTransaction> custom({
    Expression<String>? id,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<int>? serverVersion,
    Expression<String>? accountId,
    Expression<String>? categoryId,
    Expression<String>? kind,
    Expression<int>? amountMinor,
    Expression<String>? currency,
    Expression<int>? amountBaseMinor,
    Expression<String>? fxRateToBase,
    Expression<String>? transferAccountId,
    Expression<int>? transferAmountMinor,
    Expression<DateTime>? occurredAt,
    Expression<String>? localDate,
    Expression<String>? note,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (serverVersion != null) 'server_version': serverVersion,
      if (accountId != null) 'account_id': accountId,
      if (categoryId != null) 'category_id': categoryId,
      if (kind != null) 'kind': kind,
      if (amountMinor != null) 'amount_minor': amountMinor,
      if (currency != null) 'currency': currency,
      if (amountBaseMinor != null) 'amount_base_minor': amountBaseMinor,
      if (fxRateToBase != null) 'fx_rate_to_base': fxRateToBase,
      if (transferAccountId != null) 'transfer_account_id': transferAccountId,
      if (transferAmountMinor != null)
        'transfer_amount_minor': transferAmountMinor,
      if (occurredAt != null) 'occurred_at': occurredAt,
      if (localDate != null) 'local_date': localDate,
      if (note != null) 'note': note,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TransactionsCompanion copyWith({
    Value<String>? id,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<int?>? serverVersion,
    Value<String>? accountId,
    Value<String?>? categoryId,
    Value<String>? kind,
    Value<int>? amountMinor,
    Value<String>? currency,
    Value<int?>? amountBaseMinor,
    Value<String?>? fxRateToBase,
    Value<String?>? transferAccountId,
    Value<int?>? transferAmountMinor,
    Value<DateTime>? occurredAt,
    Value<String>? localDate,
    Value<String>? note,
    Value<int>? rowid,
  }) {
    return TransactionsCompanion(
      id: id ?? this.id,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      serverVersion: serverVersion ?? this.serverVersion,
      accountId: accountId ?? this.accountId,
      categoryId: categoryId ?? this.categoryId,
      kind: kind ?? this.kind,
      amountMinor: amountMinor ?? this.amountMinor,
      currency: currency ?? this.currency,
      amountBaseMinor: amountBaseMinor ?? this.amountBaseMinor,
      fxRateToBase: fxRateToBase ?? this.fxRateToBase,
      transferAccountId: transferAccountId ?? this.transferAccountId,
      transferAmountMinor: transferAmountMinor ?? this.transferAmountMinor,
      occurredAt: occurredAt ?? this.occurredAt,
      localDate: localDate ?? this.localDate,
      note: note ?? this.note,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (serverVersion.present) {
      map['server_version'] = Variable<int>(serverVersion.value);
    }
    if (accountId.present) {
      map['account_id'] = Variable<String>(accountId.value);
    }
    if (categoryId.present) {
      map['category_id'] = Variable<String>(categoryId.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (amountMinor.present) {
      map['amount_minor'] = Variable<int>(amountMinor.value);
    }
    if (currency.present) {
      map['currency'] = Variable<String>(currency.value);
    }
    if (amountBaseMinor.present) {
      map['amount_base_minor'] = Variable<int>(amountBaseMinor.value);
    }
    if (fxRateToBase.present) {
      map['fx_rate_to_base'] = Variable<String>(fxRateToBase.value);
    }
    if (transferAccountId.present) {
      map['transfer_account_id'] = Variable<String>(transferAccountId.value);
    }
    if (transferAmountMinor.present) {
      map['transfer_amount_minor'] = Variable<int>(transferAmountMinor.value);
    }
    if (occurredAt.present) {
      map['occurred_at'] = Variable<DateTime>(occurredAt.value);
    }
    if (localDate.present) {
      map['local_date'] = Variable<String>(localDate.value);
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TransactionsCompanion(')
          ..write('id: $id, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('serverVersion: $serverVersion, ')
          ..write('accountId: $accountId, ')
          ..write('categoryId: $categoryId, ')
          ..write('kind: $kind, ')
          ..write('amountMinor: $amountMinor, ')
          ..write('currency: $currency, ')
          ..write('amountBaseMinor: $amountBaseMinor, ')
          ..write('fxRateToBase: $fxRateToBase, ')
          ..write('transferAccountId: $transferAccountId, ')
          ..write('transferAmountMinor: $transferAmountMinor, ')
          ..write('occurredAt: $occurredAt, ')
          ..write('localDate: $localDate, ')
          ..write('note: $note, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $OutboxTable extends Outbox with TableInfo<$OutboxTable, OutboxData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $OutboxTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _entityMeta = const VerificationMeta('entity');
  @override
  late final GeneratedColumn<String> entity = GeneratedColumn<String>(
    'entity',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _rowIdMeta = const VerificationMeta('rowId');
  @override
  late final GeneratedColumn<String> rowId = GeneratedColumn<String>(
    'row_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _queuedUpdatedAtMeta = const VerificationMeta(
    'queuedUpdatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> queuedUpdatedAt =
      GeneratedColumn<DateTime>(
        'queued_updated_at',
        aliasedName,
        false,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _attemptsMeta = const VerificationMeta(
    'attempts',
  );
  @override
  late final GeneratedColumn<int> attempts = GeneratedColumn<int>(
    'attempts',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _rejectedCodeMeta = const VerificationMeta(
    'rejectedCode',
  );
  @override
  late final GeneratedColumn<String> rejectedCode = GeneratedColumn<String>(
    'rejected_code',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _rejectedMessageMeta = const VerificationMeta(
    'rejectedMessage',
  );
  @override
  late final GeneratedColumn<String> rejectedMessage = GeneratedColumn<String>(
    'rejected_message',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    entity,
    rowId,
    queuedUpdatedAt,
    attempts,
    rejectedCode,
    rejectedMessage,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'outbox';
  @override
  VerificationContext validateIntegrity(
    Insertable<OutboxData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('entity')) {
      context.handle(
        _entityMeta,
        entity.isAcceptableOrUnknown(data['entity']!, _entityMeta),
      );
    } else if (isInserting) {
      context.missing(_entityMeta);
    }
    if (data.containsKey('row_id')) {
      context.handle(
        _rowIdMeta,
        rowId.isAcceptableOrUnknown(data['row_id']!, _rowIdMeta),
      );
    } else if (isInserting) {
      context.missing(_rowIdMeta);
    }
    if (data.containsKey('queued_updated_at')) {
      context.handle(
        _queuedUpdatedAtMeta,
        queuedUpdatedAt.isAcceptableOrUnknown(
          data['queued_updated_at']!,
          _queuedUpdatedAtMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_queuedUpdatedAtMeta);
    }
    if (data.containsKey('attempts')) {
      context.handle(
        _attemptsMeta,
        attempts.isAcceptableOrUnknown(data['attempts']!, _attemptsMeta),
      );
    }
    if (data.containsKey('rejected_code')) {
      context.handle(
        _rejectedCodeMeta,
        rejectedCode.isAcceptableOrUnknown(
          data['rejected_code']!,
          _rejectedCodeMeta,
        ),
      );
    }
    if (data.containsKey('rejected_message')) {
      context.handle(
        _rejectedMessageMeta,
        rejectedMessage.isAcceptableOrUnknown(
          data['rejected_message']!,
          _rejectedMessageMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {entity, rowId};
  @override
  OutboxData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return OutboxData(
      entity: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity'],
      )!,
      rowId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}row_id'],
      )!,
      queuedUpdatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}queued_updated_at'],
      )!,
      attempts: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempts'],
      )!,
      rejectedCode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}rejected_code'],
      ),
      rejectedMessage: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}rejected_message'],
      ),
    );
  }

  @override
  $OutboxTable createAlias(String alias) {
    return $OutboxTable(attachedDatabase, alias);
  }
}

class OutboxData extends DataClass implements Insertable<OutboxData> {
  /// account, category or transaction
  final String entity;
  final String rowId;

  /// The row's updatedAt when it was queued. Used to tell whether the row
  /// was edited again while a push was on its way.
  final DateTime queuedUpdatedAt;
  final int attempts;

  /// Set when the server rejected the change; it is not retried as-is.
  final String? rejectedCode;
  final String? rejectedMessage;
  const OutboxData({
    required this.entity,
    required this.rowId,
    required this.queuedUpdatedAt,
    required this.attempts,
    this.rejectedCode,
    this.rejectedMessage,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['entity'] = Variable<String>(entity);
    map['row_id'] = Variable<String>(rowId);
    map['queued_updated_at'] = Variable<DateTime>(queuedUpdatedAt);
    map['attempts'] = Variable<int>(attempts);
    if (!nullToAbsent || rejectedCode != null) {
      map['rejected_code'] = Variable<String>(rejectedCode);
    }
    if (!nullToAbsent || rejectedMessage != null) {
      map['rejected_message'] = Variable<String>(rejectedMessage);
    }
    return map;
  }

  OutboxCompanion toCompanion(bool nullToAbsent) {
    return OutboxCompanion(
      entity: Value(entity),
      rowId: Value(rowId),
      queuedUpdatedAt: Value(queuedUpdatedAt),
      attempts: Value(attempts),
      rejectedCode: rejectedCode == null && nullToAbsent
          ? const Value.absent()
          : Value(rejectedCode),
      rejectedMessage: rejectedMessage == null && nullToAbsent
          ? const Value.absent()
          : Value(rejectedMessage),
    );
  }

  factory OutboxData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return OutboxData(
      entity: serializer.fromJson<String>(json['entity']),
      rowId: serializer.fromJson<String>(json['rowId']),
      queuedUpdatedAt: serializer.fromJson<DateTime>(json['queuedUpdatedAt']),
      attempts: serializer.fromJson<int>(json['attempts']),
      rejectedCode: serializer.fromJson<String?>(json['rejectedCode']),
      rejectedMessage: serializer.fromJson<String?>(json['rejectedMessage']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'entity': serializer.toJson<String>(entity),
      'rowId': serializer.toJson<String>(rowId),
      'queuedUpdatedAt': serializer.toJson<DateTime>(queuedUpdatedAt),
      'attempts': serializer.toJson<int>(attempts),
      'rejectedCode': serializer.toJson<String?>(rejectedCode),
      'rejectedMessage': serializer.toJson<String?>(rejectedMessage),
    };
  }

  OutboxData copyWith({
    String? entity,
    String? rowId,
    DateTime? queuedUpdatedAt,
    int? attempts,
    Value<String?> rejectedCode = const Value.absent(),
    Value<String?> rejectedMessage = const Value.absent(),
  }) => OutboxData(
    entity: entity ?? this.entity,
    rowId: rowId ?? this.rowId,
    queuedUpdatedAt: queuedUpdatedAt ?? this.queuedUpdatedAt,
    attempts: attempts ?? this.attempts,
    rejectedCode: rejectedCode.present ? rejectedCode.value : this.rejectedCode,
    rejectedMessage: rejectedMessage.present
        ? rejectedMessage.value
        : this.rejectedMessage,
  );
  OutboxData copyWithCompanion(OutboxCompanion data) {
    return OutboxData(
      entity: data.entity.present ? data.entity.value : this.entity,
      rowId: data.rowId.present ? data.rowId.value : this.rowId,
      queuedUpdatedAt: data.queuedUpdatedAt.present
          ? data.queuedUpdatedAt.value
          : this.queuedUpdatedAt,
      attempts: data.attempts.present ? data.attempts.value : this.attempts,
      rejectedCode: data.rejectedCode.present
          ? data.rejectedCode.value
          : this.rejectedCode,
      rejectedMessage: data.rejectedMessage.present
          ? data.rejectedMessage.value
          : this.rejectedMessage,
    );
  }

  @override
  String toString() {
    return (StringBuffer('OutboxData(')
          ..write('entity: $entity, ')
          ..write('rowId: $rowId, ')
          ..write('queuedUpdatedAt: $queuedUpdatedAt, ')
          ..write('attempts: $attempts, ')
          ..write('rejectedCode: $rejectedCode, ')
          ..write('rejectedMessage: $rejectedMessage')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    entity,
    rowId,
    queuedUpdatedAt,
    attempts,
    rejectedCode,
    rejectedMessage,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OutboxData &&
          other.entity == this.entity &&
          other.rowId == this.rowId &&
          other.queuedUpdatedAt == this.queuedUpdatedAt &&
          other.attempts == this.attempts &&
          other.rejectedCode == this.rejectedCode &&
          other.rejectedMessage == this.rejectedMessage);
}

class OutboxCompanion extends UpdateCompanion<OutboxData> {
  final Value<String> entity;
  final Value<String> rowId;
  final Value<DateTime> queuedUpdatedAt;
  final Value<int> attempts;
  final Value<String?> rejectedCode;
  final Value<String?> rejectedMessage;
  final Value<int> rowid;
  const OutboxCompanion({
    this.entity = const Value.absent(),
    this.rowId = const Value.absent(),
    this.queuedUpdatedAt = const Value.absent(),
    this.attempts = const Value.absent(),
    this.rejectedCode = const Value.absent(),
    this.rejectedMessage = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  OutboxCompanion.insert({
    required String entity,
    required String rowId,
    required DateTime queuedUpdatedAt,
    this.attempts = const Value.absent(),
    this.rejectedCode = const Value.absent(),
    this.rejectedMessage = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : entity = Value(entity),
       rowId = Value(rowId),
       queuedUpdatedAt = Value(queuedUpdatedAt);
  static Insertable<OutboxData> custom({
    Expression<String>? entity,
    Expression<String>? rowId,
    Expression<DateTime>? queuedUpdatedAt,
    Expression<int>? attempts,
    Expression<String>? rejectedCode,
    Expression<String>? rejectedMessage,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (entity != null) 'entity': entity,
      if (rowId != null) 'row_id': rowId,
      if (queuedUpdatedAt != null) 'queued_updated_at': queuedUpdatedAt,
      if (attempts != null) 'attempts': attempts,
      if (rejectedCode != null) 'rejected_code': rejectedCode,
      if (rejectedMessage != null) 'rejected_message': rejectedMessage,
      if (rowid != null) 'rowid': rowid,
    });
  }

  OutboxCompanion copyWith({
    Value<String>? entity,
    Value<String>? rowId,
    Value<DateTime>? queuedUpdatedAt,
    Value<int>? attempts,
    Value<String?>? rejectedCode,
    Value<String?>? rejectedMessage,
    Value<int>? rowid,
  }) {
    return OutboxCompanion(
      entity: entity ?? this.entity,
      rowId: rowId ?? this.rowId,
      queuedUpdatedAt: queuedUpdatedAt ?? this.queuedUpdatedAt,
      attempts: attempts ?? this.attempts,
      rejectedCode: rejectedCode ?? this.rejectedCode,
      rejectedMessage: rejectedMessage ?? this.rejectedMessage,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (entity.present) {
      map['entity'] = Variable<String>(entity.value);
    }
    if (rowId.present) {
      map['row_id'] = Variable<String>(rowId.value);
    }
    if (queuedUpdatedAt.present) {
      map['queued_updated_at'] = Variable<DateTime>(queuedUpdatedAt.value);
    }
    if (attempts.present) {
      map['attempts'] = Variable<int>(attempts.value);
    }
    if (rejectedCode.present) {
      map['rejected_code'] = Variable<String>(rejectedCode.value);
    }
    if (rejectedMessage.present) {
      map['rejected_message'] = Variable<String>(rejectedMessage.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('OutboxCompanion(')
          ..write('entity: $entity, ')
          ..write('rowId: $rowId, ')
          ..write('queuedUpdatedAt: $queuedUpdatedAt, ')
          ..write('attempts: $attempts, ')
          ..write('rejectedCode: $rejectedCode, ')
          ..write('rejectedMessage: $rejectedMessage, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $LocalMetaTable localMeta = $LocalMetaTable(this);
  late final $AccountsTable accounts = $AccountsTable(this);
  late final $CategoriesTable categories = $CategoriesTable(this);
  late final $TransactionsTable transactions = $TransactionsTable(this);
  late final $OutboxTable outbox = $OutboxTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    localMeta,
    accounts,
    categories,
    transactions,
    outbox,
  ];
  @override
  DriftDatabaseOptions get options =>
      const DriftDatabaseOptions(storeDateTimeAsText: true);
}

typedef $$LocalMetaTableCreateCompanionBuilder = LocalMetaCompanion Function({
  required String key,
  required String value,
  Value<int> rowid,
});
typedef $$LocalMetaTableUpdateCompanionBuilder = LocalMetaCompanion Function({
  Value<String> key,
  Value<String> value,
  Value<int> rowid,
});

class $$LocalMetaTableFilterComposer
    extends Composer<_$AppDatabase, $LocalMetaTable> {
  $$LocalMetaTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalMetaTableOrderingComposer
    extends Composer<_$AppDatabase, $LocalMetaTable> {
  $$LocalMetaTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalMetaTableAnnotationComposer
    extends Composer<_$AppDatabase, $LocalMetaTable> {
  $$LocalMetaTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$LocalMetaTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $LocalMetaTable,
          LocalMetaData,
          $$LocalMetaTableFilterComposer,
          $$LocalMetaTableOrderingComposer,
          $$LocalMetaTableAnnotationComposer,
          $$LocalMetaTableCreateCompanionBuilder,
          $$LocalMetaTableUpdateCompanionBuilder,
          (
            LocalMetaData,
            BaseReferences<_$AppDatabase, $LocalMetaTable, LocalMetaData>,
          ),
          LocalMetaData,
          PrefetchHooks Function()
        > {
  $$LocalMetaTableTableManager(_$AppDatabase db, $LocalMetaTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalMetaTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalMetaTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalMetaTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> key = const Value.absent(),
            Value<String> value = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) => LocalMetaCompanion(key: key, value: value, rowid: rowid),
          createCompanionCallback: ({
            required String key,
            required String value,
            Value<int> rowid = const Value.absent(),
          }) => LocalMetaCompanion.insert(key: key, value: value, rowid: rowid),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$LocalMetaTable, LocalMetaData>(table),
                  BaseReferences<_$AppDatabase, $LocalMetaTable, LocalMetaData>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalMetaTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $LocalMetaTable,
      LocalMetaData,
      $$LocalMetaTableFilterComposer,
      $$LocalMetaTableOrderingComposer,
      $$LocalMetaTableAnnotationComposer,
      $$LocalMetaTableCreateCompanionBuilder,
      $$LocalMetaTableUpdateCompanionBuilder,
      (
        LocalMetaData,
        BaseReferences<_$AppDatabase, $LocalMetaTable, LocalMetaData>,
      ),
      LocalMetaData,
      PrefetchHooks Function()
    >;
typedef $$AccountsTableCreateCompanionBuilder = AccountsCompanion Function({
  required String id,
  required DateTime updatedAt,
  Value<DateTime?> deletedAt,
  Value<int?> serverVersion,
  required String name,
  required String type,
  required String currency,
  Value<int> openingBalanceMinor,
  Value<String> icon,
  Value<String> color,
  Value<bool> archived,
  Value<int> sortOrder,
  Value<int> rowid,
});
typedef $$AccountsTableUpdateCompanionBuilder = AccountsCompanion Function({
  Value<String> id,
  Value<DateTime> updatedAt,
  Value<DateTime?> deletedAt,
  Value<int?> serverVersion,
  Value<String> name,
  Value<String> type,
  Value<String> currency,
  Value<int> openingBalanceMinor,
  Value<String> icon,
  Value<String> color,
  Value<bool> archived,
  Value<int> sortOrder,
  Value<int> rowid,
});

class $$AccountsTableFilterComposer
    extends Composer<_$AppDatabase, $AccountsTable> {
  $$AccountsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get serverVersion => $composableBuilder(
    column: $table.serverVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get currency => $composableBuilder(
    column: $table.currency,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get openingBalanceMinor => $composableBuilder(
    column: $table.openingBalanceMinor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get icon => $composableBuilder(
    column: $table.icon,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get color => $composableBuilder(
    column: $table.color,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get archived => $composableBuilder(
    column: $table.archived,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AccountsTableOrderingComposer
    extends Composer<_$AppDatabase, $AccountsTable> {
  $$AccountsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get serverVersion => $composableBuilder(
    column: $table.serverVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get currency => $composableBuilder(
    column: $table.currency,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get openingBalanceMinor => $composableBuilder(
    column: $table.openingBalanceMinor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get icon => $composableBuilder(
    column: $table.icon,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get color => $composableBuilder(
    column: $table.color,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get archived => $composableBuilder(
    column: $table.archived,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AccountsTableAnnotationComposer
    extends Composer<_$AppDatabase, $AccountsTable> {
  $$AccountsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<int> get serverVersion => $composableBuilder(
    column: $table.serverVersion,
    builder: (column) => column,
  );

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get currency =>
      $composableBuilder(column: $table.currency, builder: (column) => column);

  GeneratedColumn<int> get openingBalanceMinor => $composableBuilder(
    column: $table.openingBalanceMinor,
    builder: (column) => column,
  );

  GeneratedColumn<String> get icon =>
      $composableBuilder(column: $table.icon, builder: (column) => column);

  GeneratedColumn<String> get color =>
      $composableBuilder(column: $table.color, builder: (column) => column);

  GeneratedColumn<bool> get archived =>
      $composableBuilder(column: $table.archived, builder: (column) => column);

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);
}

class $$AccountsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AccountsTable,
          Account,
          $$AccountsTableFilterComposer,
          $$AccountsTableOrderingComposer,
          $$AccountsTableAnnotationComposer,
          $$AccountsTableCreateCompanionBuilder,
          $$AccountsTableUpdateCompanionBuilder,
          (Account, BaseReferences<_$AppDatabase, $AccountsTable, Account>),
          Account,
          PrefetchHooks Function()
        > {
  $$AccountsTableTableManager(_$AppDatabase db, $AccountsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AccountsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AccountsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AccountsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int?> serverVersion = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> type = const Value.absent(),
                Value<String> currency = const Value.absent(),
                Value<int> openingBalanceMinor = const Value.absent(),
                Value<String> icon = const Value.absent(),
                Value<String> color = const Value.absent(),
                Value<bool> archived = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AccountsCompanion(
                id: id,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                serverVersion: serverVersion,
                name: name,
                type: type,
                currency: currency,
                openingBalanceMinor: openingBalanceMinor,
                icon: icon,
                color: color,
                archived: archived,
                sortOrder: sortOrder,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required DateTime updatedAt,
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int?> serverVersion = const Value.absent(),
                required String name,
                required String type,
                required String currency,
                Value<int> openingBalanceMinor = const Value.absent(),
                Value<String> icon = const Value.absent(),
                Value<String> color = const Value.absent(),
                Value<bool> archived = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AccountsCompanion.insert(
                id: id,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                serverVersion: serverVersion,
                name: name,
                type: type,
                currency: currency,
                openingBalanceMinor: openingBalanceMinor,
                icon: icon,
                color: color,
                archived: archived,
                sortOrder: sortOrder,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$AccountsTable, Account>(table),
                  BaseReferences<_$AppDatabase, $AccountsTable, Account>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AccountsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AccountsTable,
      Account,
      $$AccountsTableFilterComposer,
      $$AccountsTableOrderingComposer,
      $$AccountsTableAnnotationComposer,
      $$AccountsTableCreateCompanionBuilder,
      $$AccountsTableUpdateCompanionBuilder,
      (Account, BaseReferences<_$AppDatabase, $AccountsTable, Account>),
      Account,
      PrefetchHooks Function()
    >;
typedef $$CategoriesTableCreateCompanionBuilder = CategoriesCompanion Function({
  required String id,
  required DateTime updatedAt,
  Value<DateTime?> deletedAt,
  Value<int?> serverVersion,
  Value<String?> parentId,
  required String name,
  required String kind,
  Value<String> icon,
  Value<String> color,
  Value<int> sortOrder,
  Value<int> rowid,
});
typedef $$CategoriesTableUpdateCompanionBuilder = CategoriesCompanion Function({
  Value<String> id,
  Value<DateTime> updatedAt,
  Value<DateTime?> deletedAt,
  Value<int?> serverVersion,
  Value<String?> parentId,
  Value<String> name,
  Value<String> kind,
  Value<String> icon,
  Value<String> color,
  Value<int> sortOrder,
  Value<int> rowid,
});

class $$CategoriesTableFilterComposer
    extends Composer<_$AppDatabase, $CategoriesTable> {
  $$CategoriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get serverVersion => $composableBuilder(
    column: $table.serverVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get parentId => $composableBuilder(
    column: $table.parentId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get icon => $composableBuilder(
    column: $table.icon,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get color => $composableBuilder(
    column: $table.color,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CategoriesTableOrderingComposer
    extends Composer<_$AppDatabase, $CategoriesTable> {
  $$CategoriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get serverVersion => $composableBuilder(
    column: $table.serverVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get parentId => $composableBuilder(
    column: $table.parentId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get icon => $composableBuilder(
    column: $table.icon,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get color => $composableBuilder(
    column: $table.color,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CategoriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $CategoriesTable> {
  $$CategoriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<int> get serverVersion => $composableBuilder(
    column: $table.serverVersion,
    builder: (column) => column,
  );

  GeneratedColumn<String> get parentId =>
      $composableBuilder(column: $table.parentId, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get icon =>
      $composableBuilder(column: $table.icon, builder: (column) => column);

  GeneratedColumn<String> get color =>
      $composableBuilder(column: $table.color, builder: (column) => column);

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);
}

class $$CategoriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CategoriesTable,
          Category,
          $$CategoriesTableFilterComposer,
          $$CategoriesTableOrderingComposer,
          $$CategoriesTableAnnotationComposer,
          $$CategoriesTableCreateCompanionBuilder,
          $$CategoriesTableUpdateCompanionBuilder,
          (Category, BaseReferences<_$AppDatabase, $CategoriesTable, Category>),
          Category,
          PrefetchHooks Function()
        > {
  $$CategoriesTableTableManager(_$AppDatabase db, $CategoriesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CategoriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CategoriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CategoriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int?> serverVersion = const Value.absent(),
                Value<String?> parentId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String> icon = const Value.absent(),
                Value<String> color = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CategoriesCompanion(
                id: id,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                serverVersion: serverVersion,
                parentId: parentId,
                name: name,
                kind: kind,
                icon: icon,
                color: color,
                sortOrder: sortOrder,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required DateTime updatedAt,
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int?> serverVersion = const Value.absent(),
                Value<String?> parentId = const Value.absent(),
                required String name,
                required String kind,
                Value<String> icon = const Value.absent(),
                Value<String> color = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CategoriesCompanion.insert(
                id: id,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                serverVersion: serverVersion,
                parentId: parentId,
                name: name,
                kind: kind,
                icon: icon,
                color: color,
                sortOrder: sortOrder,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$CategoriesTable, Category>(table),
                  BaseReferences<_$AppDatabase, $CategoriesTable, Category>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CategoriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CategoriesTable,
      Category,
      $$CategoriesTableFilterComposer,
      $$CategoriesTableOrderingComposer,
      $$CategoriesTableAnnotationComposer,
      $$CategoriesTableCreateCompanionBuilder,
      $$CategoriesTableUpdateCompanionBuilder,
      (Category, BaseReferences<_$AppDatabase, $CategoriesTable, Category>),
      Category,
      PrefetchHooks Function()
    >;
typedef $$TransactionsTableCreateCompanionBuilder =
    TransactionsCompanion Function({
      required String id,
      required DateTime updatedAt,
      Value<DateTime?> deletedAt,
      Value<int?> serverVersion,
      required String accountId,
      Value<String?> categoryId,
      required String kind,
      required int amountMinor,
      required String currency,
      Value<int?> amountBaseMinor,
      Value<String?> fxRateToBase,
      Value<String?> transferAccountId,
      Value<int?> transferAmountMinor,
      required DateTime occurredAt,
      required String localDate,
      Value<String> note,
      Value<int> rowid,
    });
typedef $$TransactionsTableUpdateCompanionBuilder =
    TransactionsCompanion Function({
      Value<String> id,
      Value<DateTime> updatedAt,
      Value<DateTime?> deletedAt,
      Value<int?> serverVersion,
      Value<String> accountId,
      Value<String?> categoryId,
      Value<String> kind,
      Value<int> amountMinor,
      Value<String> currency,
      Value<int?> amountBaseMinor,
      Value<String?> fxRateToBase,
      Value<String?> transferAccountId,
      Value<int?> transferAmountMinor,
      Value<DateTime> occurredAt,
      Value<String> localDate,
      Value<String> note,
      Value<int> rowid,
    });

class $$TransactionsTableFilterComposer
    extends Composer<_$AppDatabase, $TransactionsTable> {
  $$TransactionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get serverVersion => $composableBuilder(
    column: $table.serverVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get accountId => $composableBuilder(
    column: $table.accountId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get categoryId => $composableBuilder(
    column: $table.categoryId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get amountMinor => $composableBuilder(
    column: $table.amountMinor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get currency => $composableBuilder(
    column: $table.currency,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get amountBaseMinor => $composableBuilder(
    column: $table.amountBaseMinor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fxRateToBase => $composableBuilder(
    column: $table.fxRateToBase,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get transferAccountId => $composableBuilder(
    column: $table.transferAccountId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get transferAmountMinor => $composableBuilder(
    column: $table.transferAmountMinor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get occurredAt => $composableBuilder(
    column: $table.occurredAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get localDate => $composableBuilder(
    column: $table.localDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnFilters(column),
  );
}

class $$TransactionsTableOrderingComposer
    extends Composer<_$AppDatabase, $TransactionsTable> {
  $$TransactionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get serverVersion => $composableBuilder(
    column: $table.serverVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get accountId => $composableBuilder(
    column: $table.accountId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get categoryId => $composableBuilder(
    column: $table.categoryId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get amountMinor => $composableBuilder(
    column: $table.amountMinor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get currency => $composableBuilder(
    column: $table.currency,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get amountBaseMinor => $composableBuilder(
    column: $table.amountBaseMinor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fxRateToBase => $composableBuilder(
    column: $table.fxRateToBase,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get transferAccountId => $composableBuilder(
    column: $table.transferAccountId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get transferAmountMinor => $composableBuilder(
    column: $table.transferAmountMinor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get occurredAt => $composableBuilder(
    column: $table.occurredAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get localDate => $composableBuilder(
    column: $table.localDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TransactionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $TransactionsTable> {
  $$TransactionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<int> get serverVersion => $composableBuilder(
    column: $table.serverVersion,
    builder: (column) => column,
  );

  GeneratedColumn<String> get accountId =>
      $composableBuilder(column: $table.accountId, builder: (column) => column);

  GeneratedColumn<String> get categoryId => $composableBuilder(
    column: $table.categoryId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<int> get amountMinor => $composableBuilder(
    column: $table.amountMinor,
    builder: (column) => column,
  );

  GeneratedColumn<String> get currency =>
      $composableBuilder(column: $table.currency, builder: (column) => column);

  GeneratedColumn<int> get amountBaseMinor => $composableBuilder(
    column: $table.amountBaseMinor,
    builder: (column) => column,
  );

  GeneratedColumn<String> get fxRateToBase => $composableBuilder(
    column: $table.fxRateToBase,
    builder: (column) => column,
  );

  GeneratedColumn<String> get transferAccountId => $composableBuilder(
    column: $table.transferAccountId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get transferAmountMinor => $composableBuilder(
    column: $table.transferAmountMinor,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get occurredAt => $composableBuilder(
    column: $table.occurredAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get localDate =>
      $composableBuilder(column: $table.localDate, builder: (column) => column);

  GeneratedColumn<String> get note =>
      $composableBuilder(column: $table.note, builder: (column) => column);
}

class $$TransactionsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TransactionsTable,
          MoneyTransaction,
          $$TransactionsTableFilterComposer,
          $$TransactionsTableOrderingComposer,
          $$TransactionsTableAnnotationComposer,
          $$TransactionsTableCreateCompanionBuilder,
          $$TransactionsTableUpdateCompanionBuilder,
          (
            MoneyTransaction,
            BaseReferences<_$AppDatabase, $TransactionsTable, MoneyTransaction>,
          ),
          MoneyTransaction,
          PrefetchHooks Function()
        > {
  $$TransactionsTableTableManager(_$AppDatabase db, $TransactionsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TransactionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TransactionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TransactionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int?> serverVersion = const Value.absent(),
                Value<String> accountId = const Value.absent(),
                Value<String?> categoryId = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<int> amountMinor = const Value.absent(),
                Value<String> currency = const Value.absent(),
                Value<int?> amountBaseMinor = const Value.absent(),
                Value<String?> fxRateToBase = const Value.absent(),
                Value<String?> transferAccountId = const Value.absent(),
                Value<int?> transferAmountMinor = const Value.absent(),
                Value<DateTime> occurredAt = const Value.absent(),
                Value<String> localDate = const Value.absent(),
                Value<String> note = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TransactionsCompanion(
                id: id,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                serverVersion: serverVersion,
                accountId: accountId,
                categoryId: categoryId,
                kind: kind,
                amountMinor: amountMinor,
                currency: currency,
                amountBaseMinor: amountBaseMinor,
                fxRateToBase: fxRateToBase,
                transferAccountId: transferAccountId,
                transferAmountMinor: transferAmountMinor,
                occurredAt: occurredAt,
                localDate: localDate,
                note: note,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required DateTime updatedAt,
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int?> serverVersion = const Value.absent(),
                required String accountId,
                Value<String?> categoryId = const Value.absent(),
                required String kind,
                required int amountMinor,
                required String currency,
                Value<int?> amountBaseMinor = const Value.absent(),
                Value<String?> fxRateToBase = const Value.absent(),
                Value<String?> transferAccountId = const Value.absent(),
                Value<int?> transferAmountMinor = const Value.absent(),
                required DateTime occurredAt,
                required String localDate,
                Value<String> note = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TransactionsCompanion.insert(
                id: id,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                serverVersion: serverVersion,
                accountId: accountId,
                categoryId: categoryId,
                kind: kind,
                amountMinor: amountMinor,
                currency: currency,
                amountBaseMinor: amountBaseMinor,
                fxRateToBase: fxRateToBase,
                transferAccountId: transferAccountId,
                transferAmountMinor: transferAmountMinor,
                occurredAt: occurredAt,
                localDate: localDate,
                note: note,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$TransactionsTable, MoneyTransaction>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $TransactionsTable,
                    MoneyTransaction
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$TransactionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TransactionsTable,
      MoneyTransaction,
      $$TransactionsTableFilterComposer,
      $$TransactionsTableOrderingComposer,
      $$TransactionsTableAnnotationComposer,
      $$TransactionsTableCreateCompanionBuilder,
      $$TransactionsTableUpdateCompanionBuilder,
      (
        MoneyTransaction,
        BaseReferences<_$AppDatabase, $TransactionsTable, MoneyTransaction>,
      ),
      MoneyTransaction,
      PrefetchHooks Function()
    >;
typedef $$OutboxTableCreateCompanionBuilder = OutboxCompanion Function({
  required String entity,
  required String rowId,
  required DateTime queuedUpdatedAt,
  Value<int> attempts,
  Value<String?> rejectedCode,
  Value<String?> rejectedMessage,
  Value<int> rowid,
});
typedef $$OutboxTableUpdateCompanionBuilder = OutboxCompanion Function({
  Value<String> entity,
  Value<String> rowId,
  Value<DateTime> queuedUpdatedAt,
  Value<int> attempts,
  Value<String?> rejectedCode,
  Value<String?> rejectedMessage,
  Value<int> rowid,
});

class $$OutboxTableFilterComposer
    extends Composer<_$AppDatabase, $OutboxTable> {
  $$OutboxTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get entity => $composableBuilder(
    column: $table.entity,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get rowId => $composableBuilder(
    column: $table.rowId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get queuedUpdatedAt => $composableBuilder(
    column: $table.queuedUpdatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get rejectedCode => $composableBuilder(
    column: $table.rejectedCode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get rejectedMessage => $composableBuilder(
    column: $table.rejectedMessage,
    builder: (column) => ColumnFilters(column),
  );
}

class $$OutboxTableOrderingComposer
    extends Composer<_$AppDatabase, $OutboxTable> {
  $$OutboxTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get entity => $composableBuilder(
    column: $table.entity,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get rowId => $composableBuilder(
    column: $table.rowId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get queuedUpdatedAt => $composableBuilder(
    column: $table.queuedUpdatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get rejectedCode => $composableBuilder(
    column: $table.rejectedCode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get rejectedMessage => $composableBuilder(
    column: $table.rejectedMessage,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$OutboxTableAnnotationComposer
    extends Composer<_$AppDatabase, $OutboxTable> {
  $$OutboxTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get entity =>
      $composableBuilder(column: $table.entity, builder: (column) => column);

  GeneratedColumn<String> get rowId =>
      $composableBuilder(column: $table.rowId, builder: (column) => column);

  GeneratedColumn<DateTime> get queuedUpdatedAt => $composableBuilder(
    column: $table.queuedUpdatedAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get attempts =>
      $composableBuilder(column: $table.attempts, builder: (column) => column);

  GeneratedColumn<String> get rejectedCode => $composableBuilder(
    column: $table.rejectedCode,
    builder: (column) => column,
  );

  GeneratedColumn<String> get rejectedMessage => $composableBuilder(
    column: $table.rejectedMessage,
    builder: (column) => column,
  );
}

class $$OutboxTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $OutboxTable,
          OutboxData,
          $$OutboxTableFilterComposer,
          $$OutboxTableOrderingComposer,
          $$OutboxTableAnnotationComposer,
          $$OutboxTableCreateCompanionBuilder,
          $$OutboxTableUpdateCompanionBuilder,
          (OutboxData, BaseReferences<_$AppDatabase, $OutboxTable, OutboxData>),
          OutboxData,
          PrefetchHooks Function()
        > {
  $$OutboxTableTableManager(_$AppDatabase db, $OutboxTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$OutboxTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$OutboxTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$OutboxTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> entity = const Value.absent(),
                Value<String> rowId = const Value.absent(),
                Value<DateTime> queuedUpdatedAt = const Value.absent(),
                Value<int> attempts = const Value.absent(),
                Value<String?> rejectedCode = const Value.absent(),
                Value<String?> rejectedMessage = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => OutboxCompanion(
                entity: entity,
                rowId: rowId,
                queuedUpdatedAt: queuedUpdatedAt,
                attempts: attempts,
                rejectedCode: rejectedCode,
                rejectedMessage: rejectedMessage,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String entity,
                required String rowId,
                required DateTime queuedUpdatedAt,
                Value<int> attempts = const Value.absent(),
                Value<String?> rejectedCode = const Value.absent(),
                Value<String?> rejectedMessage = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => OutboxCompanion.insert(
                entity: entity,
                rowId: rowId,
                queuedUpdatedAt: queuedUpdatedAt,
                attempts: attempts,
                rejectedCode: rejectedCode,
                rejectedMessage: rejectedMessage,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$OutboxTable, OutboxData>(table),
                  BaseReferences<_$AppDatabase, $OutboxTable, OutboxData>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$OutboxTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $OutboxTable,
      OutboxData,
      $$OutboxTableFilterComposer,
      $$OutboxTableOrderingComposer,
      $$OutboxTableAnnotationComposer,
      $$OutboxTableCreateCompanionBuilder,
      $$OutboxTableUpdateCompanionBuilder,
      (OutboxData, BaseReferences<_$AppDatabase, $OutboxTable, OutboxData>),
      OutboxData,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$LocalMetaTableTableManager get localMeta =>
      $$LocalMetaTableTableManager(_db, _db.localMeta);
  $$AccountsTableTableManager get accounts =>
      $$AccountsTableTableManager(_db, _db.accounts);
  $$CategoriesTableTableManager get categories =>
      $$CategoriesTableTableManager(_db, _db.categories);
  $$TransactionsTableTableManager get transactions =>
      $$TransactionsTableTableManager(_db, _db.transactions);
  $$OutboxTableTableManager get outbox =>
      $$OutboxTableTableManager(_db, _db.outbox);
}
