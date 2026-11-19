import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/currencies.dart';
import '../../../core/widgets/app_icon.dart';

/// Opens a searchable currency picker sheet and returns the picked ISO code,
/// or null if dismissed.
Future<String?> showCurrencyPicker(
  BuildContext context, {
  required String title,
  String? subtitle,
  required String selected,
  String? detectedCode,
  List<String> accountCodes = const [],
  Map<String, String> contextHints = const {},
}) {
  final scheme = Theme.of(context).colorScheme;
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: scheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.card)),
    ),
    builder: (context) => CurrencyPickerSheet(
      title: title,
      subtitle: subtitle,
      selected: selected,
      detectedCode: detectedCode,
      accountCodes: accountCodes,
      contextHints: contextHints,
      onSelect: (code) => Navigator.pop(context, code),
    ),
  );
}

/// Searchable bottom-sheet body for picking an ISO 4217 currency.
///
/// Pins [selected], [detectedCode] and [accountCodes] at the top when the
/// search box is empty, and optionally renders a sticky [footer] below the list.
class CurrencyPickerSheet extends StatefulWidget {
  const CurrencyPickerSheet({
    super.key,
    required this.title,
    this.subtitle,
    required this.selected,
    this.detectedCode,
    this.accountCodes = const [],
    this.contextHints = const {},
    required this.onSelect,
    this.footer,
    this.enabled = true,
  });

  final String title;
  final String? subtitle;
  final String selected;
  final String? detectedCode;
  final List<String> accountCodes;
  final Map<String, String> contextHints;
  final ValueChanged<String> onSelect;
  final Widget? footer;
  final bool enabled;

  @override
  State<CurrencyPickerSheet> createState() => _CurrencyPickerSheetState();
}

sealed class _ListEntry {
  const _ListEntry();
}

final class _SectionEntry extends _ListEntry {
  const _SectionEntry(this.title);
  final String title;
}

final class _CurrencyEntry extends _ListEntry {
  const _CurrencyEntry(this.info, {this.hint});
  final CurrencyInfo info;
  final String? hint;
}

