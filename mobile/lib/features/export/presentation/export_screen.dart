import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/responsive_layout.dart';
import '../../ledger/presentation/day_labels.dart';
import '../../recurring/domain/recurrence.dart';
import '../../auth/application/auth_controller.dart';
import '../../ledger/application/ledger_providers.dart';
import '../data/local_export.dart';

enum _Range { thisMonth, lastMonth, thisYear, lastYear, custom }

/// Makes a CSV or PDF file of the user's transactions on the phone and
/// hands it to the share sheet (save to Files or Drive, email, chat...).
/// Works offline and without an account.
class ExportScreen extends ConsumerStatefulWidget {
  const ExportScreen({super.key});

  @override
  ConsumerState<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends ConsumerState<ExportScreen> {
  String _format = 'pdf';
  _Range _range = _Range.thisMonth;
  late DateTime _from;
  late DateTime _to;
  ({Uint8List bytes, String name, String mime})? _file;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _applyRange();
  }

  void _applyRange() {
    final now = DateTime.now();
    final (from, to) = switch (_range) {
      _Range.thisMonth => (
        DateTime(now.year, now.month, 1),
        DateTime(now.year, now.month + 1, 0),
      ),
      _Range.lastMonth => (
        DateTime(now.year, now.month - 1, 1),
        DateTime(now.year, now.month, 0),
      ),
      _Range.thisYear => (DateTime(now.year, 1, 1), DateTime(now.year, 12, 31)),
      _Range.lastYear => (
        DateTime(now.year - 1, 1, 1),
        DateTime(now.year - 1, 12, 31),
      ),
      _Range.custom => (_from, _to),
    };
    _from = from;
    _to = to;
  }

  Future<void> _pickDate({required bool from}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: from ? _from : _to,
      firstDate: DateTime(2000),
      lastDate: DateTime(DateTime.now().year + 1, 12, 31),
    );
    if (picked == null) return;
    setState(() {
      _range = _Range.custom;
      if (from) {
        _from = picked;
        if (_to.isBefore(_from)) _to = _from;
      } else {
        _to = picked;
        if (_from.isAfter(_to)) _from = _to;
      }
    });
  }

  Future<void> _create() async {
    setState(() {
      _busy = true;
      _error = null;
      _file = null;
    });
    try {
      final from = ymd(_from), to = ymd(_to);
      final base = ref.read(baseCurrencyProvider);
      final store = await ref.read(ledgerStoreProvider.future);
      final rows = await loadExportRows(store.db, from: from, to: to);
      final Uint8List bytes;
      if (_format == 'csv') {
        bytes = utf8.encode(buildCsv(rows, base));
      } else {
        final fonts = await loadPdfFonts();
        bytes = await buildPdf(
          rows: rows,
          base: base,
          from: from,
          to: to,
          regular: fonts.regular,
          bold: fonts.bold,
        );
      }
      final file = (
        bytes: bytes,
        name: exportFileName(_format, from, to),
        mime: _format == 'csv' ? 'text/csv' : 'application/pdf',
      );
      if (!mounted) return;
      setState(() => _file = file);
      await _share();
    } on Object catch (e, st) {
      if (mounted) setState(() => _error = userMessage(e, st));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share() async {
    final file = _file;
    if (file == null) return;
    try {
      await ref.read(fileSharerProvider)(file.bytes, file.name, file.mime);
    } on Object catch (e, st) {
      if (mounted) setState(() => _error = userMessage(e, st));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final file = _file;
    final hPad = ResponsiveLayout.horizontalPadding(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Export')),
      body: ResponsiveBody(
        maxWidth: ContentWidths.form,
        child: ListView(
          padding: EdgeInsets.symmetric(horizontal: hPad, vertical: Spacing.md),
          children: [
            Text('File type', style: theme.textTheme.titleSmall),
            const SizedBox(height: Spacing.sm),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'pdf', label: Text('PDF statement')),
                ButtonSegment(value: 'csv', label: Text('CSV spreadsheet')),
              ],
              selected: {_format},
              onSelectionChanged: _busy
                  ? null
                  : (s) => setState(() => _format = s.single),
            ),
            const SizedBox(height: Spacing.sm),
            Text(
              _format == 'pdf'
                  ? 'Totals, top categories and every transaction, ready to print or share.'
                  : 'One row per transaction, for Excel, Google Sheets or Numbers.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: Spacing.xl),
            Text('Period', style: theme.textTheme.titleSmall),
            const SizedBox(height: Spacing.sm),
            Wrap(
              spacing: Spacing.sm,
              runSpacing: Spacing.sm,
              children: [
                for (final r in [
                  _Range.thisMonth,
                  _Range.lastMonth,
                  _Range.thisYear,
                  _Range.lastYear,
                ])
                  ChoiceChip(
                    label: Text(switch (r) {
                      _Range.thisMonth => 'This month',
                      _Range.lastMonth => 'Last month',
                      _Range.thisYear => 'This year',
                      _ => 'Last year',
                    }),
                    selected: _range == r,
                    onSelected: _busy
                        ? null
                        : (_) => setState(() {
                            _range = r;
                            _applyRange();
                          }),
                  ),
              ],
            ),
            const SizedBox(height: Spacing.sm),
            LayoutBuilder(
              builder: (context, constraints) {
                final fromBtn = OutlinedButton.icon(
                  onPressed: _busy ? null : () => _pickDate(from: true),
                  icon: const AppIcon(
                    HugeIcons.strokeRoundedCalendar03,
                    size: 18,
                  ),
                  label: Text('From ${dayLabel(ymd(_from), now)}'),
                );
                final toBtn = OutlinedButton.icon(
                  onPressed: _busy ? null : () => _pickDate(from: false),
                  icon: const AppIcon(
                    HugeIcons.strokeRoundedCalendar03,
                    size: 18,
                  ),
                  label: Text('To ${dayLabel(ymd(_to), now)}'),
                );
                if (constraints.maxWidth < 340) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      fromBtn,
                      const SizedBox(height: Spacing.sm),
                      toBtn,
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: fromBtn),
                    const SizedBox(width: Spacing.sm),
                    Expanded(child: toBtn),
                  ],
                );
              },
            ),
            const SizedBox(height: Spacing.lg),
            FilledButton(
              onPressed: _busy ? null : _create,
              child: Text(_busy ? 'Making your file…' : 'Make file'),
            ),
            if (_busy) ...[
              const SizedBox(height: Spacing.md),
              const LinearProgressIndicator(),
            ],
            if (_error != null) ...[
              const SizedBox(height: Spacing.md),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
            if (file != null) ...[
              const SizedBox(height: Spacing.lg),
              Card(
                child: ListTile(
                  leading: const AppIcon(HugeIcons.strokeRoundedFile02),
                  title: Text(file.name),
                  subtitle: const Text('Made on this phone.'),
                  trailing: FilledButton.tonal(
                    onPressed: _share,
                    child: const Text('Share'),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
