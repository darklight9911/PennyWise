import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'core/router/app_router.dart';
import 'core/router/deep_links.dart';
import 'core/theme/app_theme.dart';

class PennyWiseApp extends ConsumerWidget {
  const PennyWiseApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(deepLinkHandlerProvider); // start listening for email links
    return MaterialApp.router(
      title: 'pennyWise',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      // Dark theme arrives in Milestone 8; until then always light.
      themeMode: ThemeMode.light,
      scaffoldMessengerKey: ref.watch(scaffoldMessengerKeyProvider),
      routerConfig: ref.watch(routerProvider),
    );
  }
}
