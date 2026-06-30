// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import '../../game_platform/game_session.dart';
import '../../game_platform/opening_book_provider.dart';
import '../../general_settings/models/general_settings.dart';
import '../../rule_settings/models/rule_settings.dart';
import '../../shared/services/logger.dart';
import 'mill_action_codec.dart';
import 'mill_opening_book_symmetry.dart';
import 'native_mill_game_session.dart';
import 'opening_book/mill_opening_move_selector.dart';
import 'opening_book/mill_opening_recognizer.dart';
import 'opening_book/opening_book_repository.dart';

class MillOpeningBookProvider implements OpeningBookProvider {
  MillOpeningBookProvider({
    required this.ruleSettings,
    required this.generalSettings,
    this.placementHistory,
  });

  final RuleSettings ruleSettings;
  final GeneralSettings generalSettings;

  /// Supplies the placement moves played so far (in order, removals filtered)
  /// for the opt-in favoured-opening director. Null disables the director.
  final List<String> Function()? placementHistory;

  @override
  GameAction? lookup(GameSession session) {
    if (!generalSettings.useOpeningBook) {
      return null;
    }
    if (!ruleSettings.isLikelyNineMensMorris() &&
        !ruleSettings.isLikelyElFilja()) {
      return null;
    }
    if (session is! NativeMillGameSession) {
      return null;
    }
    if (session.outcome.isTerminal) {
      return null;
    }
    // Opening-book FEN keys currently cover placing-phase positions only.
    // Delayed-removal book entries use action token `r`, but their FEN phase
    // remains `p`, so checking the session phase keeps those entries eligible
    // while avoiding FEN export throughout the moving phase.
    if (session.state.value.phase != 'placing') {
      return null;
    }

    // Opt-in: follow a known opening line that favours the AI's own side before
    // consulting the move oracle. Off by default, so default play is unchanged.
    final GameAction? favored = _favoredOpeningMove(session);
    if (favored != null) {
      return favored;
    }

    final String normalizedFen = normalizeOpeningBookFen(session.getFen());

    final Map<String, List<String>> book = OpeningBookRepository.instance
        .oracleFor(isElFilja: ruleSettings.isLikelyElFilja());
    final List<String>? bestMoves = lookupCanonicalOpeningBook(
      book,
      normalizedFen,
    );
    if (bestMoves != null && bestMoves.isNotEmpty) {
      final String selectedMove = MillOpeningMoveSelector.select(
        bestMoves,
        shuffling: generalSettings.shufflingEnabled,
        bias: _openingBias,
      );
      for (final GameAction action in session.legalActions) {
        if (MillActionCodec.moveStringFrom(action) == selectedMove) {
          return action;
        }
      }
      logger.w(
        '[MillOpeningBookProvider] book move "$selectedMove" matches no legal '
        'action for FEN $normalizedFen',
      );
    }

    // Oracle miss (or its move is somehow illegal): fall back to the next move
    // of a recognised opening line so curated + learned/novel lines also guide
    // AI placement beyond the engine-quality oracle's coverage.
    return _bookContinuationMove(session);
  }

  /// Returns a legal move that continues a named opening favouring the side to
  /// move (the AI), or null when the feature is off, no history is wired, or no
  /// favourable, history-consistent line offers a legal move.
  GameAction? _favoredOpeningMove(NativeMillGameSession session) {
    if (!generalSettings.preferFavoredOpenings) {
      return null;
    }
    final List<String>? history = placementHistory?.call();
    if (history == null) {
      return null;
    }
    final String aiSide = switch (session.state.value.activeSeat) {
      PlayerSeat.first => 'W',
      PlayerSeat.second => 'B',
      PlayerSeat.none => '',
    };
    if (aiSide.isEmpty) {
      return null;
    }
    return _selectLegalCandidate(
      session,
      MillOpeningRecognizer.favoredOpeningMoves(
        history,
        OpeningBookRepository.instance.openingsFor(
          isElFilja: ruleSettings.isLikelyElFilja(),
        ),
        aiSide,
      ),
    );
  }

  /// Returns the next move of a recognised opening line (curated, imported, or
  /// self-play) consistent with the placements so far. Used as a fallback when
  /// the engine-quality move oracle has no entry for the current position, so
  /// learned/novel lines also participate in AI placement. Null when no line
  /// extends the current placements with a legal move, or no history is wired.
  GameAction? _bookContinuationMove(NativeMillGameSession session) {
    final List<String>? history = placementHistory?.call();
    if (history == null) {
      return null;
    }
    return _selectLegalCandidate(
      session,
      MillOpeningRecognizer.bookContinuationMoves(
        history,
        OpeningBookRepository.instance.openingsFor(
          isElFilja: ruleSettings.isLikelyElFilja(),
        ),
      ),
    );
  }

  /// Bias for [MillOpeningMoveSelector]: derived from [openingRandomness]
  /// (0–100) as `bias = openingRandomness / 100`. 0 → always the best
  /// candidate; 1.0 → uniform random; legacy default 60 → bias 0.6.
  double get _openingBias =>
      generalSettings.openingRandomness.clamp(0, 100) / 100.0;

  /// Picks the best legal move from [candidates] (already ordered best-first),
  /// applying the shared shuffling policy. Returns null when none is legal.
  GameAction? _selectLegalCandidate(
    NativeMillGameSession session,
    List<String> candidates,
  ) {
    if (candidates.isEmpty) {
      return null;
    }
    final Set<String> legalMoves = <String>{};
    for (final GameAction action in session.legalActions) {
      final String? move = MillActionCodec.moveStringFrom(action);
      if (move != null) {
        legalMoves.add(move);
      }
    }
    final List<String> legalCandidates = candidates
        .where(legalMoves.contains)
        .toList(growable: false);
    if (legalCandidates.isEmpty) {
      return null;
    }
    final String selected = MillOpeningMoveSelector.select(
      legalCandidates,
      shuffling: generalSettings.shufflingEnabled,
      bias: _openingBias,
    );
    for (final GameAction action in session.legalActions) {
      if (MillActionCodec.moveStringFrom(action) == selected) {
        return action;
      }
    }
    return null;
  }
}
