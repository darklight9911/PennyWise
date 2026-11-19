import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/widgets/app_icon.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/router/routes.dart';
import '../../../core/widgets/panda_mascot.dart';
import '../application/auth_controller.dart';

/// Common layout for the logged-out screens: brand header, centred
/// content with a max width, scrolls when the keyboard is open.
///
/// Signing in is optional, so a guest can always leave these screens
/// ("Not now"), back to where they came from.
class AuthScaffold extends ConsumerWidget {
  const AuthScaffold({
    super.key,
    required this.title,
    this.subtitle,
    required this.children,
    this.showBack = false,
    this.mascotMood = PandaMood.wave,
  });

  final String title;
  final String? subtitle;
  final List<Widget> children;
  final bool showBack;

  /// Penny greets the user on the first screens (not on back-able ones).
  final PandaMood mascotMood;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final auth = ref.watch(authControllerProvider);
    final canLeave =
        !showBack &&
        (auth is Guest ||
            auth is SetupNeeded ||
            (auth is SignedIn && auth.sessionExpired));
    return Scaffold(
      appBar: showBack
          ? AppBar()
          : canLeave
          ? AppBar(
              leading: IconButton(
                tooltip: 'Not now',
                icon: const AppIcon(HugeIcons.strokeRoundedCancel01),
                onPressed: () => context.canPop()
                    ? context.pop()
                    : context.go(
                        auth is SetupNeeded ? Routes.welcome : Routes.settings,
                      ),
              ),
            )
          : null,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: Spacing.xl,
              vertical: Spacing.xxl,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!showBack) ...[
                    Center(child: PandaMascot(mood: mascotMood, size: 132)),
                    const SizedBox(height: Spacing.sm),
                    const BrandMark(),
                    const SizedBox(height: Spacing.xl),
                  ],
                  Text(title, style: theme.textTheme.headlineSmall),
                  if (subtitle != null) ...[
                    const SizedBox(height: Spacing.sm),
                    Text(
                      subtitle!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: Spacing.xl),
                  ...children,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The pennyWise logo mark (placeholder until the real icon exists).
class BrandMark extends StatelessWidget {
  const BrandMark({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: scheme.primary,
            borderRadius: BorderRadius.circular(Radii.button),
          ),
          child: AppIcon(
            HugeIcons.strokeRoundedPiggyBank,
            color: scheme.onPrimary,
          ),
        ),
        const SizedBox(width: Spacing.md),
        Flexible(
          child: Text(
            'pennyWise',
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

/// Password input with a show/hide toggle.
class PasswordField extends StatefulWidget {
  const PasswordField({
    super.key,
    required this.controller,
    required this.label,
    this.validator,
    this.helperText,
    this.errorText,
    this.newPassword = false,
    this.textInputAction = TextInputAction.done,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String label;
  final FormFieldValidator<String>? validator;
  final String? helperText;
  final String? errorText;

  /// Lets password managers offer to generate and save a password.
  final bool newPassword;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onSubmitted;

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget.controller,
      obscureText: _obscure,
      enableSuggestions: false,
      autocorrect: false,
      autofillHints: [
        widget.newPassword ? AutofillHints.newPassword : AutofillHints.password,
      ],
      textInputAction: widget.textInputAction,
      onFieldSubmitted: widget.onSubmitted,
      validator: widget.validator,
      decoration: InputDecoration(
        labelText: widget.label,
        helperText: widget.helperText,
        errorText: widget.errorText,
        suffixIcon: IconButton(
          tooltip: _obscure ? 'Show password' : 'Hide password',
          icon: AppIcon(
            _obscure
                ? HugeIcons.strokeRoundedView
                : HugeIcons.strokeRoundedViewOff,
          ),
          onPressed: () => setState(() => _obscure = !_obscure),
        ),
      ),
    );
  }
}

/// Filled button that shows a spinner and ignores taps while [loading].
class LoadingButton extends StatelessWidget {
  const LoadingButton({
    super.key,
    required this.label,
    required this.loading,
    required this.onPressed,
  });

  final String label;
  final bool loading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: loading ? null : onPressed,
      child: loading
          ? const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Text(label),
    );
  }
}

/// A form-level error message (e.g. "email or password is wrong").
class FormErrorText extends StatelessWidget {
  const FormErrorText(this.message, {super.key});

  final String? message;

  @override
  Widget build(BuildContext context) {
    if (message == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.lg),
      child: Semantics(
        liveRegion: true,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppIcon(
              HugeIcons.strokeRoundedAlertCircle,
              size: 20,
              color: scheme.error,
            ),
            const SizedBox(width: Spacing.sm),
            Expanded(
              child: Text(message!, style: TextStyle(color: scheme.error)),
            ),
          ],
        ),
      ),
    );
  }
}

/// "or" divider between password login and Google.
class OrDivider extends StatelessWidget {
  const OrDivider({super.key});

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Spacing.lg),
      child: Row(
        children: [
          const Expanded(child: Divider()),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
            child: Text('or', style: TextStyle(color: muted)),
          ),
          const Expanded(child: Divider()),
        ],
      ),
    );
  }
}
