// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// native_methods.dart

import 'package:flutter/services.dart';
import 'logger.dart';

const MethodChannel _platform = MethodChannel('com.calcitem.sanmill/native');

Future<String?> readContentUri(Uri uri) async {
  try {
    final String? result = await _platform.invokeMethod<String>(
        'readContentUri', <String, String>{'uri': uri.toString()});
    return result;
  } on PlatformException catch (e) {
    logger.e("Failed to read content URI: ${e.message}");
    return null;
  }
}
