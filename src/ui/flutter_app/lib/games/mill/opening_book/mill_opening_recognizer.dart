// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

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
    this.candidateFamilies = const <String>[],
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

  /// When several distinct families still fit the played prefix, the ranked,
  /// de-duplicated family shortlist (e.g. `["Battle Lines", "Z Mill"]`); empty
  /// for an unambiguous single-family match. Lets the UI surface the
  /// alternatives instead of committing to one (possibly wrong) name while the
  /// lines still share a common start.
  final List<String> candidateFamilies;

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

    // Every distinct opening (keyed by id, first matching frame retained for
    // next-move recovery) whose line covers the played prefix. Collecting all
    // candidates — rather than greedily keeping the longest line — lets us pick
    // a principled representative and detect when several *different families*
    // fit the same prefix, so the result can stay honestly ambiguous instead of
    // naming one at random.
    final Map<String, _BestMatch> exactById = <String, _BestMatch>{};
    final Map<String, _BestMatch> transpositionById = <String, _BestMatch>{};
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
          exactById.putIfAbsent(
            opening.id,
            () => _BestMatch(
              opening: opening,
              type: type,
              lineLength: line.length,
            ),
          );
          continue;
        }
        if (line.length >= ply && _setMatch(moved, line, ply)) {
          transpositionById.putIfAbsent(
            opening.id,
            () => _BestMatch(
              opening: opening,
              type: type,
              lineLength: line.length,
            ),
          );
        }
      }
    }

    if (exactById.isNotEmpty) {
      return _resolveAmbiguous(exactById.values, ply, exact: true);
    }
    if (transpositionById.isNotEmpty) {
      return _resolveAmbiguous(transpositionById.values, ply, exact: false);
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

  /// Picks a single representative from [candidates] (all openings matching the
  /// played prefix) and records any family-level ambiguity.
  ///
  /// Naming is confined to the highest source tier present (see [_sourceRank]):
  /// when a curated book line fits, imported/self-play "learned" lines never
  /// influence the displayed name or family shortlist. Within that tier the
  /// representative is chosen by [_preferred] — most authoritative, then
  /// shortest (closest to the live position), then a stable id — never simply
  /// the longest line. When the surviving candidates still span more than one
  /// family the match is reported as `probable` and [candidateFamilies] lists
  /// them, so the UI can show "A / B" instead of committing to one name.
  static MillOpeningRecognition _resolveAmbiguous(
    Iterable<_BestMatch> candidates,
    int ply, {
    required bool exact,
  }) {
    final List<_BestMatch> all = candidates.toList(growable: false);
    final int topRank = all
        .map((_BestMatch m) => _sourceRank(m.opening))
        .reduce((int a, int b) => a < b ? a : b);
    final List<_BestMatch> named =
        all.where((_BestMatch m) => _sourceRank(m.opening) == topRank).toList()
          ..sort(_preferred);

    final List<String> families = <String>[];
    final Set<String> seenFamilies = <String>{};
    for (final _BestMatch m in named) {
      final String family = m.opening.family;
      if (family.isNotEmpty && seenFamilies.add(family)) {
        families.add(family);
      }
    }

    final bool ambiguous = named.length > 1;
    final MillOpeningStatus status = exact
        ? (ambiguous ? MillOpeningStatus.probable : MillOpeningStatus.exact)
        : MillOpeningStatus.transposition;
    final double confidence = exact
        ? (ambiguous ? 1.0 / named.length : 1.0)
        : 0.7;
    return _build(
      named.first,
      ply,
      status,
      confidence,
      candidateFamilies: families,
    );
  }

  static MillOpeningRecognition _build(
    _BestMatch match,
    int ply,
    MillOpeningStatus status,
    double confidence, {
    List<String> candidateFamilies = const <String>[],
  }) {
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
      candidateFamilies: candidateFamilies,
      nextMove: nextMove,
      confidence: confidence,
    );
  }

  /// Naming priority by provenance. Lower wins: hand-curated book lines first,
  /// then imported book games, then self-play "novel" discoveries, then the
  /// rest. Mirrors the build tool's dedup ranking so the recognised name always
  /// comes from the most authoritative source available for the position.
  static int _sourceRank(OpeningEntry entry) {
    if (entry.source == 'book') {
      return 0;
    }
    if (entry.id.startsWith('book-')) {
      return 1;
    }
    if (entry.id.startsWith('novel-')) {
      return 2;
    }
    return 3;
  }

  /// Tie-break among equally-ranked prefix matches: highest confidence, then
  /// the SHORTEST line (closest to the live position, least speculative), then
  /// a stable id order. Deliberately NOT "longest line", which previously let a
  /// long, loosely-related line (e.g. an 18-ply import) outvote the opening the
  /// player was actually in.
  static int _preferred(_BestMatch a, _BestMatch b) {
    final int byConfidence = b.opening.confidence.compareTo(
      a.opening.confidence,
    );
    if (byConfidence != 0) {
      return byConfidence;
    }
    final int byLength = a.lineLength.compareTo(b.lineLength);
    if (byLength != 0) {
      return byLength;
    }
    return a.opening.id.compareTo(b.opening.id);
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
