// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// array_helper.dart

/// List Extension
///
/// Extends the List Object by the method [lastF].
extension ListExtension<E> on List<E> {
  /// Returns the last value of the list.
  ///
  /// It is comparable to [last] but it doesn't iterate through every entry (performance).
  /// It will return null if the list [isEmpty].
  E? get lastF {
    if (isNotEmpty) {
      return this[length - 1];
    }
    return null;
  }
}
