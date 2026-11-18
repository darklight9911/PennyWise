import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/widgets/app_icon.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/application/auth_controller.dart';
import '../../currency/presentation/main_currency_dialog.dart';
import '../application/theme_mode.dart';
import 'delete_account_dialog.dart';
import 'verify_email_card.dart';

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

  Future<void> _pickTheme(BuildContext context, WidgetRef ref) async {
    final picked = await showDialog<ThemeMode>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Appearance'),
        children: [
          RadioGroup<ThemeMode>(
            groupValue: ref.read(themeModeProvider),
            onChanged: (m) => Navigator.pop(context, m),
            child: Column(
              children: [
                for (final m in ThemeMode.values)
                  RadioListTile<ThemeMode>(
                    value: m,
                    title: Text(themeModeLabel(m)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    if (picked != null) await ref.read(themeModeProvider.notifier).set(picked);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final user = auth is SignedIn ? auth.user : null;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          if (user != null && !user.emailVerified)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Spacing.lg,
                Spacing.sm,
                Spacing.lg,
                Spacing.sm,
              ),
              child: VerifyEmailCard(user: user),
            ),
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
            subtitle: Text(
              user == null
                  ? '—'
                  : user.recalculating
                  ? '${user.baseCurrency} · converting totals…'
                  : user.baseCurrency,
            ),
            trailing: user == null
                ? null
                : const AppIcon(HugeIcons.strokeRoundedArrowRight01),
            onTap: user == null || user.recalculating
                ? null
                : () => showMainCurrencyDialog(context, user.baseCurrency),
          ),
          ListTile(
            leading: const AppIcon(HugeIcons.strokeRoundedClock01),
            title: const Text('Time zone'),
            subtitle: Text(user?.timezone ?? '—'),
          ),
          ListTile(
            leading: const AppIcon(HugeIcons.strokeRoundedPaintBrush02),
            title: const Text('Appearance'),
            subtitle: Text(themeModeLabel(ref.watch(themeModeProvider))),
            trailing: const AppIcon(HugeIcons.strokeRoundedArrowRight01),
            onTap: () => _pickTheme(context, ref),
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
          ListTile(
            leading: const AppIcon(HugeIcons.strokeRoundedTarget02),
            title: const Text('Budgets'),
            trailing: const AppIcon(HugeIcons.strokeRoundedArrowRight01),
            onTap: () => context.push(Routes.budgets),
          ),
          ListTile(
            leading: const AppIcon(HugeIcons.strokeRoundedPiggyBank),
            title: const Text('Goals'),
            trailing: const AppIcon(HugeIcons.strokeRoundedArrowRight01),
            onTap: () => context.push(Routes.goals),
          ),
          ListTile(
            leading: const AppIcon(HugeIcons.strokeRoundedRepeat),
            title: const Text('Recurring'),
            trailing: const AppIcon(HugeIcons.strokeRoundedArrowRight01),
            onTap: () => context.push(Routes.recurring),
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
          if (user != null)
            ListTile(
              leading: AppIcon(
                HugeIcons.strokeRoundedDelete02,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text(
                'Delete account',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              onTap: () => showDeleteAccountDialog(
                context,
                hasPassword: user.hasPassword,
              ),
            ),
        ],
      ),
    );
  }
}
