import 'package:drift/drift.dart';

/// Columns every synced table has (see PLAN.md section 3).
mixin SyncedColumns on Table {
  /// Client-generated UUID v7.
  TextColumn get id => text()();

  /// When this row was last edited (on any device). The newer edit wins.
  DateTimeColumn get updatedAt => dateTime()();

  /// Soft delete: the row stays so the deletion can sync.
  DateTimeColumn get deletedAt => dateTime().nullable()();

  /// The server's version of this row; null until it reached the server.
  IntColumn get serverVersion => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class Accounts extends Table with SyncedColumns {
  TextColumn get name => text().withLength(min: 1, max: 60)();

  /// cash, bank, card, ewallet, savings, other
  TextColumn get type => text()();
  TextColumn get currency => text().withLength(min: 3, max: 3)();
  IntColumn get openingBalanceMinor =>
      integer().withDefault(const Constant(0))();
  TextColumn get icon => text().withDefault(const Constant(''))();
  TextColumn get color => text().withDefault(const Constant(''))();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
}

class Categories extends Table with SyncedColumns {
  TextColumn get parentId => text().nullable()();
  TextColumn get name => text().withLength(min: 1, max: 40)();

  /// income or expense
  TextColumn get kind => text()();
  TextColumn get icon => text().withDefault(const Constant(''))();
  TextColumn get color => text().withDefault(const Constant(''))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
}

/// Money in or out. Data class named MoneyTransaction to avoid clashing
/// with database "transactions".
@DataClassName('MoneyTransaction')
class Transactions extends Table with SyncedColumns {
  TextColumn get accountId => text()();
  TextColumn get categoryId => text().nullable()();

  /// income, expense or transfer
  TextColumn get kind => text()();

  /// Always positive; the kind says in or out.
  IntColumn get amountMinor => integer()();
  TextColumn get currency => text().withLength(min: 3, max: 3)();

  /// Set by the server (same currency: rate 1). Null until known.
  IntColumn get amountBaseMinor => integer().nullable()();
  TextColumn get fxRateToBase => text().nullable()();

  TextColumn get transferAccountId => text().nullable()();
  IntColumn get transferAmountMinor => integer().nullable()();

  DateTimeColumn get occurredAt => dateTime()();

  /// YYYY-MM-DD where the user was. Months and budgets use this.
  TextColumn get localDate => text().withLength(min: 10, max: 10)();
  TextColumn get note => text().withDefault(const Constant(''))();
}

/// Rows changed on this phone that the server has not confirmed yet.
/// One entry per row: many edits while offline send only the latest state.
class Outbox extends Table {
  /// account, category or transaction
  TextColumn get entity => text()();
  TextColumn get rowId => text()();

  /// The row's updatedAt when it was queued. Used to tell whether the row
  /// was edited again while a push was on its way.
  DateTimeColumn get queuedUpdatedAt => dateTime()();
  IntColumn get attempts => integer().withDefault(const Constant(0))();

  /// Set when the server rejected the change; it is not retried as-is.
  TextColumn get rejectedCode => text().nullable()();
  TextColumn get rejectedMessage => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {entity, rowId};
}

/// A spending limit per week or month, in the user's main currency.
/// No category = all spending.
class Budgets extends Table with SyncedColumns {
  TextColumn get categoryId => text().nullable()();
  IntColumn get amountMinor => integer()();

  /// weekly or monthly
  TextColumn get period => text()();

  /// Alert levels in percent, comma separated, e.g. "80,100".
  TextColumn get alertThresholds =>
      text().withDefault(const Constant('80,100'))();
}
