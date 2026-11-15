import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_theme.dart';
import '../data/auth_api.dart';
import '../domain/validators.dart';
import 'auth_widgets.dart';

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  bool _loading = false;
  bool _sent = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      await ref.read(authApiProvider).forgotPassword(_email.text.trim());
      if (mounted) setState(() => _sent = true);
    } on Object catch (e, st) {
      if (mounted) setState(() => _error = userMessage(e, st));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_sent) {
      return AuthScaffold(
        showBack: true,
        title: 'Check your email',
        // Same text whether or not the account exists (no account guessing).
        subtitle:
            'If an account exists for ${_email.text.trim()}, we sent a link to reset '
            'the password. The link works for 1 hour. Open it on this phone.',
        children: [
          FilledButton(
            onPressed: () => context.go(Routes.login),
            child: const Text('Back to log in'),
          ),
        ],
      );
    }
    return AuthScaffold(
      showBack: true,
      title: 'Reset your password',
      subtitle: 'Enter your email and we will send you a link to choose a new password.',
      children: [
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                autocorrect: false,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _submit(),
                validator: validateEmail,
                decoration: const InputDecoration(labelText: 'Email'),
              ),
              const SizedBox(height: Spacing.xl),
              FormErrorText(_error),
              LoadingButton(
                label: 'Send reset link',
                loading: _loading,
                onPressed: _submit,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
