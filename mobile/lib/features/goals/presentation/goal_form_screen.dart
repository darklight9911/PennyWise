import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/database/app_database.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/responsive_layout.dart';
import '../../auth/application/auth_controller.dart';
import '../../ledger/application/ledger_providers.dart';
import '../../ledger/presentation/day_labels.dart';
import '../../recurring/domain/recurrence.dart';

/// Add a goal ([goalId] null) or edit one.
class GoalFormScreen extends ConsumerStatefulWidget {
  const GoalFormScreen({super.key, this.goalId});

  final String? goalId;

  @override
  ConsumerState<GoalFormScreen> createState() => _GoalFormScreenState();
}

class _GoalFormScreenState extends ConsumerState<GoalFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _target = TextEditingController();
  String? _deadline;
  Goal? _existing;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  bool get _isNew => widget.goalId == null;

  String get _currency {
    return ref.read(baseCurrencyProvider);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!_isNew) {
      final store = await ref.read(ledgerStoreProvider.future);
      final g = await store.getGoal(widget.goalId!);
      if (g != null) {
        _existing = g;
        _name.text = g.name;
        _target.text = formatMinor(g.targetMinor, _currency);
        _deadline = g.deadline;
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _name.dispose();
    _target.dispose();
    super.dispose();
  }

  Future<void> _pickDeadline() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _deadline == null
          ? DateTime(now.year + 1, now.month, now.day)
          : DateTime.parse(_deadline!),
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 50),
    );
    if (picked != null) setState(() => _deadline = ymd(picked));
  }

  Future<void> _save() async {
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;
    final target = parseAmount(_target.text, _currency).minor!;
    setState(() => _saving = true);
    try {
      final store = await ref.read(ledgerStoreProvider.future);
      final e = _existing;
      if (e == null) {
        final g = await store.createGoal(
          name: _name.text,
          targetMinor: target,
          deadline: _deadline,
        );
        if (mounted) context.pushReplacement(Routes.goal(g.id));
      } else {
        await store.updateGoal(
          e.copyWith(
            name: _name.text,
            targetMinor: target,
            deadline: Value(_deadline),
          ),
        );
        if (mounted) context.pop();
      }
    } on Object catch (e, st) {
      if (mounted) setState(() => _error = userMessage(e, st));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${_existing!.name}?'),
        content: const Text(
          'The goal and its history are deleted. Your accounts do not change.',
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
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final store = await ref.read(ledgerStoreProvider.future);
    await store.deleteGoal(_existing!.id);
    // Tells the goal page under this form that its goal is gone.
    if (mounted) context.pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final currency = _currency;
    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? 'New goal' : 'Edit goal'),
        actions: [
          if (_existing != null)
            IconButton(
              tooltip: 'Delete goal',
              icon: const AppIcon(HugeIcons.strokeRoundedDelete02),
              onPressed: _delete,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ResponsiveBody(
              maxWidth: ContentWidths.form,
              child: Form(
                key: _formKey,
                child: ListView(
                  padding: EdgeInsets.symmetric(
                    horizontal: ResponsiveLayout.horizontalPadding(context),
                    vertical: Spacing.md,
                  ),
                  children: [
                    TextFormField(
                      controller: _name,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        labelText: 'What are you saving for?',
                        hintText: 'e.g. New laptop',
                      ),
                      validator: (v) {
                        final n = v?.trim().length ?? 0;
                        if (n == 0) return 'Give the goal a name';
                        if (n > 60) return 'Use at most 60 characters';
                        return null;
                      },
                    ),
                    const SizedBox(height: Spacing.lg),
                    TextFormField(
                      controller: _target,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Target',
                        suffixText: currency,
                      ),
                      validator: (v) {
                        final r = parseAmount(v ?? '', currency);
                        if (r.error != null) {
                          return amountErrorText(r.error!, currency);
                        }
                        if (r.minor == 0) return 'Enter a target above zero';
                        return null;
                      },
                    ),
                    const SizedBox(height: Spacing.lg),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const AppIcon(HugeIcons.strokeRoundedCalendar03),
                      title: Text(
                        _deadline == null
                            ? 'No deadline'
                            : 'By ${dayLabel(_deadline!, DateTime.now())}',
                      ),
                      subtitle: const Text('Optional'),
                      trailing: _deadline == null
                          ? null
                          : IconButton(
                              tooltip: 'Remove deadline',
                              icon: const AppIcon(
                                HugeIcons.strokeRoundedCancel01,
                              ),
                              onPressed: () => setState(() => _deadline = null),
                            ),
                      onTap: _pickDeadline,
                    ),
                    const SizedBox(height: Spacing.xl),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: Spacing.lg),
                        child: Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    FilledButton(
                      onPressed: _saving ? null : _save,
                      child: Text(_isNew ? 'Add goal' : 'Save changes'),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
