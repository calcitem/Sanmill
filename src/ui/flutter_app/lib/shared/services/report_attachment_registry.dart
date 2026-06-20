// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// report_attachment_registry.dart

import 'logger.dart';

/// Produces an on-disk file to attach to a crash / error report.
///
/// Implementations return the absolute path of a file to attach, or `null`
/// when there is nothing to contribute (e.g. an empty move list).  Providers
/// are allowed to throw; [ReportAttachmentRegistry] isolates failures so a
/// single faulty provider cannot block the others or the report itself.
typedef ReportAttachmentProvider = Future<String?> Function();

/// Registry of extra files attached to crash / error reports.
///
/// Lives in the shared layer so report handlers (e.g. `SanmillEmailHandler`)
/// stay game-agnostic: feature layers register providers without the handler
/// importing them directly.  This keeps the dependency direction one-way
/// (features -> shared) and makes new attachment sources (move lists, puzzle
/// state, recording sessions, ...) easy to add.
class ReportAttachmentRegistry {
  ReportAttachmentRegistry._();

  static final List<ReportAttachmentProvider> _providers =
      <ReportAttachmentProvider>[];

  /// Registers [provider].  Safe to call repeatedly; duplicates are ignored.
  static void register(ReportAttachmentProvider provider) {
    if (!_providers.contains(provider)) {
      _providers.add(provider);
    }
  }

  /// Removes a previously registered [provider].  Mainly for tests.
  static void unregister(ReportAttachmentProvider provider) {
    _providers.remove(provider);
  }

  /// Clears every registered provider.  Mainly for tests.
  static void clear() {
    _providers.clear();
  }

  /// Number of registered providers.  Mainly for tests.
  static int get providerCount => _providers.length;

  /// Collects attachment paths from every registered provider.
  ///
  /// Null / empty results and failing providers are skipped so a single bad
  /// provider never prevents a report from being sent.  Paths are returned in
  /// registration order with duplicates removed.
  static Future<List<String>> collectPaths() async {
    final List<String> paths = <String>[];
    for (final ReportAttachmentProvider provider in _providers) {
      try {
        final String? path = await provider();
        if (path != null && path.isNotEmpty && !paths.contains(path)) {
          paths.add(path);
        }
      } catch (e) {
        logger.w('[report_attachments] provider failed: $e');
      }
    }
    return paths;
  }
}
