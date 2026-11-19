import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/local_database.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../auth/application/auth_controller.dart';
import '../currency/data/fx_rates.dart';
import '../ledger/application/ledger_providers.dart';
import '../ledger/data/ledger_store.dart';
import '../receipts/data/receipt_files.dart';
import '../receipts/data/receipt_sync.dart';
import 'sync_engine.dart';

/// What the UI shows about syncing.
class SyncStatus {
  const SyncStatus({
    this.syncing = false,
    this.lastSyncedAt,
    this.offline = false,
    this.error,
  });

  final bool syncing;
  final DateTime? lastSyncedAt;

  /// The last attempt could not reach the server (changes are kept).
  final bool offline;

  /// Any other failure, as a message for the user.
  final String? error;

  SyncStatus copyWith({
    bool? syncing,
    DateTime? lastSyncedAt,
    bool? offline,
    String? error,
  }) => SyncStatus(
    syncing: syncing ?? this.syncing,
    lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
    offline: offline ?? this.offline,
    error: error,
  );
}

/// Wait after a local change before syncing, so a burst of edits becomes
/// one sync. Tests set it to zero.
final syncDebounceProvider = Provider<Duration>(
  (ref) => const Duration(milliseconds: 1500),
);

/// Starts syncing when the user's ledger opens, after local changes and
/// when the app comes back to the foreground.
class SyncController extends Notifier<SyncStatus> {
  SyncEngine? _engine;
  LedgerStore? _store;
  Timer? _debounce;
  AppLifecycleListener? _lifecycle;
  void Function()? _removeCloseHook;

  @override
  SyncStatus build() {
    ref.onDispose(() {
      _debounce?.cancel();
      _lifecycle?.dispose();
      _detach();
    });
    ref.listen(
      ledgerStoreProvider,
      (_, _) => _reconcile(),
      fireImmediately: true,
    );
    // Without an account, or with an expired session, nothing is synced:
    // the data waits in the outbox until the user (re)signs in.
    ref.listen(authControllerProvider, (_, _) => _reconcile());

    _lifecycle = AppLifecycleListener(onResume: () => unawaited(syncNow()));
    return const SyncStatus();
  }

  void _reconcile() {
    final auth = ref.read(authControllerProvider);
    final user = auth is SignedIn && !auth.sessionExpired ? auth.user : null;
    // Only fresh data counts. In Riverpod 3 an error or loading state
    // still carries the PREVIOUS value, which after logout is a store on
    // the deleted database.
    final store = user != null
        ? switch (ref.read(ledgerStoreProvider)) {
            AsyncData(:final value) => value,
            _ => null,
          }
        : null;
    if (store != null && identical(store.db, _engine?.db)) return;
    _detach();
    if (store == null) return;

    _store = store;
    final engine = _engine = SyncEngine(
      db: store.db,
      dio: ref.read(dioProvider),
      receiptFiles: ref.read(receiptFilesProvider),
    );
    // Before the database closes (logout, other user), stop syncing:
    // the request in flight is cancelled and the run ends first.
    _removeCloseHook = ref.read(localDatabaseProvider).addCloseHook(() async {
      _debounce?.cancel();
      await engine.stop();
    });
    engine.onMergeGuest = () => _mergeGuest(store, user!.baseCurrency);
    store.onLocalWrite = _scheduleSync;
    unawaited(syncNow());
  }

  /// Joins this phone's guest data into the account, converting budgets
  /// and goals when the main currencies differ (at today's rate, if known).
  Future<void> _mergeGuest(LedgerStore store, String accountCurrency) async {
    final from = await store.db.readMeta(LocalDatabase.mergeFromCurrencyKey);
    String? rate;
    if (from != null && from != accountCurrency) {
      try {
        rate = (await ref.read(fxApiProvider).latest(from))
            .rates[accountCurrency];
      } on ApiException {
        rate = null; // no rate known: amounts are kept as they are
      }
    }
    await store.mergeGuestData(
      fromCurrency: from,
      toCurrency: accountCurrency,
      rate: rate,
    );
    await store.db.deleteMeta(LocalDatabase.mergeFromCurrencyKey);
  }

  /// Forgets the current engine (it stops when its database closes).
  void _detach() {
    _debounce?.cancel();
    _removeCloseHook?.call();
    _removeCloseHook = null;
    final old = _engine;
    _engine = null;
    _store = null;
    if (old != null) unawaited(old.stop());
  }

  void _scheduleSync() {
    _debounce?.cancel();
    _debounce = Timer(
      ref.read(syncDebounceProvider),
      () => unawaited(syncNow()),
    );
  }

  /// Syncs now. Never throws: the result is in [state].
  Future<void> syncNow() async {
    final engine = _engine;
    if (engine == null) return;
    _set(state.copyWith(syncing: true, error: state.error));
    try {
      // Bills that came due (e.g. while the phone was off) are created
      // first, with the server's fixed ids, so this sync uploads them.
      await _store?.generateDueBills(DateTime.now());
      await engine.sync();
      if (engine.isStopped || !identical(engine, _engine)) return;
      // Photos go after the data, so their transactions exist on the server.
      await receiptSyncFor(ref, engine.db).run();
      if (engine.isStopped || !identical(engine, _engine)) return;
      _set(SyncStatus(lastSyncedAt: DateTime.now()));
    } on Object catch (e, st) {
      // The session ended (logout, other user) while this sync ran: its
      // database is gone. Nothing to report.
      if (engine.isStopped || !identical(engine, _engine)) return;
      if (e is ApiException) {
        _set(
          state.copyWith(
            syncing: false,
            offline: e.isNetworkError,
            error: e.isNetworkError ? null : e.message,
          ),
        );
      } else {
        _set(
          state.copyWith(
            syncing: false,
            offline: false,
            error: userMessage(e, st),
          ),
        );
      }
    }
  }

  void _set(SyncStatus s) {
    if (ref.mounted) state = s;
  }
}

final syncControllerProvider = NotifierProvider<SyncController, SyncStatus>(
  SyncController.new,
);
