import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_icon.dart';
import '../../auth/data/auth_api.dart';
import '../../auth/domain/app_user.dart';

/// Reminds the user to confirm their email, with a button to resend the link.
/// Shown in Settings while the address is not confirmed.
class VerifyEmailCard extends ConsumerStatefulWidget {
  const VerifyEmailCard({super.key, required this.user});

  final AppUser user;

  @override
  ConsumerState<VerifyEmailCard> createState() => _VerifyEmailCardState();
}

class _VerifyEmailCardState extends ConsumerState<VerifyEmailCard> {
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
            AppIcon(
              HugeIcons.strokeRoundedMailOpen01,
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
