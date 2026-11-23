import 'dart:async';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart';

import '../../core/database/local_database.dart';
import '../../core/database/app_database.dart';
import '../../core/network/api_exception.dart';
import '../ledger/data/ledger_store.dart';
import '../receipts/data/receipt_files.dart';

/// Result of one sync run.
class SyncReport {
  const SyncReport({this.pushed = 0, this.rejected = 0, this.pulled = 0});
  final int pushed;
  final int rejected;
  final int pulled;
}

/// Moves changes between this phone and the server (PLAN.md section 3).
///
/// Push: the outbox, as the rows look NOW (many edits = one change).
/// Pull: everything after the saved cursor. A row with a local edit still
/// waiting to be pushed is not overwritten: that edit is newer, and the
/// server decides once it arrives (newer edit wins).
class SyncEngine {
  SyncEngine({required this.db, required Dio dio, this.receiptFiles})
    : _dio = dio; // ignore: prefer_initializing_formals

  final AppDatabase db;
  final Dio _dio;

  /// Deletes the photo of a receipt removed on another phone.
  final ReceiptFiles? receiptFiles;

  static const cursorKey = 'sync_cursor';
  static const _batchSize = 500; // server maximum per push

  Future<SyncReport>? _running;
  bool _again = false;
  bool _stopped = false;
  CancelToken? _cancel;

  /// Joins guest data into the account (see [LedgerStore.mergeGuestData]).
  /// Called once, between pulling the account's rows and pushing.
  Future<void> Function()? onMergeGuest;

  /// True once [stop] was called (logout or user switch).
  bool get isStopped => _stopped;

  /// Stops for good: cancels a request in flight and waits until the
  /// running sync has ended, so the database can be closed safely.
  Future<void> stop() async {
    _stopped = true;
    _again = false;
    _cancel?.cancel('sync stopped');
    final running = _running;
    if (running != null) {
      await running.then<void>((_) {}, onError: (Object _) {});
    }
  }

  /// Runs a sync. While one runs, further calls wait for it, and exactly
  /// one more run follows (changes made meanwhile are not missed).
  Future<SyncReport> sync() {
    if (_stopped) return Future.value(const SyncReport());
    if (_running != null) {
      _again = true;
      return _running!;
    }
    return _running = _loop().whenComplete(() => _running = null);
  }

  Future<SyncReport> _loop() async {
    var report = await _once();
    while (_again && !_stopped) {
      _again = false;
      final next = await _once();
      report = SyncReport(
        pushed: report.pushed + next.pushed,
        rejected: report.rejected + next.rejected,
        pulled: report.pulled + next.pulled,
      );
    }
    return report;
  }

  Future<SyncReport> _once() async {
    _cancel = CancelToken();
    var pulledFirst = 0;
    if (await db.readMeta(LocalDatabase.mergePendingKey) != null) {
      // Data made without an account just joined this account: fetch the
      // account's rows first, join duplicates, then upload the rest.
      pulledFirst = await _pullAll();
      _checkStopped();
      await onMergeGuest?.call();
      await db.deleteMeta(LocalDatabase.mergePendingKey);
    }
    final (pushed, rejected) = await _pushAll();
    _checkStopped();
    final pulled = await _pullAll();
    return SyncReport(
      pushed: pushed,
      rejected: rejected,
      pulled: pulledFirst + pulled,
    );
  }

  // -------------------------------------------------------------------- push