class _CurrencyPickerSheetState extends State<CurrencyPickerSheet> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _clearSearch() {
    _search.clear();
    setState(() => _query = '');
  }

  List<_ListEntry> _buildEntries() {
    final q = _query.trim();
    final selectedUpper = widget.selected.trim().toUpperCase();

    if (q.isNotEmpty) {
      final matches = searchCurrencies(q);
      final inCatalog = allCurrencies.any((c) => c.code == selectedUpper);
      final extra =
          !inCatalog && selectedUpper.toLowerCase().contains(q.toLowerCase())
          ? [currencyInfo(selectedUpper)]
          : const <CurrencyInfo>[];
      return [
        for (final c in [...extra, ...matches]) _CurrencyEntry(c),
      ];
    }

    final suggested = suggestedCurrencyCodes(
      selected: widget.selected,
      detectedCode: widget.detectedCode,
      accountCodes: widget.accountCodes,
    );
    final suggestedSet = suggested.toSet();
    final accountSet = {
      for (final c in widget.accountCodes) c.trim().toUpperCase(),
    };
    final detectedUpper = widget.detectedCode?.trim().toUpperCase();

    String? hintFor(String code) {
      final custom = widget.contextHints[code];
      if (custom != null) return custom;
      if (code == selectedUpper) return 'Current';
      if (accountSet.contains(code)) return 'In your accounts';
      if (code == detectedUpper) return 'Detected on phone';
      return null;
    }

    return [
      const _SectionEntry('Suggested'),
      for (final code in suggested)
        _CurrencyEntry(currencyInfo(code), hint: hintFor(code)),
      const _SectionEntry('All currencies'),
      for (final c in allCurrencies)
        if (!suggestedSet.contains(c.code)) _CurrencyEntry(c),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final mq = MediaQuery.of(context);
    final available = (mq.size.height - mq.viewInsets.bottom - mq.padding.top)
        .clamp(0.0, mq.size.height);
    final sheetHeight = available <= 240.0
        ? available
        : (available * 0.85).clamp(240.0, available);

    final entries = _buildEntries();
    final selectedUpper = widget.selected.trim().toUpperCase();

    return Padding(
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: SizedBox(
        height: sheetHeight,
        child: SafeArea(
          top: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Spacing.xl,
                  0,
                  Spacing.xl,
                  Spacing.md,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.title, style: theme.textTheme.titleLarge),
                    if (widget.subtitle != null) ...[
                      const SizedBox(height: Spacing.xs),
                      Text(
                        widget.subtitle!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const SizedBox(height: Spacing.md),
                    TextField(
                      controller: _search,
                      enabled: widget.enabled,
                      textInputAction: TextInputAction.search,
                      onChanged: (v) => setState(() => _query = v),
                      decoration: InputDecoration(
                        hintText: 'Search currency, country or symbol',
                        prefixIcon: const Padding(
                          padding: EdgeInsets.all(Spacing.md),
                          child: AppIcon(HugeIcons.strokeRoundedSearch01),
                        ),
                        suffixIcon: _query.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Clear search',
                                icon: const AppIcon(
                                  HugeIcons.strokeRoundedCancel01,
                                ),
                                onPressed: widget.enabled ? _clearSearch : null,
                              ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: entries.isEmpty
                    ? Center(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(Spacing.xl),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'No currency matches "${_query.trim()}"',
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: Spacing.sm),
                              TextButton(
                                onPressed: _clearSearch,
                                child: const Text('Clear search'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.builder(
                        itemCount: entries.length,
                        itemBuilder: (context, index) {
                          final entry = entries[index];
                          switch (entry) {
                            case _SectionEntry(:final title):
                              return Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  Spacing.xl,
                                  Spacing.md,
                                  Spacing.xl,
                                  Spacing.xs,
                                ),
                                child: Text(
                                  title,
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              );
                            case _CurrencyEntry(:final info, :final hint):
                              return _CurrencyTile(
                                info: info,
                                hint: hint,
                                selected: info.code == selectedUpper,
                                enabled: widget.enabled,
                                onTap: () => widget.onSelect(info.code),
                              );
                          }
                        },
                      ),
              ),
              if (widget.footer != null) ...[
                const Divider(height: 1),
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: sheetHeight * 0.45),
                  child: SingleChildScrollView(child: widget.footer),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CurrencyTile extends StatelessWidget {
  const _CurrencyTile({
    required this.info,
    required this.hint,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final CurrencyInfo info;
  final String? hint;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final subtitle = hint == null ? info.name : '$hint · ${info.name}';

    return ListTile(
      enabled: enabled,
      selected: selected,
      selectedTileColor: scheme.secondaryContainer.withValues(alpha: 0.22),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: Spacing.xl,
        vertical: Spacing.xs,
      ),
      onTap: enabled ? onTap : null,
      leading: Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(Spacing.xs),
        decoration: BoxDecoration(
          color: selected
              ? scheme.secondaryContainer
              : theme.scaffoldBackgroundColor,
          borderRadius: BorderRadius.circular(Radii.button),
          border: Border.all(color: selected ? scheme.primary : scheme.outline),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: ExcludeSemantics(
            child: Text(
              info.symbol,
              style: theme.textTheme.titleMedium?.copyWith(
                color: selected
                    ? scheme.onSecondaryContainer
                    : scheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
      title: Text(
        info.code,
        style: theme.textTheme.titleMedium?.copyWith(
          color: selected ? scheme.primary : scheme.onSurface,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
      trailing: selected
          ? AppIcon(
              HugeIcons.strokeRoundedTick02,
              size: 20,
              color: scheme.primary,
              strokeWidth: AppIcon.selectedStroke,
              semanticLabel: 'Selected',
            )
          : null,
    );
  }
}

/// Form-styled tap target that displays the selected currency and opens a picker.
class CurrencyField extends StatelessWidget {
  const CurrencyField({
    super.key,
    required this.label,
    required this.value,
    this.helperText,
    this.errorText,
    this.enabled = true,
    this.onTap,
  });

  final String label;
  final String value;
  final String? helperText;
  final String? errorText;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final info = currencyInfo(value);
    final display = currencyLabel(value);
    final semanticLabel = [label, display, ?helperText, ?errorText].join(', ');

    return Semantics(
      button: enabled,
      enabled: enabled,
      label: semanticLabel,
      excludeSemantics: true,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(Radii.button),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: InputDecorator(
            isEmpty: false,
            decoration: InputDecoration(
              labelText: label,
              helperText: helperText,
              helperMaxLines: 2,
              errorText: errorText,
              enabled: enabled,
              suffixIcon: enabled
                  ? const Padding(
                      padding: EdgeInsets.all(Spacing.md),
                      child: AppIcon(
                        HugeIcons.strokeRoundedArrowDown01,
                        size: 20,
                      ),
                    )
                  : null,
            ),
            child: Row(
              children: [
                Container(
                  constraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 24,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: Spacing.xs,
                    vertical: 2,
                  ),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: theme.scaffoldBackgroundColor,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: scheme.outline),
                  ),
                  child: Text(
                    info.symbol,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: enabled
                          ? scheme.onSurface
                          : scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: Spacing.sm),
                Expanded(
                  child: Text(
                    display,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: enabled
                          ? scheme.onSurface
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
