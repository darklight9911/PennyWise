import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/router/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/currencies.dart';
import '../../../core/widgets/app_icon.dart';
import '../../app_lock/application/app_lock.dart';
import '../../app_lock/application/biometrics.dart';
import '../../auth/application/auth_controller.dart';
import '../../currency/presentation/main_currency_dialog.dart';
import 'delete_account_dialog.dart';
import 'verify_email_card.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  Future<void> _confirmLogout(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text(
          'Your data stays in your account. This phone starts empty again, '
          'and you can keep using pennyWise without an account.',
        ),
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

  Future<void> _confirmErase(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Erase data on this phone?'),
        content: const Text(
          'Everything you added will be deleted. It is not backed up, so '
          'this cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Erase'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(authControllerProvider.notifier).eraseGuestData();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final auth = ref.watch(authControllerProvider);
    final user = auth is SignedIn ? auth.user : null;
    final profile = auth.profile;
    final guest = auth is Guest;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          if (guest)
            const _CardPadding(
              child: _AccountCard(
                icon: HugeIcons.strokeRoundedCloudUpload,
                title: 'Back up and sync',
                message:
                    'You are using pennyWise without an account. Your data '
                    'is only on this phone. Log in or create a free account '
                    'to back it up and use it on other phones too.',
                showCreate: true,
              ),
            ),
          if (auth is SignedIn && auth.sessionExpired)
            const _CardPadding(
              child: _AccountCard(
                icon: HugeIcons.strokeRoundedCloudSlowWind,
                title: 'Log in again to sync',
                message:
                    'Your session ended. Everything still works on this '
                    'phone; log in again to sync your changes.',
                showCreate: false,
              ),
            ),
          if (user != null) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Spacing.lg,
                Spacing.md,
                Spacing.lg,
                Spacing.xs,
              ),
              child: Text(
                'Profile',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
              child: Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ListTile(
                      leading: CircleAvatar(
                        backgroundColor: theme.colorScheme.primary.withValues(
                          alpha: 0.12,
                        ),
                        foregroundColor: theme.colorScheme.primary,
                        child: Text(
                          user.displayName.isNotEmpty
                              ? user.displayName[0].toUpperCase()
                              : '?',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      title: Text(
                        user.displayName,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user.emailVerified
                                ? user.email
                                : '${user.email} · not confirmed',
                          ),
                          const SizedBox(height: Spacing.xs),
                          _EmailVerificationBadge(verified: user.emailVerified),
                        ],
                      ),
                    ),
                    if (!user.emailVerified)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          Spacing.md,
                          0,
                          Spacing.md,
                          Spacing.md,
                        ),
                        child: VerifyEmailCard(user: user),
                      ),
                    const Divider(height: 1),
                    ListTile(
                      dense: true,
                      leading: const AppIcon(HugeIcons.strokeRoundedClock01),
                      title: const Text('Time zone'),
                      subtitle: Text(profile?.timezone ?? '—'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: Spacing.sm),
          ],
          ListTile(
            leading: const AppIcon(HugeIcons.strokeRoundedMoney03),
            title: const Text('Main currency'),
            subtitle: Text(
              profile == null
                  ? '—'
                  : profile.recalculating
                  ? '${profile.baseCurrency} · converting totals…'
                  : currencyLabel(profile.baseCurrency),
            ),
            trailing: profile == null
                ? null
                : const AppIcon(HugeIcons.strokeRoundedArrowRight01),
            onTap: profile == null || profile.recalculating
                ? null
                : () => showMainCurrencyDialog(context, profile.baseCurrency),
          ),
          if (user == null)
            ListTile(
              leading: const AppIcon(HugeIcons.strokeRoundedClock01),
              title: const Text('Time zone'),
              subtitle: Text(profile?.timezone ?? '—'),
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
          if (user != null)
            ListTile(
              leading: const AppIcon(HugeIcons.strokeRoundedLogout03),
              title: const Text('Log out'),
              onTap: () => _confirmLogout(context, ref),
            ),
          if (guest)
            ListTile(
              leading: AppIcon(
                HugeIcons.strokeRoundedDelete02,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text(
                'Erase data on this phone',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              onTap: () => _confirmErase(context, ref),
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

class _EmailVerificationBadge extends StatelessWidget {
  const _EmailVerificationBadge({required this.verified});

  final bool verified;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = verified ? AppColors.incomeText : theme.colorScheme.error;
    final bg = (verified ? AppColors.income : theme.colorScheme.error)
        .withValues(alpha: 0.12);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 4,
        children: [
          AppIcon(
            verified
                ? HugeIcons.strokeRoundedCheckmarkCircle02
                : HugeIcons.strokeRoundedAlertCircle,
            size: 14,
            color: color,
          ),
          Text(
            verified ? 'Confirmed' : 'Not confirmed',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _CardPadding extends StatelessWidget {
  const _CardPadding({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      Spacing.lg,
      Spacing.sm,
      Spacing.lg,
      Spacing.sm,
    ),
    child: child,
  );
}

/// Invites the user to log in (or sign up) to back up and sync.
class _AccountCard extends StatelessWidget {
  const _AccountCard({
    required this.icon,
    required this.title,
    required this.message,
    required this.showCreate,
  });

  final AppIconData icon;
  final String title;
  final String message;
  final bool showCreate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final on = theme.colorScheme.onSecondaryContainer;
    return Card(
      color: theme.colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(Spacing.lg),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppIcon(icon, color: on),
            const SizedBox(width: Spacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.titleSmall),
                  const SizedBox(height: Spacing.xs),
                  Text(message, style: theme.textTheme.bodySmall),
                  const SizedBox(height: Spacing.sm),
                  Wrap(
                    spacing: Spacing.sm,
                    runSpacing: Spacing.xs,
                    children: [
                      FilledButton(
                        onPressed: () => context.push(Routes.login),
                        child: const Text('Log in'),
                      ),
                      if (showCreate)
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: on,
                            minimumSize: const Size(64, 48),
                          ),
                          onPressed: () => context.push(Routes.register),
                          child: const Text('Create account'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
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
