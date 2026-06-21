// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import '../../game_page/services/transform/transform.dart';

/// Normalises volatile Mill FEN counters used by opening-book keys.
///
/// Field 14 (`formed_mills`) and field 15 (`rule50`) are zeroed so that
/// otherwise-equivalent positions share a single book key.
String normalizeOpeningBookFen(String fen) {
  final List<String> fields = fen.split(' ');
  if (fields.length >= 16) {
    fields[14] = '0';
    fields[15] = '0';
  }
  return fields.join(' ');
}

/// Returns the lexicographically smallest FEN in the 16-way symmetry orbit.
String canonicalOpeningBookFen(String fen) {
  final String normalized = normalizeOpeningBookFen(fen);
  String canonical = normalized;
  for (final TransformationType type in TransformationType.values) {
    final String candidate = normalizeOpeningBookFen(
      transformFEN(normalized, type),
    );
    if (candidate.compareTo(canonical) < 0) {
      canonical = candidate;
    }
  }
  return canonical;
}

/// Returns the symmetry that maps [fen] onto [canonicalOpeningBookFen].
///
/// When a position has a non-trivial stabiliser several transforms reach the
/// canonical FEN; the first one in [TransformationType.values] order is
/// returned so the result is deterministic.
TransformationType symmetryToCanonical(String fen) {
  final String normalized = normalizeOpeningBookFen(fen);
  final String canonical = canonicalOpeningBookFen(normalized);
  for (final TransformationType type in TransformationType.values) {
    final String candidate = normalizeOpeningBookFen(
      transformFEN(normalized, type),
    );
    if (candidate == canonical) {
      return type;
    }
  }
  throw StateError('no symmetry maps $fen to its canonical opening-book FEN');
}

/// Looks up [fen] in a canonical opening book that stores one representative
/// best-move line per symmetry orbit.
///
/// The query position is mapped to its canonical key, then the stored line is
/// rotated back into the query's coordinate frame with the inverse symmetry.
/// Returns null when no orbit matches.
List<String>? lookupCanonicalOpeningBook(
  Map<String, List<String>> book,
  String fen,
) {
  final String normalized = normalizeOpeningBookFen(fen);
  final String canonicalKey = canonicalOpeningBookFen(normalized);
  final List<String>? canonicalMoves = book[canonicalKey];
  if (canonicalMoves == null || canonicalMoves.isEmpty) {
    return null;
  }
  final TransformationType toCanonical = symmetryToCanonical(normalized);
  final List<int> fromCanonical = inverseTransformMap(
    getTransformMap(toCanonical),
  );
  return canonicalMoves
      .map((String move) => transformMoveNotationWithMap(move, fromCanonical))
      .toList();
}
