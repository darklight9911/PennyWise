import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import '../../ledger/application/ledger_providers.dart';
import '../data/fx_rates.dart';

/// Changes the main currency without an account: the phone converts every
/// amount itself with today's rates (signed in, the server does it).
///
/// Needs a connection once, for the rates. Throws an ApiException when
/// offline and a [StateError] when there is no rate for [from].
Future<void> changeGuestMainCurrency(
  WidgetRef ref, {
  required String from,
  required String to,
}) async {
  final rates = await ref.read(fxApiProvider).latest(to);
  final store = await ref.read(ledgerStoreProvider.future);
  await store.rebaseLocally(oldBase: from, newBase: to, rates: rates.rates);
  await ref.read(authControllerProvider.notifier).changeBaseCurrency(to);
}
