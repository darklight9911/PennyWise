import 'package:material_ui/material_ui.dart';

import '../../../core/widgets/panda_mascot.dart';
import 'auth_widgets.dart';

/// Shown for a moment while the saved session is read.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PandaMascot(mood: PandaMood.thinking, size: 160),
            SizedBox(height: 16),
            BrandMark(),
            SizedBox(height: 24),
            SizedBox.square(
              dimension: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ],
        ),
      ),
    );
  }
}
