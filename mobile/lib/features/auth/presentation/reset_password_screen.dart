import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_theme.dart';
import '../application/auth_controller.dart';
import '../data/auth_api.dart';
import '../domain/validators.dart';
import 'auth_widgets.dart';

/// Opened from the reset link in the email (pennywise://reset-password?token=...).
class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({super.key, required this.token});

  final String token;

  @override
  ConsumerState<ResetPasswordScreen> createState() =>
      _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      await ref
          .read(authApiProvider)
          .resetPassword(token: widget.token, newPassword: _password.text);
      // The server logged out every device, including this one.
      await ref.read(authControllerProvider.notifier).logout();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Password changed. Log in with your new password.'),
        ),
      );
      context.go(Routes.login);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.code == 'invalid_link'
            ? 'This reset link has expired or was already used. Ask for a new one.'
            : e.message;
      });
    } on Object catch (e, st) {
      if (mounted) setState(() => _error = userMessage(e, st));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final invalidLink = widget.token.isEmpty;
    return AuthScaffold(
      showBack: true,
      title: 'Choose a new password',
      subtitle: 'You will be logged out on all your devices.',
      children: [
        if (invalidLink)
          const FormErrorText(
            'This link is incomplete. Open the link from the email again.',
          )
        else
          Form(
            key: _formKey,
            child: AutofillGroup(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  PasswordField(
                    controller: _password,
                    label: 'New password',
                    newPassword: true,
                    helperText: 'At least $minPasswordLength characters.',
                    validator: validateNewPassword,
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: Spacing.lg),
                  PasswordField(
                    controller: _confirm,
                    label: 'Repeat new password',
                    newPassword: true,
                    validator: (v) =>
                        v != _password.text ? 'Passwords do not match' : null,
                    onSubmitted: (_) => _submit(),
                  ),
                  const SizedBox(height: Spacing.xl),
                  FormErrorText(_error),
                  LoadingButton(
                    label: 'Save new password',
                    loading: _loading,
                    onPressed: _submit,
                  ),
                ],
              ),
            ),
          ),
        if (_error != null && _error!.contains('expired'))
          TextButton(
            onPressed: () => context.go(Routes.forgotPassword),
            child: const Text('Send a new link'),
          ),
      ],
    );
  }
}
