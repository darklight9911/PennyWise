import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/amount_text.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/data/auth_api.dart';
import '../../auth/domain/app_user.dart';

/// Home screen. Shows placeholder zeros until accounts and transactions
/// exist (Milestone 2).
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final user = auth is SignedIn ? auth.user : null;
    final currency = user?.baseCurrency ?? 'USD';

    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(user == null ? 'pennyWise' : 'Hi, ${user.displayName}'),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          try {
            await ref.read(authControllerProvider.notifier).refreshUser();
          } on ApiException {
            // Offline: keep showing what we have.
          }
        },
        child: ListView(
          padding: const EdgeInsets.all(Spacing.lg),
          children: [
            if (user != null && !user.emailVerified) ...[
              _VerifyEmailCard(user: user),
              const SizedBox(height: Spacing.md),
            ],
            Card(
              child: Padding(
                padding: const EdgeInsets.all(Spacing.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Total balance', style: muted),
                    const SizedBox(height: Spacing.sm),
                    AmountText(
                      minor: 0,
                      currency: currency,
                      signed: false,
                      large: true,
                      style: theme.textTheme.displaySmall,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: Spacing.md),
            Row(
              children: [
                Expanded(
                  child: _MonthFigure(
                    label: 'Income this month',
                    minor: 0,
                    currency: currency,
                    labelStyle: muted,
                  ),
                ),
                const SizedBox(width: Spacing.md),
                Expanded(
                  child: _MonthFigure(
                    label: 'Spent this month',
                    minor: 0,
                    currency: currency,
                    labelStyle: muted,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Add transaction',
        onPressed: () {}, // Add-transaction flow arrives in Milestone 2.
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _VerifyEmailCard extends ConsumerStatefulWidget {
  const _VerifyEmailCard({required this.user});

  final AppUser user;

  @override
  ConsumerState<_VerifyEmailCard> createState() => _VerifyEmailCardState();
}

class _VerifyEmailCardState extends ConsumerState<_VerifyEmailCard> {
  bool _sending = false;

  Future<void> _resend() async {
    setState(() => _sending = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(authApiProvider).resendVerification();
      messenger.showSnackBar(
        SnackBar(content: Text('We sent a new link to ${widget.user.email}.')),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            e.code == 'rate_limited'
                ? 'Please wait a while before asking for another link.'
                : e.message,
          ),
        ),
      );
    } on Object catch (e, st) {
      messenger.showSnackBar(SnackBar(content: Text(userMessage(e, st))));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(Spacing.lg),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.mark_email_unread_outlined,
              color: theme.colorScheme.onSecondaryContainer,
            ),
            const SizedBox(width: Spacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Confirm your email', style: theme.textTheme.titleSmall),
                  const SizedBox(height: Spacing.xs),
                  Text(
                    'Open the link we sent to ${widget.user.email}. '
                    'It helps you get back in if you forget your password.',
                    style: theme.textTheme.bodySmall,
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      style: TextButton.styleFrom(
                        foregroundColor: theme.colorScheme.onSecondaryContainer,
                        padding: EdgeInsets.zero,
                      ),
                      onPressed: _sending ? null : _resend,
                      child: Text(
                        _sending ? 'Sending…' : 'Send the link again',
                      ),
                    ),
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

class _MonthFigure extends StatelessWidget {
  const _MonthFigure({
    required this.label,
    required this.minor,
    required this.currency,
    this.labelStyle,
  });

  final String label;
  final int minor;
  final String currency;
  final TextStyle? labelStyle;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: labelStyle),
            const SizedBox(height: Spacing.xs),
            AmountText(
              minor: minor,
              currency: currency,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ],
        ),
      ),
    );
  }
}
