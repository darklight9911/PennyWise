import 'package:material_ui/material_ui.dart';

import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/panda_mascot.dart';

class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reports')),
      body: const EmptyState(
        mascot: PandaMood.thinking,
        icon: HugeIcons.strokeRoundedPieChart,
        title: 'Nothing to show yet',
        message: 'Charts appear here once you have a few transactions.',
      ),
    );
  }
}
