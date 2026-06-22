// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// ignore_for_file: avoid_classes_with_only_static_members

// mill_opening_recognizer.dart
//
// Stateless real-time opening recognition for the placement phase.
//
// Given the ordered list of placement moves played so far (removals filtered
// out), it identifies which named opening the game is following and returns the
// metadata the UI needs (name, source, notes, blunder/response hints, next book
// move). Recognition is symmetry-aware over Sanmill's full 16-element board
// group, so a rotated/reflected variant is matched as the same opening.
//
// Three match modes, in priority order:
//   * exact       : the played moves are an in-order prefix of an opening line.
//   * transposition: the same squares were occupied by each side but in a
//                    different order (set match) -> still the same position.
//   * deviation   : a previously-followed line was left, but a named
//                    branch_move covers the deviating move.
// Otherwise the result is `novel` (once enough moves are in) or `none`.

import '../../../game_page/services/transform/transform.dart';
import 'opening_book_models.dart';

/// Recognition confidence/category for the current placement sequence.
enum MillOpeningStatus {
  none,
  probable,
  exact,
  transposition,
  deviation,
  novel,
}

/// Immutable result describing the recognised opening (or lack thereof).
class MillOpeningRecognition {
  const MillOpeningRecognition({
    required this.status,
    required this.matchedPly,
    this.openingId,
    this.name,
    this.family,
    this.source,
    this.sourceReference,
    this.strategicNotes = '',
    this.commonBlunders = const <String>[],
    this.recommendedResponses = const <String, List<String>>{},
    this.aliases = const <String>[],
    this.tags = const <String>[],
    this.favoredSide = 'equal',
    this.nextMove,
    this.branchName,
    this.deviationPly,
    this.deviationMove,
    this.confidence = 0.0,
  });

  static const MillOpeningRecognition none = MillOpeningRecognition(
    status: MillOpeningStatus.none,
    matchedPly: 0,
  );

  final MillOpeningStatus status;
  final int matchedPly;
  final String? openingId;
  final String? name;
  final String? family;
  final String? source;
  final String? sourceReference;
  final String strategicNotes;
  final List<String> commonBlunders;
  final Map<String, List<String>> recommendedResponses;
  final List<String> aliases;
  final List<String> tags;

  /// Which side the recognised opening favours: "W", "B", or "equal".
  final String favoredSide;

  /// Book's recommended next move in the live board frame, when known.
  final String? nextMove;
  final String? branchName;
  final int? deviationPly;
  final String? deviationMove;
  final double confidence;

  bool get isNamed =>
      name != null &&
      name!.isNotEmpty &&
      status != MillOpeningStatus.none &&
      status != MillOpeningStatus.novel;
}

abstract final class MillOpeningRecognizer {
  /// Minimum plies before a brand-new (unmatched) sequence is called `novel`.
  static const int novelCommitPly = 6;

  /// Recognises [placementMoves] (in play order, removals already filtered)
  /// against [openings]. Pure and side-effect free.
  static MillOpeningRecognition recognize(
    List<String> placementMoves,
    List<OpeningEntry> openings,
  ) {
    final int ply = placementMoves.length;
    if (ply == 0 || openings.isEmpty) {
      return MillOpeningRecognition.none;
    }

    _BestMatch? exact;
    _BestMatch? transposition;
    int bestPrefix = 0; // longest in-order prefix across all openings/frames
    final List<_PartialMatch> prefixMatches = <_PartialMatch>[];

    for (final TransformationType type in TransformationType.values) {
      final List<String> moved = placementMoves
          .map((String m) => transformMoveNotation(m, type))
          .toList(growable: false);

      for (final OpeningEntry opening in openings) {
        final List<String> line = opening.lineMoves;
        final int prefix = _commonPrefix(moved, line);
        if (prefix > bestPrefix) {
          bestPrefix = prefix;
        }
        if (prefix > 0) {
          prefixMatches.add(
            _PartialMatch(opening: opening, type: type, prefix: prefix),
          );
        }

        if (line.length >= ply && prefix == ply) {
          exact = _better(exact, opening, type, line.length);
          continue;
        }
        if (line.length >= ply && _setMatch(moved, line, ply)) {
          transposition = _better(transposition, opening, type, line.length);
        }
      }
    }

    if (exact != null) {
      final int candidates = _countExact(placementMoves, openings, ply);
      final MillOpeningStatus status = candidates <= 1
          ? MillOpeningStatus.exact
          : MillOpeningStatus.probable;
      return _build(
        exact,
        ply,
        status,
        candidates <= 1 ? 1.0 : 1.0 / candidates,
      );
    }

    if (transposition != null) {
      return _build(transposition, ply, MillOpeningStatus.transposition, 0.7);
    }

    // No full-length match: did we leave a line we were following?
    if (bestPrefix > 0 && bestPrefix < ply) {
      final MillOpeningRecognition? deviation = _detectDeviation(
        prefixMatches,
        placementMoves,
        bestPrefix,
      );
      if (deviation != null) {
        return deviation;
      }
    }

    if (ply >= novelCommitPly || bestPrefix > 0) {
      return MillOpeningRecognition(
        status: MillOpeningStatus.novel,
        matchedPly: bestPrefix,
      );
    }
    return MillOpeningRecognition.none;
  }

