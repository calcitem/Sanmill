// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// test_native_library.dart
//
// Shared helper for tests that exercise the Rust/FRB kernel on the host VM.
// `flutter test` runs from the flutter_app package root, so the workspace
// `target/debug` directory produced by `cargo build -p rust_lib_sanmill`
// sits three levels up.

import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show ExternalLibrary;
import 'package:sanmill/src/rust/frb_generated.dart';

/// Locates the host-platform `rust_lib_sanmill` dynamic library built by
/// `cargo build -p rust_lib_sanmill` (debug profile).
File nativeLibraryFile() {
  final String fileName = Platform.isWindows
      ? 'rust_lib_sanmill.dll'
      : Platform.isMacOS
      ? 'librust_lib_sanmill.dylib'
      : 'librust_lib_sanmill.so';
  return File('../../../target/debug/$fileName');
}

/// Non-null skip reason when the native library has not been built yet.
/// Pass as `skip:` to tests that need the Rust kernel.
String? nativeLibrarySkipReason() {
  return nativeLibraryFile().existsSync()
      ? null
      : 'Run `cargo build -p rust_lib_sanmill` before this FFI-backed test.';
}

bool _initialized = false;

/// Initializes the FRB bridge against the locally built native library.
/// No-op when already initialized or when the library is missing (the
/// dependent tests are expected to be skipped via [nativeLibrarySkipReason]).
Future<void> initRustLibForTests() async {
  if (_initialized || nativeLibrarySkipReason() != null) {
    return;
  }
  await RustLib.init(
    externalLibrary: ExternalLibrary.open(nativeLibraryFile().absolute.path),
  );
  _initialized = true;
}

/// Tears the FRB bridge down again (call from `tearDownAll`).
void disposeRustLibForTests() {
  if (_initialized) {
    RustLib.dispose();
    _initialized = false;
  }
}
