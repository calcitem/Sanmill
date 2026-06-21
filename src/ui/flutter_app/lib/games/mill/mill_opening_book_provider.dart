// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:math';

import '../../game_platform/game_session.dart';
import '../../game_platform/opening_book_provider.dart';
import '../../general_settings/models/general_settings.dart';
import '../../rule_settings/models/rule_settings.dart';
import '../../shared/services/logger.dart';
import 'mill_action_codec.dart';
import 'mill_opening_book_data.dart';
import 'mill_opening_book_symmetry.dart';
import 'native_mill_game_session.dart';

class MillOpeningBookProvider implements OpeningBookProvider {
  MillOpeningBookProvider({
    required this.ruleSettings,
    required this.generalSettings,
  });

  final RuleSettings ruleSettings;
  final GeneralSettings generalSettings;

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

    final String normalizedFen = normalizeOpeningBookFen(session.getFen());

    final Map<String, List<String>> book = ruleSettings.isLikelyElFilja()
        ? elFiljaCanonicalOpeningBook
        : nineMensMorrisCanonicalOpeningBook;
    final List<String>? bestMoves = lookupCanonicalOpeningBook(
      book,
      normalizedFen,
    );
    if (bestMoves == null || bestMoves.isEmpty) {
      return null;
    }

    final String selectedMove = generalSettings.shufflingEnabled
        ? bestMoves[Random(
            DateTime.now().millisecondsSinceEpoch,
          ).nextInt(bestMoves.length)]
        : bestMoves.first;

    for (final GameAction action in session.legalActions) {
      if (MillActionCodec.moveStringFrom(action) == selectedMove) {
        return action;
      }
    }

    logger.w(
      '[MillOpeningBookProvider] book move "$selectedMove" matches no legal '
      'action for FEN $normalizedFen',
    );
    return null;
  }
}
