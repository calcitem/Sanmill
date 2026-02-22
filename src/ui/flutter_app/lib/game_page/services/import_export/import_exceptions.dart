// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// import_exceptions.dart

part of '../mill.dart';

/// Custom response to throw when importing the game history.
abstract class ImportResponse {}

/// Structured error codes for import failures that require localization.
enum ImportErrorCode { noValidMovesFound }

class ImportFormatException extends FormatException {
  const ImportFormatException([String? source, int? offset])
    : code = null,
      super(source ?? "Cannot import", null, offset);

  /// Creates an exception carrying a structured [code] rather than a raw
  /// English message, so the UI layer can display a localized string.
  const ImportFormatException.coded(this.code)
    : super("Cannot import", null, null);

  /// Optional structured error code for localization in the UI layer.
  final ImportErrorCode? code;

  @override
  String toString() {
    return message.isEmpty ? "Cannot import" : message;
  }
}