  Future<(int, int)> _pushAll() async {
    var pushed = 0, rejected = 0;
    // Bounded: rows edited during every single push could otherwise keep
    // the loop going; whatever is left goes with the next sync.
    for (var round = 0; round < 20; round++) {
      final batch =
          await (db.select(db.outbox)
                ..where((o) => o.rejectedCode.isNull())
                ..limit(_batchSize))
              .get();
      if (batch.isEmpty) return (pushed, rejected);

      final changes = <Map<String, dynamic>>[];
      final sent = <(String, String), DateTime>{};
      for (final entry in batch) {
        final change = await _changeFor(entry.entity, entry.rowId);
        if (change == null) {
          await _dropEntry(entry.entity, entry.rowId); // row vanished
          continue;
        }
        changes.add(change.json);
        sent[(entry.entity, entry.rowId)] = change.updatedAt;
      }
      if (changes.isEmpty) continue;

      final Map<String, dynamic> body;
      try {
        final res = await _dio.post<Map<String, dynamic>>(
          '/v1/sync/push',
          data: {'changes': changes},
          cancelToken: _cancel,
        );
        body = res.data!;
      } on DioException catch (e) {
        throw ApiException.fromDio(e); // offline etc.: the outbox stays
      }
      _checkStopped();

      await db.transaction(() async {
        for (final r
            in (body['results'] as List).cast<Map<String, dynamic>>()) {
          final key = (r['entity'] as String, r['id'] as String);
          final at = sent[key];
          if (at == null) continue;
          final where =
              db.outbox.entity.equals(key.$1) &
              db.outbox.rowId.equals(key.$2) &
              // Only if the row was not edited again while this push was on its way.
              db.outbox.queuedUpdatedAt.equals(at);
          if (r['status'] == 'rejected') {
            rejected++;
            final err = (r['error'] as Map?)?.cast<String, dynamic>() ?? {};
            await (db.update(db.outbox)..where((_) => where)).write(
              OutboxCompanion(
                rejectedCode: Value(err['code'] as String? ?? 'rejected'),
                rejectedMessage: Value(err['message'] as String? ?? ''),
              ),
            );
          } else {
            pushed++; // applied, or the server already had it (stale)
            await (db.delete(db.outbox)..where((_) => where)).go();
          }
        }
      });
      if (batch.length < _batchSize) return (pushed, rejected);
    }
    return (pushed, rejected);
  }

  Future<void> _dropEntry(String entity, String id) => (db.delete(
    db.outbox,
  )..where((o) => o.entity.equals(entity) & o.rowId.equals(id))).go();