  /// Distinct next moves (in the live board frame) that continue a named line
  /// favouring [aiSide] ("W"/"B") and consistent with [placementMoves], ordered
  /// best line first. Empty when no favourable line extends the current
  /// placements. Backs the opt-in "prefer favourable openings" director.
  static List<String> favoredOpeningMoves(
    List<String> placementMoves,
    List<OpeningEntry> openings,
    String aiSide,
  ) {
    if (aiSide != 'W' && aiSide != 'B') {
      return const <String>[];
    }
    return _continuationMoves(
      placementMoves,
      openings,
      requiredFavoredSide: aiSide,
    );
  }

  /// Distinct next moves (in the live board frame) that continue ANY named line
  /// consistent with [placementMoves], ordered best line first (confidence,
  /// then line length). Unlike [favoredOpeningMoves] this ignores which side a
  /// line favours, so curated, imported, and self-play lines can all guide AI
  /// placement when the move oracle has no entry for the current position.
  static List<String> bookContinuationMoves(
    List<String> placementMoves,
    List<OpeningEntry> openings,
  ) {
    return _continuationMoves(placementMoves, openings);
  }

  /// Shared engine behind [favoredOpeningMoves] and [bookContinuationMoves]:
  /// collects, across all 16 symmetry frames, the next move of every opening
  /// whose line extends [placementMoves]; when [requiredFavoredSide] is set,
  /// only lines favouring that side are considered. Results are ordered by
  /// confidence then line length, deduplicated by move (best occurrence wins).
  static List<String> _continuationMoves(
    List<String> placementMoves,
    List<OpeningEntry> openings, {
    String? requiredFavoredSide,
  }) {
    final int ply = placementMoves.length;
    final List<_ContinuationCandidate> candidates = <_ContinuationCandidate>[];
    for (final TransformationType type in TransformationType.values) {
      final List<String> moved = placementMoves
          .map((String m) => transformMoveNotation(m, type))
          .toList(growable: false);
      final List<int> fromCanonical = inverseTransformMap(
        getTransformMap(type),
      );
      for (final OpeningEntry opening in openings) {
        if (requiredFavoredSide != null &&
            opening.favoredSide != requiredFavoredSide) {
          continue;
        }
        if (opening.lineMoves.length <= ply ||
            _commonPrefix(moved, opening.lineMoves) != ply) {
          continue;
        }
        candidates.add(
          _ContinuationCandidate(
            move: transformMoveNotationWithMap(
              opening.lineMoves[ply],
              fromCanonical,
            ),
            confidence: opening.confidence,
            lineLength: opening.lineMoves.length,
          ),
        );
      }
    }
    candidates.sort((_ContinuationCandidate a, _ContinuationCandidate b) {
      final int byConfidence = b.confidence.compareTo(a.confidence);
      return byConfidence != 0
          ? byConfidence
          : b.lineLength.compareTo(a.lineLength);
    });
    final List<String> ordered = <String>[];
    final Set<String> seen = <String>{};
    for (final _ContinuationCandidate c in candidates) {
      if (seen.add(c.move)) {
        ordered.add(c.move);
      }
    }
    return ordered;
  }

  static MillOpeningRecognition? _detectDeviation(
    List<_PartialMatch> prefixMatches,
    List<String> placementMoves,
    int bestPrefix,
  ) {
    // Consider the lines we matched furthest; the deviation occurred at the
    // move after their shared prefix.
    for (final _PartialMatch match in prefixMatches) {
      if (match.prefix != bestPrefix) {
        continue;
      }
      final int deviationPly = bestPrefix + 1;
      final List<String> moved = placementMoves
          .map((String m) => transformMoveNotation(m, match.type))
          .toList(growable: false);
      if (deviationPly - 1 >= moved.length) {
        continue;
      }
      final String deviationMove = moved[deviationPly - 1];
      for (final OpeningBranch branch in match.opening.branchMoves) {
        if (branch.deviationPly == deviationPly &&
            branch.deviationMove == deviationMove) {
          return MillOpeningRecognition(
            status: MillOpeningStatus.deviation,
            matchedPly: bestPrefix,
            openingId: match.opening.id,
            name: match.opening.name,
            family: match.opening.family,
            source: match.opening.source,
            sourceReference: match.opening.sourceReference,
            strategicNotes: branch.strategicNotes.isNotEmpty
                ? branch.strategicNotes
                : match.opening.strategicNotes,
            commonBlunders: match.opening.commonBlunders,
            recommendedResponses: match.opening.recommendedResponses,
            aliases: match.opening.aliases,
            tags: match.opening.tags,
            favoredSide: match.opening.favoredSide,
            branchName: branch.name,
            deviationPly: deviationPly,
            deviationMove: placementMoves[deviationPly - 1],
            confidence: 0.5,
          );
        }
      }
    }
    return null;
  }

