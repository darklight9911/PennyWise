import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/database/local_database.dart';

/// Where receipt photos are kept on the phone. Tests use memory.
abstract class ReceiptFiles {
  /// Saves the photo and returns its path.
  Future<String> write(String id, String extension, Uint8List bytes);
  Future<Uint8List?> read(String path);
  Future<void> delete(String path);
}

/// App-private storage, in a folder next to the database (deleted on logout).
class DiskReceiptFiles implements ReceiptFiles {
  DiskReceiptFiles(this._dir);

  final Future<Directory> Function() _dir;

  @override
  Future<String> write(String id, String extension, Uint8List bytes) async {
    final dir = await _dir();
    await dir.create(recursive: true);
    final f = File(p.join(dir.path, '$id.$extension'));
    await f.writeAsBytes(bytes, flush: true);
    return f.path;
  }

  @override
  Future<Uint8List?> read(String path) async {
    final f = File(path);
    return await f.exists() ? f.readAsBytes() : null;
  }

  @override
  Future<void> delete(String path) async {
    final f = File(path);
    if (await f.exists()) await f.delete();
  }
}

/// In memory, for tests.
class MemoryReceiptFiles implements ReceiptFiles {
  final files = <String, Uint8List>{};

  @override
  Future<String> write(String id, String extension, Uint8List bytes) async {
    final path = 'mem://$id.$extension';
    files[path] = bytes;
    return path;
  }

  @override
  Future<Uint8List?> read(String path) async => files[path];

  @override
  Future<void> delete(String path) async => files.remove(path);
}

final receiptFilesProvider = Provider<ReceiptFiles>(
  (ref) => DiskReceiptFiles(ref.watch(localDatabaseProvider).receiptsDir),
);
