// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

/// Web stub — QR screen capture is not used in the browser build.
Future<void> decodePngBytesWithTempFile(
  Uint8List pngBytes,
  Future<void> Function(XFile file) decode,
) async {
  throw UnsupportedError('QR screen capture temp file is not available on web');
}
