import 'package:material_ui/material_ui.dart';

import '../../../core/widgets/empty_state.dart';

class TransactionsScreen extends StatelessWidget {
  const TransactionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Transactions')),
      body: const EmptyState(
        icon: Icons.receipt_long_outlined,
        title: 'No transactions yet',
        message:
            'Tap + on the home screen to add your first income or expense.',
      ),
    );
  }
}
