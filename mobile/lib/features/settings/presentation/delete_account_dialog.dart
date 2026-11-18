import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/application/auth_controller.dart';

/// Asks before deleting the account for good. Accounts with a password
/// type it to confirm. On success the app is logged out and wiped.
Future<void> showDeleteAccountDialog(
  BuildContext context, {
  required bool hasPassword,
}) => showDialog<void>(
  context: context,
  builder: (_) => _DeleteAccountDialog(hasPassword: hasPassword),
);

class _DeleteAccountDialog extends ConsumerStatefulWidget {
  const _DeleteAccountDialog({required this.hasPassword});

  final bool hasPassword;

  @override
  ConsumerState<_DeleteAccountDialog> createState() =>
      _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends ConsumerState<_DeleteAccountDialog> {
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    if (widget.hasPassword && _password.text.isEmpty) {
      setState(() => _error = 'Type your password to confirm');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final navigator = Navigator.of(context);
    try {
      await ref
          .read(authControllerProvider.notifier)
          .deleteAccount(password: widget.hasPassword ? _password.text : null);
      // Logged out now; the router shows the login screen under this dialog.
      if (navigator.mounted && navigator.canPop()) navigator.pop();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.code == 'wrong_password'
            ? 'That password is wrong'
            : e.isNetworkError
            ? 'No connection. Your account was not deleted; try again online.'
            : e.message;
      });
    } on Object catch (e, st) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = userMessage(e, st);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final error = Theme.of(context).colorScheme.error;
    return AlertDialog(
      title: const Text('Delete your account?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This deletes your account and everything in it: accounts, '
              'transactions, budgets, goals and receipt photos, on this phone '
              'and on our server. It cannot be undone.',
            ),
            const SizedBox(height: Spacing.sm),
            const Text('Want a copy first? Export your data from Reports.'),
            if (widget.hasPassword) ...[
              const SizedBox(height: Spacing.lg),
              TextFormField(
                controller: _password,
                obscureText: true,
                autofillHints: const [AutofillHints.password],
                decoration: const InputDecoration(labelText: 'Password'),
                onFieldSubmitted: (_) => _busy ? null : _delete(),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: Spacing.md),
              Text(_error!, style: TextStyle(color: error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: error),
          onPressed: _busy ? null : _delete,
          child: Text(_busy ? 'Deleting…' : 'Delete account'),
        ),
      ],
    );
  }
}
