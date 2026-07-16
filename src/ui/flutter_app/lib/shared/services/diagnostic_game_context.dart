// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

/// Late-bound bridge that keeps the generic diagnostic layer independent of
/// the current game implementation.
class DiagnosticGameContext {
  const DiagnosticGameContext._();

  static Map<String, dynamic> Function()? _capture;
  static bool Function(Map<String, dynamic> game)? _restore;

  static void register({
    required Map<String, dynamic> Function() capture,
    required bool Function(Map<String, dynamic> game) restore,
  }) {
    _capture = capture;
    _restore = restore;
  }

  static Map<String, dynamic> capture() {
    try {
      return Map<String, dynamic>.from(
        _capture?.call() ?? const <String, dynamic>{},
      );
    } on Object {
      return <String, dynamic>{};
    }
  }

  static bool restore(Map<String, dynamic> game) {
    try {
      return _restore?.call(Map<String, dynamic>.from(game)) ?? false;
    } on Object {
      return false;
    }
  }
}
