import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/device/device_profile.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../currency/presentation/currency_picker_sheet.dart';
import '../application/auth_controller.dart';
import '../domain/validators.dart';
import '../../../core/widgets/panda_mascot.dart';
import 'auth_widgets.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  late String _currency = ref.read(deviceProfileProvider).defaultCurrency;
  bool _loading = false;
  String? _error;

  /// Errors the server returned for one field (e.g. email already taken).
  final Map<String, String> _fieldErrors = {};

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _pickCurrency() async {
    final picked = await showCurrencyPicker(
      context,
      title: 'Main currency',
      subtitle: 'Totals and budgets use this currency.',
      selected: _currency,
      detectedCode: ref.read(deviceProfileProvider).defaultCurrency,
    );
    if (picked != null && mounted) {
      setState(() {
        _currency = picked;
        _fieldErrors.remove('base_currency');
      });
    }
  }

  Future<void> _submit() async {
    setState(() {
      _error = null;
      _fieldErrors.clear();
    });
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      await ref
          .read(authControllerProvider.notifier)
          .register(
            email: _email.text,
            password: _password.text,
            name: _name.text,
            baseCurrency: _currency,
          );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        if (e.code == 'email_taken') {
          _fieldErrors['email'] =
              'An account with this email already exists. Try logging in.';
        } else if (e.field != null) {
          _fieldErrors[e.field!] = e.message;
        } else {
          _error = e.message;
        }
      });
    } on Object catch (e, st) {
      if (mounted) setState(() => _error = userMessage(e, st));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      mascotMood: _error == null ? PandaMood.happy : PandaMood.worried,
      title: 'Create your account',
      subtitle: 'Track spending, budgets and goals in one place.',
      children: [
        Form(
          key: _formKey,
          child: AutofillGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  autofillHints: const [AutofillHints.name],
                  textInputAction: TextInputAction.next,
                  validator: validateName,
                  decoration: InputDecoration(
                    labelText: 'Name (optional)',
                    errorText: _fieldErrors['name'],
                  ),
                ),
                const SizedBox(height: Spacing.lg),
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  autocorrect: false,
                  textInputAction: TextInputAction.next,
                  validator: validateEmail,
                  decoration: InputDecoration(
                    labelText: 'Email',
                    errorText: _fieldErrors['email'],
                    errorMaxLines: 2,
                  ),
                ),
                const SizedBox(height: Spacing.lg),
                PasswordField(
                  controller: _password,
                  label: 'Password',
                  newPassword: true,
                  helperText:
                      'At least $minPasswordLength characters. A short sentence works well.',
                  errorText: _fieldErrors['password'],
                  validator: validateNewPassword,
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: Spacing.lg),
                CurrencyField(
                  label: 'Main currency',
                  value: _currency,
                  helperText: 'Totals and budgets use this currency.',
                  errorText: _fieldErrors['base_currency'],
                  enabled: !_loading,
                  onTap: _pickCurrency,
                ),
                const SizedBox(height: Spacing.xl),
                FormErrorText(_error),
                LoadingButton(
                  label: 'Create account',
                  loading: _loading,
                  onPressed: _submit,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: Spacing.xl),
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text('Already have an account?'),
            TextButton(
              onPressed: _loading ? null : () => context.go(Routes.login),
              child: const Text('Log in'),
            ),
          ],
        ),
      ],
    );
  }
}
