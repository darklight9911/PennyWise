import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/local_database.dart';
import '../../auth/application/auth_controller.dart';
import '../data/ledger_store.dart';

/// The signed-in user's id, or null.
final signedInUserIdProvider = Provider<String?>((ref) {
  final auth = ref.watch(authControllerProvider);
  return auth is SignedIn ? auth.user.id : null;
});

/// The ledger of the signed-in user. Rebuilt when another user signs in,
/// so a screen can never read the previous user's database.
final ledgerStoreProvider = FutureProvider<LedgerStore>((ref) async {
  final userId = ref.watch(signedInUserIdProvider);
  if (userId == null) throw StateError('not signed in');
  final db = await ref.watch(localDatabaseProvider).claimFor(userId);
  return LedgerStore(db);
});
