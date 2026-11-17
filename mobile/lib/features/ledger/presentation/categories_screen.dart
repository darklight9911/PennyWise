import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/database/app_database.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../application/ledger_providers.dart';
import '../data/ledger_store.dart';
import 'ledger_style.dart';

/// Expense and income categories: add, rename, recolour, delete.
class CategoriesScreen extends StatelessWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: _CategoriesAppBar(),
        body: TabBarView(
          children: [
            _CategoryList(kind: TxKind.expense),
            _CategoryList(kind: TxKind.income),
          ],
        ),
      ),
    );
  }
}

class _CategoriesAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _CategoriesAppBar();

  @override
  Size get preferredSize =>
      const Size.fromHeight(kToolbarHeight + kTextTabBarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: const Text('Categories'),
      bottom: const TabBar(
        tabs: [
          Tab(text: 'Expenses'),
          Tab(text: 'Income'),
        ],
      ),
    );
  }
}

class _CategoryList extends ConsumerWidget {
  const _CategoryList({required this.kind});

  final String kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(categoriesProvider(kind));
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: null,
        onPressed: () => showCategoryEditor(context, kind: kind),
        icon: const Icon(Icons.add),
        label: Text(
          kind == TxKind.expense
              ? 'Add expense category'
              : 'Add income category',
        ),
      ),
      body: categories.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load: $e')),
        data: (list) => list.isEmpty
            ? const Center(child: Text('No categories yet.'))
            : ListView.builder(
                padding: const EdgeInsets.only(bottom: 96),
                itemCount: list.length,
                itemBuilder: (context, i) {
                  final c = list[i];
                  return ListTile(
                    leading: IconBadge(
                      icon: categoryIcon(c.icon),
                      color: colorFromHex(c.color, scheme.primary),
                    ),
                    title: Text(c.name),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () =>
                        showCategoryEditor(context, kind: kind, existing: c),
                  );
                },
              ),
      ),
    );
  }
}

/// Bottom sheet to add ([existing] null) or edit a category.
Future<void> showCategoryEditor(
  BuildContext context, {
  required String kind,
  Category? existing,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _CategoryEditor(kind: kind, existing: existing),
  );
}

class _CategoryEditor extends ConsumerStatefulWidget {
  const _CategoryEditor({required this.kind, this.existing});

  final String kind;
  final Category? existing;

  @override
  ConsumerState<_CategoryEditor> createState() => _CategoryEditorState();
}

class _CategoryEditorState extends ConsumerState<_CategoryEditor> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late String _icon = widget.existing?.icon.isNotEmpty == true
      ? widget.existing!.icon
      : 'more_horiz';
  late String _color = widget.existing?.color.isNotEmpty == true
      ? widget.existing!.color
      : swatches.first;
  final _formKey = GlobalKey<FormState>();
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    try {
      final store = await ref.read(ledgerStoreProvider.future);
      final e = widget.existing;
      if (e == null) {
        await store.createCategory(
          name: _name.text,
          kind: widget.kind,
          icon: _icon,
          color: _color,
        );
      } else {
        await store.updateCategory(
          e.copyWith(name: _name.text, icon: _icon, color: _color),
        );
      }
      if (mounted) Navigator.pop(context);
    } on Object catch (e, st) {
      setState(() => _error = userMessage(e, st));
    }
  }

  Future<void> _delete() async {
    final c = widget.existing!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${c.name}?'),
        content: const Text(
          'Past transactions keep showing this name. You cannot pick it for new ones.',
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
    await store.deleteCategory(c.id);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final fallback = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: EdgeInsets.only(
        left: Spacing.lg,
        right: Spacing.lg,
        bottom: MediaQuery.viewInsetsOf(context).bottom + Spacing.lg,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.existing == null ? 'New category' : 'Edit category',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: Spacing.lg),
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Category name'),
                validator: (v) {
                  final n = v?.trim().length ?? 0;
                  if (n == 0) return 'Give the category a name';
                  if (n > 40) return 'Use at most 40 characters';
                  return null;
                },
              ),
              const SizedBox(height: Spacing.lg),
              Text('Icon', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: Spacing.sm),
              Wrap(
                spacing: Spacing.sm,
                runSpacing: Spacing.sm,
                children: [
                  for (final e in categoryIcons.entries)
                    InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => setState(() => _icon = e.key),
                      child: Semantics(
                        label: 'Icon ${e.key}',
                        selected: _icon == e.key,
                        child: IconBadge(
                          icon: e.value,
                          size: 36,
                          color: _icon == e.key
                              ? colorFromHex(_color, fallback)
                              : Colors.grey.shade400,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: Spacing.lg),
              Text('Colour', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: Spacing.sm),
              Wrap(
                spacing: Spacing.sm,
                runSpacing: Spacing.sm,
                children: [
                  for (final hex in swatches)
                    InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => setState(() => _color = hex),
                      child: Semantics(
                        label: 'Colour $hex',
                        selected: _color == hex,
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: colorFromHex(hex, fallback),
                            shape: BoxShape.circle,
                            border: _color == hex
                                ? Border.all(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface,
                                    width: 3,
                                  )
                                : null,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: Spacing.lg),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: Spacing.xl),
              Row(
                children: [
                  if (widget.existing != null)
                    TextButton.icon(
                      onPressed: _delete,
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Delete'),
                    ),
                  const Spacer(),
                  FilledButton(onPressed: _save, child: const Text('Save')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
