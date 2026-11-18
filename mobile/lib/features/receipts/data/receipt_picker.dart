import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

/// A photo chosen by the user, already made smaller.
typedef PickedPhoto = ({Uint8List bytes, String contentType});

enum PhotoSource { camera, gallery }

/// Takes or chooses a photo. Null if the user cancelled. Tests replace it.
typedef PhotoPicker = Future<PickedPhoto?> Function(PhotoSource source);

final photoPickerProvider = Provider<PhotoPicker>((ref) => _pick);

Future<PickedPhoto?> _pick(PhotoSource source) async {
  // The plugin shrinks and re-compresses the photo (JPEG), which keeps
  // receipts readable at a few hundred KB.
  final file = await ImagePicker().pickImage(
    source: source == PhotoSource.camera
        ? ImageSource.camera
        : ImageSource.gallery,
    maxWidth: 1600,
    maxHeight: 1600,
    imageQuality: 75,
  );
  if (file == null) return null;
  final bytes = await file.readAsBytes();
  final png =
      file.name.toLowerCase().endsWith('.png') || file.mimeType == 'image/png';
  return (bytes: bytes, contentType: png ? 'image/png' : 'image/jpeg');
}
