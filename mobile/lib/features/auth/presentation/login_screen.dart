import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_theme.dart';
import '../application/auth_controller.dart';
import '../data/google_auth.dart';
import '../domain/validators.dart';
import 'auth_widgets.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  bool _googleLoading = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      await ref
          .read(authControllerProvider.notifier)
          .login(_email.text, _password.text);
      // The router redirects to the dashboard on SignedIn.
    } on Object catch (e, st) {
      if (mounted) setState(() => _error = userMessage(e, st));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _google() async {
    setState(() {
      _error = null;
      _googleLoading = true;
    });
    try {
      await ref.read(authControllerProvider.notifier).loginWithGoogle();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on Object catch (e, st) {
      userMessage(e, st); // logs it
      if (mounted) {
        setState(() => _error = 'Google sign-in failed. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _googleLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final googleEnabled = ref.watch(googleAuthProvider).enabled;
    final busy = _loading || _googleLoading;

    return AuthScaffold(
      title: 'Welcome back',
      subtitle: 'Log in to see your money at a glance.',
      children: [
        Form(
          key: _formKey,
          child: AutofillGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  autocorrect: false,
                  textInputAction: TextInputAction.next,
                  validator: validateEmail,
                  decoration: const InputDecoration(labelText: 'Email'),
                ),
                const SizedBox(height: Spacing.lg),
                PasswordField(
                  controller: _password,
                  label: 'Password',
                  validator: validateLoginPassword,
                  onSubmitted: (_) => _submit(),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: busy
                        ? null
                        : () => context.push(Routes.forgotPassword),
                    child: const Text('Forgot password?'),
                  ),
                ),
                const SizedBox(height: Spacing.sm),
                FormErrorText(_error),
                LoadingButton(
                  label: 'Log in',
                  loading: _loading,
                  onPressed: _submit,
                ),
              ],
            ),
          ),
        ),
        if (googleEnabled) ...[
          const OrDivider(),
          OutlinedButton.icon(
            onPressed: busy ? null : _google,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
            icon: _googleLoading
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.g_mobiledata, size: 28),
            label: const Text('Continue with Google'),
          ),
        ],
        const SizedBox(height: Spacing.xl),
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text('New to pennyWise?'),
            TextButton(
              onPressed: busy ? null : () => context.go(Routes.register),
              child: const Text('Create an account'),
            ),
          ],
        ),
      ],
    );
  }
}
