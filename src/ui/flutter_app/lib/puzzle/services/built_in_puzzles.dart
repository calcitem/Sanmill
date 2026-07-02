// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// built_in_puzzles.dart
//
// Loads the built-in puzzle pack bundled with the app. The pack is
// generated offline from the Malom Nine Men's Morris perfect-play database
// by `tgf puzzle-gen` (see `crates/tgf-cli/src/mill_puzzle/`) and committed
// as a plain `.sanmill_puzzles` JSON asset, so no native/FFI access to the
// (multi-gigabyte) perfect database is needed at app runtime.

import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../../shared/services/logger.dart';
import '../models/puzzle_models.dart';

const String _logTag = '[BuiltInPuzzles]';

/// Signature for the asset reader; injectable so tests can feed file
/// contents without a Flutter asset bundle.
typedef BuiltInPuzzlesAssetLoader = Future<String> Function(String assetKey);

/// Path to the bundled built-in puzzle pack.
const String builtInPuzzlesAsset =
    'assets/puzzles/malom_perfect_db_puzzles.sanmill_puzzles';

/// Overridable for tests; defaults to the Flutter asset bundle.
BuiltInPuzzlesAssetLoader builtInPuzzlesAssetLoader = rootBundle.loadString;

/// Get the collection of built-in puzzles bundled with the app.
///
/// A missing or malformed asset is non-fatal: the app degrades to shipping
/// no built-in puzzles rather than failing to start, and users can still
/// create or import their own custom puzzles.
Future<List<PuzzleInfo>> getBuiltInPuzzles() async {
  try {
    final String raw = await builtInPuzzlesAssetLoader(builtInPuzzlesAsset);
    final Object? decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      logger.w('$_logTag $builtInPuzzlesAsset is not a JSON object; ignoring.');
      return <PuzzleInfo>[];
    }
    final Object? rawPuzzles = decoded['puzzles'];
    if (rawPuzzles is! List<dynamic>) {
      logger.w(
        '$_logTag $builtInPuzzlesAsset has no "puzzles" array; ignoring.',
      );
      return <PuzzleInfo>[];
    }
    final List<PuzzleInfo> puzzles = rawPuzzles
        .map((dynamic e) => PuzzleInfo.fromJson(e as Map<String, dynamic>))
        .toList();
    logger.i('$_logTag loaded ${puzzles.length} built-in puzzles');
    return puzzles;
  } on Object catch (e) {
    // A missing or malformed pack must never block app startup.
    logger.w('$_logTag could not load $builtInPuzzlesAsset: $e');
    return <PuzzleInfo>[];
  }
}