  Future<({Map<String, dynamic> json, DateTime updatedAt})?> _changeFor(
    String entity,
    String id,
  ) async {
    Map<String, dynamic> wrap(
      DateTime updatedAt,
      DateTime? deletedAt,
      Map<String, dynamic> data,
    ) => {
      'entity': entity,
      'id': id,
      'updated_at': _iso(updatedAt),
      'deleted_at': deletedAt == null ? null : _iso(deletedAt),
      'data': data,
    };
    switch (entity) {
      case Entity.account:
        final a = await (db.select(
          db.accounts,
        )..where((x) => x.id.equals(id))).getSingleOrNull();
        if (a == null) return null;
        return (
          updatedAt: a.updatedAt,
          json: wrap(a.updatedAt, a.deletedAt, {
            'name': a.name,
            'type': a.type,
            'currency': a.currency,
            'opening_balance_minor': a.openingBalanceMinor,
            'icon': a.icon,
            'color': a.color,
            'archived': a.archived,
            'sort_order': a.sortOrder,
          }),
        );
      case Entity.category:
        final c = await (db.select(
          db.categories,
        )..where((x) => x.id.equals(id))).getSingleOrNull();
        if (c == null) return null;
        return (
          updatedAt: c.updatedAt,
          json: wrap(c.updatedAt, c.deletedAt, {
            'parent_id': c.parentId,
            'name': c.name,
            'kind': c.kind,
            'icon': c.icon,
            'color': c.color,
            'sort_order': c.sortOrder,
          }),
        );
      case Entity.transaction:
        final t = await (db.select(
          db.transactions,
        )..where((x) => x.id.equals(id))).getSingleOrNull();
        if (t == null) return null;
        return (
          updatedAt: t.updatedAt,
          json: wrap(t.updatedAt, t.deletedAt, {
            'account_id': t.accountId,
            'category_id': t.categoryId,
            'kind': t.kind,
            'amount_minor': t.amountMinor,
            'currency': t.currency,
            'transfer_account_id': t.transferAccountId,
            'transfer_amount_minor': t.transferAmountMinor,
            'occurred_at': _iso(t.occurredAt),
            'local_date': t.localDate,
            'note': t.note,
            'recurring_id': t.recurringId,
            'occurrence_date': t.occurrenceDate,
            // A rate the user typed; daily rates are the server's job.
            // Only when set, so servers without dues still take the rest.
            if (t.dueId != null) 'due_id': t.dueId,
            if (t.fxRateSource == 'manual' && t.fxRateToBase != null)
              'manual_fx_rate': t.fxRateToBase,
          }),
        );
      case Entity.budget:
        final b = await (db.select(
          db.budgets,
        )..where((x) => x.id.equals(id))).getSingleOrNull();
        if (b == null) return null;
        return (
          updatedAt: b.updatedAt,
          json: wrap(b.updatedAt, b.deletedAt, {
            'category_id': b.categoryId,
            'amount_minor': b.amountMinor,
            'period': b.period,
            'alert_thresholds': parseLevels(b.alertThresholds),
          }),
        );
      case Entity.recurringRule:
        final r = await (db.select(
          db.recurringRules,
        )..where((x) => x.id.equals(id))).getSingleOrNull();
        if (r == null) return null;
        return (
          updatedAt: r.updatedAt,
          json: wrap(r.updatedAt, r.deletedAt, {
            'kind': r.kind,
            'account_id': r.accountId,
            'category_id': r.categoryId,
            'amount_minor': r.amountMinor,
            'currency': r.currency,
            'note': r.note,
            'frequency': r.frequency,
            'every': r.every,
            'start_date': r.startDate,
            'end_date': r.endDate,
            'remind_days_before': r.remindDaysBefore,
            'active': r.active,
          }),
        );
      case Entity.due:
        final x = await (db.select(
          db.dues,
        )..where((r) => r.id.equals(id))).getSingleOrNull();
        if (x == null) return null;
        return (
          updatedAt: x.updatedAt,
          json: wrap(x.updatedAt, x.deletedAt, {
            'direction': x.direction,
            'kind': x.kind,
            'person': x.person,
            'amount_minor': x.amountMinor,
            'currency': x.currency,
            'account_id': x.accountId,
            'category_id': x.categoryId,
            'start_date': x.startDate,
            'due_date': x.dueDate,
            'remind_days_before': x.remindDaysBefore,
            'note': x.note,
            'closed_at': x.closedAt == null ? null : _iso(x.closedAt!),
          }),
        );
      case Entity.goal:
        final g = await (db.select(
          db.goals,
        )..where((x) => x.id.equals(id))).getSingleOrNull();
        if (g == null) return null;
        return (
          updatedAt: g.updatedAt,
          json: wrap(g.updatedAt, g.deletedAt, {
            'name': g.name,
            'target_minor': g.targetMinor,
            'deadline': g.deadline,
            'icon': g.icon,
            'color': g.color,
            'archived': g.archived,
          }),
        );
      case Entity.goalContribution:
        final c = await (db.select(
          db.goalContributions,
        )..where((x) => x.id.equals(id))).getSingleOrNull();
        if (c == null) return null;
        return (
          updatedAt: c.updatedAt,
          json: wrap(c.updatedAt, c.deletedAt, {
            'goal_id': c.goalId,
            'amount_minor': c.amountMinor,
            'local_date': c.localDate,
            'note': c.note,
          }),
        );
    }
    return null;
  }

  // -------------------------------------------------------------------- pull

  Future<int> _pullAll() async {
    var pulled = 0;
    while (true) {
      final since = int.tryParse(await db.readMeta(cursorKey) ?? '') ?? 0;
      final Map<String, dynamic> body;
      try {
        final res = await _dio.get<Map<String, dynamic>>(
          '/v1/sync/pull',
          queryParameters: {'since': since},
          cancelToken: _cancel,
        );
        body = res.data!;
      } on DioException catch (e) {
        throw ApiException.fromDio(e);
      }
      _checkStopped();
      final changes = (body['changes'] as List).cast<Map<String, dynamic>>();

      await db.transaction(() async {
        for (final c in changes) {
          if (await _applyRemote(c)) pulled++;
        }
        // Cursor moves only together with the rows it covers.
        await db.writeMeta(cursorKey, '${body['cursor']}');
      });
      if (body['has_more'] != true) return pulled;
    }
  }

