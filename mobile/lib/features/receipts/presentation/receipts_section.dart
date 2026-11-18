import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/database/app_database.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_icon.dart';
import '../../ledger/application/ledger_providers.dart';
import '../data/receipt_picker.dart';
import '../data/receipt_store.dart';
import '../data/receipt_sync.dart';

const _thumb = 76.0;

/// Receipt photos of a transaction: thumbnails, "Add photo" (camera or
/// gallery) and a full-screen view. For a transaction that is not saved
/// yet ([transactionId] null), photos wait in [pending] and the form adds
/// them after saving.
class ReceiptsSection extends ConsumerWidget {
  const ReceiptsSection({
    super.key,
    required this.transactionId,
    required this.pending,
    required this.onPendingChanged,
  });

  final String? transactionId;
  final List<PickedPhoto> pending;
  final ValueChanged<List<PickedPhoto>> onPendingChanged;

  Future<void> _add(BuildContext context, WidgetRef ref, int count) async {
    final messenger = ScaffoldMessenger.of(context);
    final source = await showModalBottomSheet<PhotoSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const AppIcon(HugeIcons.strokeRoundedCamera01),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(context, PhotoSource.camera),
            ),
            ListTile(
              leading: const AppIcon(HugeIcons.strokeRoundedImage01),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(context, PhotoSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    final PickedPhoto? photo;
    try {
      photo = await ref.read(photoPickerProvider)(source);
    } on Object {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not open the camera or gallery.')),
      );
      return;
    }
    if (photo == null) return;
    if (photo.bytes.length > maxReceiptBytes) {
      messenger.showSnackBar(
        const SnackBar(content: Text('This photo is too large (over 2 MB).')),
      );
      return;
    }
    final id = transactionId;
    if (id == null) {
      onPendingChanged([...pending, photo]);
      return;
    }
    try {
      final store = await ref.read(receiptStoreProvider.future);
      await store.add(id, photo.bytes, photo.contentType);
    } on ReceiptException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = transactionId;
    final saved = id == null
        ? const <Receipt>[]
        : (ref.watch(receiptsProvider(id)).value ?? const <Receipt>[]);
    final count = saved.length + pending.length;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Receipts ($count/$maxReceiptsPerTransaction)',
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: Spacing.sm),
        Wrap(
          spacing: Spacing.sm,
          runSpacing: Spacing.sm,
          children: [
            for (final r in saved) _SavedThumb(receipt: r),
            for (var i = 0; i < pending.length; i++)
              _Frame(
                semantics:
                    'Receipt photo ${saved.length + i + 1}, saved with the transaction',
                onTap: () => _openPending(context, i),
                child: Image.memory(pending[i].bytes, fit: BoxFit.cover),
              ),
            if (count < maxReceiptsPerTransaction)
              SizedBox.square(
                dimension: _thumb,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(padding: EdgeInsets.zero),
                  onPressed: () => _add(context, ref, count),
                  // Shrinks with very large text instead of overflowing.
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AppIcon(HugeIcons.strokeRoundedCamera01),
                          SizedBox(height: 4),
                          Text('Add photo'),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  void _openPending(BuildContext context, int i) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _Viewer(
          load: () async => pending[i].bytes,
          onDelete: () async => onPendingChanged([...pending]..removeAt(i)),
        ),
      ),
    );
  }
}

class _Frame extends StatelessWidget {
  const _Frame({
    required this.child,
    required this.onTap,
    required this.semantics,
    this.badge,
  });

  final Widget child;
  final VoidCallback onTap;
  final String semantics;
  final Widget? badge;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semantics,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: SizedBox.square(
            dimension: _thumb,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: child,
                ),
                if (badge != null)
                  Positioned(right: 4, bottom: 4, child: badge!),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SavedThumb extends ConsumerWidget {
  const _SavedThumb({required this.receipt});

  final Receipt receipt;

  Future<Uint8List?> _bytes(WidgetRef ref) async {
    final store = await ref.read(receiptStoreProvider.future);
    return store.localBytes(receipt);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final waiting = receipt.status == 'local';
    return _Frame(
      semantics: waiting ? 'Receipt photo, waiting to upload' : 'Receipt photo',
      badge: waiting
          ? Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const AppIcon(
                HugeIcons.strokeRoundedCloudUpload,
                size: 14,
                color: Colors.white,
              ),
            )
          : null,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => _Viewer(
            load: () async => _bytes(ref),
            url: receipt.localPath == null
                ? () => ReceiptSync.viewUrl(ref.read(dioProvider), receipt.id)
                : null,
            onDelete: () async {
              final store = await ref.read(receiptStoreProvider.future);
              await store.delete(receipt);
            },
          ),
        ),
      ),
      child: FutureBuilder<Uint8List?>(
        future: _bytes(ref),
        builder: (context, snap) => snap.data != null
            ? Image.memory(snap.data!, fit: BoxFit.cover)
            : const Center(child: AppIcon(HugeIcons.strokeRoundedCloud)),
      ),
    );
  }
}

/// A receipt filling the screen; pinch to zoom.
class _Viewer extends StatefulWidget {
  const _Viewer({required this.load, required this.onDelete, this.url});

  final Future<Uint8List?> Function() load;
  final Future<String> Function()? url; // for photos only on the server
  final Future<void> Function() onDelete;

  @override
  State<_Viewer> createState() => _ViewerState();
}

class _ViewerState extends State<_Viewer> {
  late final Future<Object?> _image = _resolve();

  Future<Object?> _resolve() async {
    final bytes = await widget.load();
    if (bytes != null) return bytes;
    return widget.url == null ? null : await widget.url!();
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this photo?'),
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
    await widget.onDelete();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Receipt'),
        actions: [
          IconButton(
            tooltip: 'Delete photo',
            icon: const AppIcon(
              HugeIcons.strokeRoundedDelete02,
              color: Colors.white,
            ),
            onPressed: _delete,
          ),
        ],
      ),
      body: FutureBuilder<Object?>(
        future: _image,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final img = snap.data;
          final Widget child = switch (img) {
            Uint8List b => Image.memory(b, fit: BoxFit.contain),
            String url => Image.network(
              url,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) =>
                  const _Message('Could not load the photo.'),
            ),
            _ => _Message(
              snap.error is ApiException &&
                      (snap.error! as ApiException).isNetworkError
                  ? 'This photo is on the server. Connect to the internet to see it.'
                  : 'Could not load the photo.',
            ),
          };
          return InteractiveViewer(maxScale: 5, child: Center(child: child));
        },
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(Spacing.xl),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: const TextStyle(color: Colors.white),
    ),
  );
}
