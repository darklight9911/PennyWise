import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/widgets/app_icon.dart';
import '../../../core/router/routes.dart';
import '../../auth/application/auth_controller.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  Future<void> _confirmLogout(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text('You can log back in at any time.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Log out'),
          ),
        ],
      ),
    );
    if (ok == true) await ref.read(authControllerProvider.notifier).logout();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final user = auth is SignedIn ? auth.user : null;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          if (user != null)
            ListTile(
              leading: const AppIcon(HugeIcons.strokeRoundedUserCircle),
              title: Text(user.displayName),
              subtitle: Text(
                user.emailVerified
                    ? user.email
                    : '${user.email} · not confirmed',
              ),
            ),
          ListTile(
            leading: const AppIcon(HugeIcons.strokeRoundedMoney03),
            title: const Text('Main currency'),
            subtitle: Text(user?.baseCurrency ?? '—'),
          ),
          ListTile(
            leading: const AppIcon(HugeIcons.strokeRoundedClock01),
            title: const Text('Time zone'),
            subtitle: Text(user?.timezone ?? '—'),
          ),
          const Divider(),
          ListTile(
            leading: const AppIcon(HugeIcons.strokeRoundedWallet01),
            title: const Text('Accounts'),
            trailing: const AppIcon(HugeIcons.strokeRoundedArrowRight01),
            onTap: () => context.push(Routes.accounts),
          ),
          ListTile(
            leading: const AppIcon(HugeIcons.strokeRoundedGrid),
            title: const Text('Categories'),
            trailing: const AppIcon(HugeIcons.strokeRoundedArrowRight01),
            onTap: () => context.push(Routes.categories),
          ),
          const Divider(),
          ListTile(
            leading: const AppIcon(HugeIcons.strokeRoundedInformationCircle),
            title: const Text('About pennyWise'),
            subtitle: const Text('Version 0.1.0'),
          ),
          ListTile(
            leading: const AppIcon(HugeIcons.strokeRoundedLogout03),
            title: const Text('Log out'),
            onTap: () => _confirmLogout(context, ref),
          ),
        ],
      ),
    );
  }
}
