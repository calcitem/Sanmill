// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:io';
import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

/// Writes [pngBytes] to a temporary file and runs [decode], then deletes it.
Future<void> decodePngBytesWithTempFile(
  Uint8List pngBytes,
  Future<void> Function(XFile file) decode,
) async {
  final Directory tempDir = await getTemporaryDirectory();
  final String path =
      '${tempDir.path}/sanmill_qr_cap_${DateTime.now().millisecondsSinceEpoch}.png';
  final File file = File(path);
  await file.writeAsBytes(pngBytes);
  try {
    await decode(XFile(path));
  } finally {
    if (file.existsSync()) {
      await file.delete();
    }
  }
}
