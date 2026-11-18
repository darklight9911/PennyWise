import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/platform/link_opener.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_icon.dart';
import '../../ledger/presentation/day_labels.dart';
import '../../recurring/domain/recurrence.dart';
import '../data/export_api.dart';

enum _Range { thisMonth, lastMonth, thisYear, lastYear, custom }

/// Makes a CSV or PDF file of the user's transactions on the server and
/// opens the download link. Needs a connection.
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
  ExportJob? _job;
  bool _busy = false;
  String? _error;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _applyRange();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
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
    _poll?.cancel();
    setState(() {
      _busy = true;
      _error = null;
      _job = null;
    });
    try {
      final job = await ref
          .read(exportApiProvider)
          .create(format: _format, from: ymd(_from), to: ymd(_to));
      if (!mounted) return;
      setState(() => _job = job);
      if (job.pending) {
        _poll = Timer.periodic(ref.read(exportPollProvider), (_) => _check());
      } else {
        setState(() => _busy = false);
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = switch (e.code) {
          'exports_unavailable' =>
            'Export is not available on this server yet.',
          'too_many' => 'Wait for your other exports to finish.',
          'rate_limited' => 'Too many exports. Try again later.',
          _ when e.isNetworkError => 'No connection. Exports are made on our server, so you need to be online.',
          _ => e.message,
        };
      });
    }
  }

  Future<void> _check() async {
    final job = _job;
    if (job == null) return;
    try {
      final next = await ref.read(exportApiProvider).get(job.id);
      if (!mounted) return;
      setState(() => _job = next);
      if (!next.pending) {
        _poll?.cancel();
        setState(() => _busy = false);
      }
    } on ApiException {
      // Offline for a moment: keep checking.
    }
  }

  Future<void> _open() async {
    // Links last 10 minutes: ask for a fresh one first.
    final job = _job!;
    try {
      final fresh = await ref.read(exportApiProvider).get(job.id);
      if (!mounted) return;
      setState(() => _job = fresh);
      final url = fresh.downloadUrl;
      if (url == null) return;
      final ok = await ref.read(linkOpenerProvider)(Uri.parse(url));
      if (!ok && mounted) {
        setState(() => _error = 'No app could open the file.');
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final job = _job;
    return Scaffold(
      appBar: AppBar(title: const Text('Export')),
      body: ListView(
        padding: const EdgeInsets.all(Spacing.lg),
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
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : () => _pickDate(from: true),
                  icon: const AppIcon(
                    HugeIcons.strokeRoundedCalendar03,
                    size: 18,
                  ),
                  label: Text('From ${dayLabel(ymd(_from), now)}'),
                ),
              ),
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : () => _pickDate(from: false),
                  icon: const AppIcon(
                    HugeIcons.strokeRoundedCalendar03,
                    size: 18,
                  ),
                  label: Text('To ${dayLabel(ymd(_to), now)}'),
                ),
              ),
            ],
          ),
          const SizedBox(height: Spacing.xl),
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
          if (job != null && job.status == 'ready') ...[
            const SizedBox(height: Spacing.lg),
            Card(
              child: ListTile(
                leading: const AppIcon(HugeIcons.strokeRoundedFile02),
                title: Text(job.fileName),
                subtitle: const Text('Ready. Kept for 7 days.'),
                trailing: FilledButton.tonal(
                  onPressed: _open,
                  child: const Text('Open'),
                ),
              ),
            ),
          ],
          if (job != null && job.status == 'failed') ...[
            const SizedBox(height: Spacing.md),
            Text(
              job.error.isEmpty
                  ? 'The file could not be made. Please try again.'
                  : job.error,
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ],
        ],
      ),
    );
  }
}
