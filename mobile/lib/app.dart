import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'core/router/app_router.dart';
import 'core/router/deep_links.dart';
import 'core/theme/app_theme.dart';
import 'features/app_lock/presentation/lock_gate.dart';
import 'features/settings/application/theme_mode.dart';
import 'features/sync/sync_controller.dart';

class PennyWiseApp extends ConsumerWidget {
  const PennyWiseApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(deepLinkHandlerProvider); // start listening for email links
    ref.watch(syncControllerProvider); // sync at login, on changes, on resume
    return MaterialApp.router(
      title: 'pennyWise',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ref.watch(themeModeProvider),
      scaffoldMessengerKey: ref.watch(scaffoldMessengerKeyProvider),
      routerConfig: ref.watch(routerProvider),
      // The app lock sits above every screen.
      builder: (context, child) => LockGate(child: child ?? const SizedBox()),
    );
  }
}
