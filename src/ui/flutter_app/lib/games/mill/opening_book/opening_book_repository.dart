// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// opening_book_repository.dart
//
// Loads the unified opening-book JSON assets once and exposes the parsed data
// to the move-selection provider and the opening recognizer. Loading is async
// (rootBundle), but every query is synchronous against the in-memory model, so
// the AI hot path never blocks. When the book has not finished loading a lookup
// simply misses and the engine search proceeds, exactly as a book miss would.

import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../../../shared/services/logger.dart';
import 'opening_book_models.dart';

const String _logTag = '[OpeningBookRepository]';

/// Signature for the asset reader; injectable so tests can feed file contents
/// without a Flutter asset bundle.
typedef OpeningBookAssetLoader = Future<String> Function(String assetKey);

class OpeningBookRepository {
  OpeningBookRepository._();

  static final OpeningBookRepository instance = OpeningBookRepository._();

  static const String nmmAsset = 'assets/opening_books/nmm/opening_book.json';
  static const String elFiljaAsset =
      'assets/opening_books/el_filja/opening_book.json';

  /// Overridable for tests; defaults to the Flutter asset bundle.
  OpeningBookAssetLoader assetLoader = rootBundle.loadString;

  OpeningBookData? _nineMensMorris;
  OpeningBookData? _elFilja;
  Future<void>? _loading;

  bool get isLoaded => _nineMensMorris != null || _elFilja != null;

  OpeningBookData? get nineMensMorris => _nineMensMorris;
  OpeningBookData? get elFilja => _elFilja;

  /// Loads both variant books once. Safe to call repeatedly and concurrently:
  /// the first call performs the work and later calls await the same future.
  Future<void> ensureLoaded() {
    return _loading ??= _loadAll();
  }

  Future<void> _loadAll() async {
    _nineMensMorris = await _loadOne(nmmAsset);
    _elFilja = await _loadOne(elFiljaAsset);
    logger.i(
      '$_logTag loaded: nmm=${_nineMensMorris?.openings.length ?? 0} openings/'
      '${_nineMensMorris?.oracle.length ?? 0} oracle, '
      'el_filja=${_elFilja?.oracle.length ?? 0} oracle',
    );
  }

  Future<OpeningBookData?> _loadOne(String assetKey) async {
    try {
      final String raw = await assetLoader(assetKey);
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        logger.w('$_logTag $assetKey is not a JSON object; ignoring.');
        return null;
      }
      return OpeningBookData.fromJson(decoded);
    } on Object catch (e) {
      // A missing or malformed book is non-fatal: the AI falls back to search
      // and recognition stays inactive.
      logger.w('$_logTag could not load $assetKey: $e');
      return null;
    }
  }

  /// Canonical FEN -> best-move table for the requested variant.
  Map<String, List<String>> oracleFor({required bool isElFilja}) {
    final OpeningBookData? data = isElFilja ? _elFilja : _nineMensMorris;
    return data?.oracle ?? const <String, List<String>>{};
  }

  /// Named opening lines for the requested variant (empty when unavailable).
  List<OpeningEntry> openingsFor({required bool isElFilja}) {
    final OpeningBookData? data = isElFilja ? _elFilja : _nineMensMorris;
    return data?.openings ?? const <OpeningEntry>[];
  }

  /// Test-only reset so suites can re-stub [assetLoader] and reload.
  void resetForTest() {
    _nineMensMorris = null;
    _elFilja = null;
    _loading = null;
  }
}
