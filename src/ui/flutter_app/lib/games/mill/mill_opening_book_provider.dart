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

    final String? normalizedFen = _normalizeFen(session.getFen());
    if (normalizedFen == null) {
      return null;
    }

    final Map<String, List<String>> book = ruleSettings.isLikelyElFilja()
        ? elFiljaFenToBestMoves
        : nineMensMorrisFenToBestMoves;
    final List<String>? bestMoves = book[normalizedFen];
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

  static String? _normalizeFen(String fen) {
    final List<String> fenFields = fen.split(' ');
    if (fenFields.length < 2) {
      return fen;
    }
    fenFields[fenFields.length - 2] = '0';
    fenFields[fenFields.length - 3] = '0';
    return fenFields.join(' ');
  }
}
