// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// import_exceptions.dart

part of '../mill.dart';

/// Custom response to throw when importing the game history.
abstract class ImportResponse {}

class ImportFormatException extends FormatException {
  const ImportFormatException([String? source, int? offset])
    : super(source ?? "Cannot import", null, offset);

  @override
  String toString() {
    return message.isEmpty ? "Cannot import" : message;
  }
}
