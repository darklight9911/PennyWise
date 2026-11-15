import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'app.dart';
import 'core/widgets/panda_mascot.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final animatePanda = await initPandaAnimations();
  runApp(
    ProviderScope(
      overrides: [pandaAnimationsProvider.overrideWithValue(animatePanda)],
      child: const PennyWiseApp(),
    ),
  );
}
