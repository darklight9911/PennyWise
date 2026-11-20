import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/currencies.dart';
import '../../../core/widgets/app_icon.dart';
import '../../auth/application/auth_controller.dart';
import 'verify_email_card.dart';

/// Shows a structured modal bottom sheet with the user's profile details:
/// email address, confirmation status, time zone, main currency, and sign-in info.
Future<void> showProfileModal(BuildContext context) {
  final theme = Theme.of(context);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: theme.colorScheme.surface,
    constraints: const BoxConstraints(maxWidth: 540),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.card)),
    ),
    builder: (context) => const _ProfileModalSheet(),
  );
}

class _ProfileModalSheet extends ConsumerWidget {
  const _ProfileModalSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final auth = ref.watch(authControllerProvider);
    final user = auth is SignedIn ? auth.user : null;
    final profile = auth.profile;
    final isGuest = user == null;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        Spacing.lg,
        Spacing.xs,
        Spacing.lg,
        Spacing.xl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Profile details',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              IconButton(
                icon: const AppIcon(HugeIcons.strokeRoundedCancel01, size: 20),
                tooltip: 'Close',
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: Spacing.md),
          Center(
            child: Column(
              children: [
                CircleAvatar(
                  radius: 36,
                  backgroundColor: theme.colorScheme.primary.withValues(
                    alpha: 0.12,
                  ),
                  foregroundColor: theme.colorScheme.primary,
                  child: user != null
                      ? Text(
                          user.displayName.isNotEmpty
                              ? user.displayName[0].toUpperCase()
                              : '?',
                          style: const TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                          ),
                        )
                      : const AppIcon(HugeIcons.strokeRoundedUser, size: 36),
                ),
                const SizedBox(height: Spacing.sm),
                Text(
                  user != null && user.displayName.isNotEmpty
                      ? user.displayName
                      : (isGuest ? 'Guest User' : 'pennyWise User'),
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: Spacing.xs),
                _VerificationPill(
                  verified: user?.emailVerified ?? false,
                  isGuest: isGuest,
                ),
              ],
            ),
          ),
          const SizedBox(height: Spacing.lg),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Spacing.md,
                    Spacing.md,
                    Spacing.md,
                    Spacing.xs,
                  ),
                  child: Text(
                    'Account & Email',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                ListTile(
                  leading: const AppIcon(HugeIcons.strokeRoundedMail01),
                  title: const Text('Email address'),
                  subtitle: Text(user?.email ?? 'No email (offline guest)'),
                  trailing: user != null
                      ? AppIcon(
                          user.emailVerified
                              ? HugeIcons.strokeRoundedCheckmarkCircle02
                              : HugeIcons.strokeRoundedAlertCircle,
                          color: user.emailVerified
                              ? AppColors.incomeText
                              : theme.colorScheme.error,
                        )
                      : null,
                ),
                if (user != null && !user.emailVerified) ...[
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.all(Spacing.md),
                    child: VerifyEmailCard(user: user),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: Spacing.md),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Spacing.md,
                    Spacing.md,
                    Spacing.md,
                    Spacing.xs,
                  ),
                  child: Text(
                    'Regional Info',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                ListTile(
                  leading: const AppIcon(HugeIcons.strokeRoundedClock01),
                  title: const Text('Time zone'),
                  subtitle: Text(profile?.timezone ?? 'UTC'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const AppIcon(HugeIcons.strokeRoundedMoney03),
                  title: const Text('Main currency'),
                  subtitle: Text(
                    profile != null ? currencyLabel(profile.baseCurrency) : '—',
                  ),
                ),
              ],
            ),
          ),
          if (user != null) ...[
            const SizedBox(height: Spacing.md),
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      Spacing.md,
                      Spacing.md,
                      Spacing.md,
                      Spacing.xs,
                    ),
                    child: Text(
                      'Security',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  ListTile(
                    leading: const AppIcon(
                      HugeIcons.strokeRoundedSecurityCheck,
                    ),
                    title: const Text('Sign-in method'),
                    subtitle: Text(
                      user.hasPassword ? 'Password' : 'Google Account',
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: Spacing.lg),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }
}

class _VerificationPill extends StatelessWidget {
  const _VerificationPill({required this.verified, required this.isGuest});

  final bool verified;
  final bool isGuest;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Color color;
    final Color bg;
    final AppIconData icon;
    final String label;

    if (isGuest) {
      color = theme.colorScheme.onSurfaceVariant;
      bg = theme.colorScheme.surfaceContainerHighest;
      icon = HugeIcons.strokeRoundedCloudSlowWind;
      label = 'Using offline as guest';
    } else if (verified) {
      color = AppColors.incomeText;
      bg = AppColors.income.withValues(alpha: 0.12);
      icon = HugeIcons.strokeRoundedCheckmarkCircle02;
      label = 'Confirmed email';
    } else {
      color = theme.colorScheme.error;
      bg = theme.colorScheme.error.withValues(alpha: 0.12);
      icon = HugeIcons.strokeRoundedAlertCircle;
      label = 'Email not confirmed';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppIcon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
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