  /// Saves one row from the server. Returns false if a newer local edit
  /// is still waiting to be pushed (that edit is kept).
  Future<bool> _applyRemote(Map<String, dynamic> c) async {
    final entity = c['entity'] as String;
    final id = c['id'] as String;
    final pending =
        await (db.select(db.outbox)
              ..where((o) => o.entity.equals(entity) & o.rowId.equals(id)))
            .getSingleOrNull();
    if (pending != null && pending.rejectedCode == null) return false;
    if (pending != null) {
      await _dropEntry(entity, id); // server copy replaces a rejected edit
    }

    final d = (c['data'] as Map).cast<String, dynamic>();
    final updatedAt = DateTime.parse(c['updated_at'] as String);
    final deletedAt = c['deleted_at'] == null
        ? null
        : DateTime.parse(c['deleted_at'] as String);
    final version = c['version'] as int;

    switch (entity) {
      case Entity.account:
        await db
            .into(db.accounts)
            .insertOnConflictUpdate(
              AccountsCompanion.insert(
                id: id,
                name: d['name'] as String,
                type: d['type'] as String,
                currency: d['currency'] as String,
                openingBalanceMinor: Value(d['opening_balance_minor'] as int),
                icon: Value(d['icon'] as String? ?? ''),
                color: Value(d['color'] as String? ?? ''),
                archived: Value(d['archived'] as bool? ?? false),
                sortOrder: Value(d['sort_order'] as int? ?? 0),
                updatedAt: updatedAt,
                deletedAt: Value(deletedAt),
                serverVersion: Value(version),
              ),
            );
      case Entity.category:
        await db
            .into(db.categories)
            .insertOnConflictUpdate(
              CategoriesCompanion.insert(
                id: id,
                parentId: Value(d['parent_id'] as String?),
                name: d['name'] as String,
                kind: d['kind'] as String,
                icon: Value(d['icon'] as String? ?? ''),
                color: Value(d['color'] as String? ?? ''),
                sortOrder: Value(d['sort_order'] as int? ?? 0),
                updatedAt: updatedAt,
                deletedAt: Value(deletedAt),
                serverVersion: Value(version),
              ),
            );
      case Entity.transaction:
        await db
            .into(db.transactions)
            .insertOnConflictUpdate(
              TransactionsCompanion.insert(
                id: id,
                accountId: d['account_id'] as String,
                categoryId: Value(d['category_id'] as String?),
                kind: d['kind'] as String,
                amountMinor: d['amount_minor'] as int,
                currency: d['currency'] as String,
                amountBaseMinor: Value(d['amount_base_minor'] as int?),
                fxRateToBase: Value(d['fx_rate_to_base'] as String?),
                fxRateSource: Value(d['fx_rate_source'] as String?),
                dueId: Value(d['due_id'] as String?),
                transferAccountId: Value(d['transfer_account_id'] as String?),
                transferAmountMinor: Value(d['transfer_amount_minor'] as int?),
                occurredAt: DateTime.parse(d['occurred_at'] as String),
                localDate: d['local_date'] as String,
                note: Value(d['note'] as String? ?? ''),
                recurringId: Value(d['recurring_id'] as String?),
                occurrenceDate: Value(d['occurrence_date'] as String?),
                updatedAt: updatedAt,
                deletedAt: Value(deletedAt),
                serverVersion: Value(version),
              ),
            );
      case Entity.budget:
        await db
            .into(db.budgets)
            .insertOnConflictUpdate(
              BudgetsCompanion.insert(
                id: id,
                categoryId: Value(d['category_id'] as String?),
                amountMinor: d['amount_minor'] as int,
                period: d['period'] as String,
                alertThresholds: Value(
                  ((d['alert_thresholds'] as List?) ?? const [80, 100]).join(
                    ',',
                  ),
                ),
                updatedAt: updatedAt,
                deletedAt: Value(deletedAt),
                serverVersion: Value(version),
              ),
            );
      case Entity.recurringRule:
        await db
            .into(db.recurringRules)
            .insertOnConflictUpdate(
              RecurringRulesCompanion.insert(
                id: id,
                kind: d['kind'] as String,
                accountId: d['account_id'] as String,
                categoryId: d['category_id'] as String,
                amountMinor: d['amount_minor'] as int,
                currency: d['currency'] as String,
                note: Value(d['note'] as String? ?? ''),
                frequency: d['frequency'] as String,
                every: Value(d['every'] as int? ?? 1),
                startDate: d['start_date'] as String,
                endDate: Value(d['end_date'] as String?),
                remindDaysBefore: Value(d['remind_days_before'] as int? ?? 0),
                active: Value(d['active'] as bool? ?? true),
                updatedAt: updatedAt,
                deletedAt: Value(deletedAt),
                serverVersion: Value(version),
              ),
            );
      case Entity.due:
        await db
            .into(db.dues)
            .insertOnConflictUpdate(
              DuesCompanion.insert(
                id: id,
                direction: d['direction'] as String,
                kind: d['kind'] as String,
                person: d['person'] as String,
                amountMinor: d['amount_minor'] as int,
                currency: d['currency'] as String,
                accountId: Value(d['account_id'] as String?),
                categoryId: Value(d['category_id'] as String?),
                startDate: d['start_date'] as String,
                dueDate: Value(d['due_date'] as String?),
                remindDaysBefore: Value(d['remind_days_before'] as int?),
                note: Value(d['note'] as String? ?? ''),
                closedAt: Value(
                  d['closed_at'] == null
                      ? null
                      : DateTime.parse(d['closed_at'] as String),
                ),
                updatedAt: updatedAt,
                deletedAt: Value(deletedAt),
                serverVersion: Value(version),
              ),
            );
      case Entity.goal:
        await db
            .into(db.goals)
            .insertOnConflictUpdate(
              GoalsCompanion.insert(
                id: id,
                name: d['name'] as String,
                targetMinor: d['target_minor'] as int,
                deadline: Value(d['deadline'] as String?),
                icon: Value(d['icon'] as String? ?? ''),
                color: Value(d['color'] as String? ?? ''),
                archived: Value(d['archived'] as bool? ?? false),
                updatedAt: updatedAt,
                deletedAt: Value(deletedAt),
                serverVersion: Value(version),
              ),
            );
      case Entity.goalContribution:
        await db
            .into(db.goalContributions)
            .insertOnConflictUpdate(
              GoalContributionsCompanion.insert(
                id: id,
                goalId: d['goal_id'] as String,
                amountMinor: d['amount_minor'] as int,
                localDate: d['local_date'] as String,
                note: Value(d['note'] as String? ?? ''),
                updatedAt: updatedAt,
                deletedAt: Value(deletedAt),
                serverVersion: Value(version),
              ),
            );
      case Entity.receipt:
        final local = await (db.select(
          db.receipts,
        )..where((r) => r.id.equals(id))).getSingleOrNull();
        if (deletedAt != null) {
          if (local?.localPath != null) {
            await receiptFiles?.delete(local!.localPath!);
          }
          await (db.delete(db.receipts)..where((r) => r.id.equals(id))).go();
        } else if (local == null) {
          // Another phone's photo: the file is fetched when shown.
          await db
              .into(db.receipts)
              .insert(
                ReceiptsCompanion.insert(
                  id: id,
                  transactionId: d['transaction_id'] as String,
                  contentType: d['content_type'] as String,
                  sizeBytes: d['size_bytes'] as int,
                  status: 'uploaded',
                  createdAt: updatedAt,
                ),
              );
        } else if (local.deletedAt == null) {
          await (db.update(db.receipts)..where((r) => r.id.equals(id))).write(
            const ReceiptsCompanion(status: Value('uploaded')),
          );
        }
      default:
        return false; // a newer server may send types this app does not know yet
    }
    return true;
  }

  void _checkStopped() {
    if (_stopped) throw const SyncStoppedException();
  }

  static String _iso(DateTime t) => t.toUtc().toIso8601String();
}

/// The sync was stopped (logout or user switch) while it ran.
class SyncStoppedException implements Exception {
  const SyncStoppedException();
}
