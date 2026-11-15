import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../features/auth/application/auth_controller.dart';
import '../network/api_exception.dart';
import 'app_router.dart';

/// Links the app is opened with, e.g. pennywise://verify-email?token=...
/// (the plugin also emits the link that cold-started the app).
final incomingLinksProvider = Provider<Stream<Uri>>(
  (ref) => AppLinks().uriLinkStream,
);

/// Shows snack bars from outside any screen (e.g. after a link is handled).
final scaffoldMessengerKeyProvider =
    Provider<GlobalKey<ScaffoldMessengerState>>(
      (ref) => GlobalKey<ScaffoldMessengerState>(),
    );

/// Handles links from our emails. Started once by the app widget.
final deepLinkHandlerProvider = Provider<void>((ref) {
  final sub = ref.watch(incomingLinksProvider).listen((uri) {
    unawaited(handleDeepLink(ref, uri));
  });
  ref.onDispose(sub.cancel);
});

/// Routes one incoming link. Unknown links are ignored.
Future<void> handleDeepLink(Ref ref, Uri uri) async {
  if (uri.scheme != 'pennywise') return;
  final token = uri.queryParameters['token'] ?? '';

  switch (uri.host) {
    case 'reset-password':
      ref.read(routerProvider).go(Routes.resetPasswordWith(token));
    case 'verify-email':
      final messenger = ref.read(scaffoldMessengerKeyProvider).currentState;
      try {
        await ref.read(authControllerProvider.notifier).verifyEmail(token);
        messenger?.showSnackBar(
          const SnackBar(content: Text('Email confirmed. Thank you!')),
        );
      } on ApiException catch (e) {
        messenger?.showSnackBar(
          SnackBar(
            content: Text(
              e.code == 'invalid_link'
                  ? 'This confirmation link has expired or was already used.'
                  : e.message,
            ),
          ),
        );
      }
  }
}