  static MillOpeningRecognition _build(
    _BestMatch match,
    int ply,
    MillOpeningStatus status,
    double confidence,
  ) {
    final OpeningEntry opening = match.opening;
    String? nextMove;
    if (opening.lineMoves.length > ply) {
      final List<int> fromCanonical = inverseTransformMap(
        getTransformMap(match.type),
      );
      nextMove = transformMoveNotationWithMap(
        opening.lineMoves[ply],
        fromCanonical,
      );
    }
    return MillOpeningRecognition(
      status: status,
      matchedPly: ply,
      openingId: opening.id,
      name: opening.name,
      family: opening.family,
      source: opening.source,
      sourceReference: opening.sourceReference,
      strategicNotes: opening.strategicNotes,
      commonBlunders: opening.commonBlunders,
      recommendedResponses: opening.recommendedResponses,
      aliases: opening.aliases,
      tags: opening.tags,
      favoredSide: opening.favoredSide,
      nextMove: nextMove,
      confidence: confidence,
    );
  }

  static _BestMatch _better(
    _BestMatch? current,
    OpeningEntry opening,
    TransformationType type,
    int lineLength,
  ) {
    if (current == null || lineLength > current.lineLength) {
      return _BestMatch(opening: opening, type: type, lineLength: lineLength);
    }
    return current;
  }

  /// Number of distinct openings whose line begins with the exact (any-frame)
  /// played prefix, used to grade `exact` vs `probable`.
  static int _countExact(
    List<String> placementMoves,
    List<OpeningEntry> openings,
    int ply,
  ) {
    final Set<String> ids = <String>{};
    for (final TransformationType type in TransformationType.values) {
      final List<String> moved = placementMoves
          .map((String m) => transformMoveNotation(m, type))
          .toList(growable: false);
      for (final OpeningEntry opening in openings) {
        if (opening.lineMoves.length >= ply &&
            _commonPrefix(moved, opening.lineMoves) == ply) {
          ids.add(opening.id);
        }
      }
    }
    return ids.length;
  }

  static int _commonPrefix(List<String> a, List<String> b) {
    final int n = a.length < b.length ? a.length : b.length;
    int i = 0;
    while (i < n && a[i] == b[i]) {
      i++;
    }
    return i;
  }

  /// True when the first [ply] moves of [moved] and [line] place on the same
  /// squares per side (order-independent), i.e. a transposition. Even indices
  /// are the first mover's placements, odd indices the opponent's.
  static bool _setMatch(List<String> moved, List<String> line, int ply) {
    final Set<String> movedFirst = <String>{};
    final Set<String> movedSecond = <String>{};
    final Set<String> lineFirst = <String>{};
    final Set<String> lineSecond = <String>{};
    for (int i = 0; i < ply; i++) {
      if (i.isEven) {
        movedFirst.add(moved[i]);
        lineFirst.add(line[i]);
      } else {
        movedSecond.add(moved[i]);
        lineSecond.add(line[i]);
      }
    }
    return _setEquals(movedFirst, lineFirst) &&
        _setEquals(movedSecond, lineSecond);
  }

  static bool _setEquals(Set<String> a, Set<String> b) {
    return a.length == b.length && a.containsAll(b);
  }
}

class _BestMatch {
  const _BestMatch({
    required this.opening,
    required this.type,
    required this.lineLength,
  });

  final OpeningEntry opening;
  final TransformationType type;
  final int lineLength;
}

class _PartialMatch {
  const _PartialMatch({
    required this.opening,
    required this.type,
    required this.prefix,
  });

  final OpeningEntry opening;
  final TransformationType type;
  final int prefix;
}

class _ContinuationCandidate {
  const _ContinuationCandidate({
    required this.move,
    required this.confidence,
    required this.lineLength,
  });

  final String move;
  final double confidence;
  final int lineLength;
}
