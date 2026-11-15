import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pennywise/core/network/api_client.dart';
import 'package:pennywise/features/auth/application/auth_controller.dart';

import '../../support/test_app.dart';

/// Who may see the data in the encrypted local database.
void main() {
  late TestHarness h;
  late ProviderContainer c;
  AuthController auth() => c.read(authControllerProvider.notifier);

  setUp(() async {
    h = TestHarness();
    h.backend.seedUser('ann@example.com', 'ann-password-1');
    h.backend.seedUser('bo@example.com', 'bo-password-12');
    c = h.container();
    addTearDown(c.dispose);
    c.read(authControllerProvider); // start the controller
    await Future<void>.delayed(Duration.zero);
  });

  String idOf(String email) => h.backend.users[email]!['id'] as String;

  test('logging in claims the local data for that user', () async {
    await auth().login('ann@example.com', 'ann-password-1');
    expect(await h.local.owner(), idOf('ann@example.com'));
  });

  test('logging out wipes the local data', () async {
    await auth().login('ann@example.com', 'ann-password-1');
    await auth().logout();
    expect(h.local.wipeCount, 1);
    expect(await h.local.owner(), isNull);
  });

  test(
    'the same user back after a session expiry keeps their local data',
    () async {
      await auth().login('ann@example.com', 'ann-password-1');
      await (await h.local.database).writeMeta('unsynced', 'coffee 3.50');

      await c.read(sessionManagerProvider).clear(); // session expired
      await auth().login('ann@example.com', 'ann-password-1');

      expect(h.local.wipeCount, 0);
      expect(
        await (await h.local.database).readMeta('unsynced'),
        'coffee 3.50',
      );
    },
  );

  test("another user never sees the previous user's data", () async {
    await auth().login('ann@example.com', 'ann-password-1');
    await (await h.local.database).writeMeta('unsynced', 'ann private note');

    await c.read(sessionManagerProvider).clear(); // expired, not logged out
    await auth().login('bo@example.com', 'bo-password-12');

    expect(h.local.wipeCount, 1);
    expect(await (await h.local.database).readMeta('unsynced'), isNull);
    expect(await h.local.owner(), idOf('bo@example.com'));
  });

  test(
    'restoring a saved session claims the data for the cached user',
    () async {
      await auth().login('ann@example.com', 'ann-password-1');
      c.dispose();

      // App restart with the same storage.
      final h2 = TestHarness(backend: h.backend, store: h.store);
      final c2 = h2.container();
      addTearDown(c2.dispose);
      c2.read(authControllerProvider);
      for (
        var i = 0;
        i < 20 && c2.read(authControllerProvider) is AuthLoading;
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(c2.read(authControllerProvider), isA<SignedIn>());
      expect(await h2.local.owner(), idOf('ann@example.com'));
    },
  );
}
