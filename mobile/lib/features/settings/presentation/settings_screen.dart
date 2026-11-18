import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/widgets/app_icon.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/application/auth_controller.dart';
import '../../currency/presentation/main_currency_dialog.dart';
import '../../app_lock/application/app_lock.dart';
import '../../app_lock/application/biometrics.dart';
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
          _AppLockTiles(),
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

/// "App lock" and, when it is on and the phone can, "Unlock with fingerprint".
class _AppLockTiles extends ConsumerWidget {
  Future<void> _turnOff(BuildContext context, WidgetRef ref) async {
    final pin = TextEditingController();
    String? error;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Turn off app lock?'),
          content: TextField(
            controller: pin,
            autofocus: true,
            obscureText: true,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Your PIN',
              errorText: error,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final right = await ref
                    .read(appLockProvider.notifier)
                    .checkPin(pin.text);
                if (!context.mounted) return;
                if (right) {
                  Navigator.pop(context, true);
                } else {
                  setState(() => error = 'Wrong PIN');
                }
              },
              child: const Text('Turn off'),
            ),
          ],
        ),
      ),
    );
    if (ok == true) await ref.read(appLockProvider.notifier).disable();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lock = ref.watch(appLockProvider);
    final canBio = ref.watch(biometricsAvailableProvider).value ?? false;
    return Column(
      children: [
        SwitchListTile(
          secondary: const AppIcon(HugeIcons.strokeRoundedSquareLock02),
          title: const Text('App lock'),
          subtitle: const Text('Ask for a PIN when pennyWise opens'),
          value: lock.enabled,
          onChanged: (on) =>
              on ? context.push(Routes.setPin) : _turnOff(context, ref),
        ),
        if (lock.enabled && canBio)
          SwitchListTile(
            secondary: const AppIcon(HugeIcons.strokeRoundedFingerPrint),
            title: const Text('Unlock with fingerprint or face'),
            value: lock.biometric,
            onChanged: (on) =>
                ref.read(appLockProvider.notifier).setBiometric(on),
          ),
      ],
    );
  }
}
