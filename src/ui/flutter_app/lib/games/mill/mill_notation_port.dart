// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import '../../game_platform/game_session.dart';
import '../../game_platform/notation_port.dart';
import '../../src/rust/api/kernel.dart' as tgf_kernel;
import 'mill_action_codec.dart';

/// Notation adapter for Mill's compact move-token list.
class MillNotationPort implements NotationPort {
  const MillNotationPort();

  @override
  List<GameAction> decodeMoveList(String notation) {
    assert(notation.isNotEmpty, 'Mill notation must not be empty.');
    final List<GameAction> actions = <GameAction>[];
    for (final String token in _moveTokens(notation)) {
      for (final String segment in _splitCaptures(token)) {
        final tgf_kernel.TgfAction? tgfAction =
            MillActionCodec.tgfActionFromMoveString(segment);
        assert(tgfAction != null, 'Invalid Mill move token: $segment.');
        actions.add(MillActionCodec.fromTgfAction(tgfAction!));
      }
    }
    assert(actions.isNotEmpty, 'Mill notation contained no moves.');
    return actions;
  }

  @override
  String describeMove(GameAction action) {
    assert(action.type.isNotEmpty, 'GameAction.type must not be empty.');
    if (action.payload['move'] case final String move) {
      return move;
    }
    return action.payload['notation']?.toString() ?? action.type;
  }

  @override
  String encodeMoveList(Iterable<GameAction> actions) {
    return actions.map(describeMove).join(' ');
  }

  @override
  String exportGame(GameStateSnapshot snapshot, Iterable<GameAction> actions) {
    assert(
      snapshot.gameId.value == 'mill',
      'MillNotationPort needs Mill state.',
    );
    return encodeMoveList(actions);
  }

  static Iterable<String> _moveTokens(String notation) sync* {
    final String withoutComments = notation.replaceAll(
      RegExp(r'\{[^}]*\}'),
      ' ',
    );
    for (final String raw in withoutComments.split(RegExp(r'\s+'))) {
      final String token = _normaliseMoveToken(raw);
      if (token.isNotEmpty) {
        yield token;
      }
    }
  }

  static String _normaliseMoveToken(String raw) {
    String token = raw.trim().toLowerCase();
    if (token.isEmpty) {
      return '';
    }
    if (token == '1-0' ||
        token == '0-1' ||
        token == '1/2-1/2' ||
        token == '*') {
      return '';
    }
    token = token.replaceFirst(RegExp(r'^\d+\.(?:\.\.)?'), '');
    token = token.replaceFirst(RegExp(r'^\.\.\.'), '');
    token = token.replaceAll(RegExp(r'[!?]+$'), '');
    if (token.startsWith(r'$')) {
      return '';
    }
    return token;
  }

  /// Splits a move token into the primitive action sequence understood by the
  /// Rust kernel, e.g. "b4xb2xc3" becomes ["b4", "xb2", "xc3"].
  static List<String> _splitCaptures(String token) {
    if (!token.contains('x')) {
      return <String>[token];
    }
    final List<String> segments = <String>[];
    if (!token.startsWith('x')) {
      final int firstCapture = token.indexOf('x');
      segments.add(token.substring(0, firstCapture));
      token = token.substring(firstCapture);
    }
    segments.addAll(
      RegExp(
        r'x[a-g][1-7]',
      ).allMatches(token).map((RegExpMatch m) => m.group(0)!),
    );
    return segments;
  }
}
