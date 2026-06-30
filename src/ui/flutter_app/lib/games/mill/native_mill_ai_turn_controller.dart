// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import '../../game_platform/game_session.dart';
import '../../game_platform/opening_book_provider.dart';
import '../../general_settings/models/general_settings.dart';
import '../../shared/services/environment_config.dart';
import '../../shared/services/logger.dart';
import '../../src/rust/api/simple.dart' as tgf;
import 'mill_action_codec.dart';
import 'mill_human_database_provider.dart';
import 'mill_types.dart';
import 'native_mill_game_session.dart';

/// Optional hook invoked immediately before a remove [GameAction] is applied.
/// Used to await [Game.pendingMillSoundCompleter] so mill audio finishes
/// before the capture animation/sound (master `engineToGo` parity).
typedef BeforeRemoveApplyHook = Future<void> Function();

/// AI-turn adapter for the Rust-native Mill session path.
///
/// This intentionally does not touch `GameController`, timers, or recording.
/// It only answers: "Is the active side controlled by AI, and if so, run the
/// native search to consume the entire AI obligation (place / move / remove
/// chain)."  `engineToGo` can layer UI side effects on top later.
class NativeMillAiTurnController {
  const NativeMillAiTurnController({
    this.depth,
    this.generalSettings = const GeneralSettings(),
    this.maxStepsPerTurn = 8,
    this.bothSidesAi = false,
    this.onBeforeRemoveApply,
    this.openingBook,
    this.humanDatabase,
  });

  /// Optional fixed depth override used by tests and targeted diagnostics.
  ///
  /// When null, the depth is derived from [generalSettings.skillLevel] and the
  /// current session snapshot to preserve the legacy "draw on human
  /// experience" placing-phase depth table.
  final int? depth;
  final GeneralSettings generalSettings;

  /// Safety cap on how many native search-and-apply iterations are performed
  /// for a single human-triggered AI turn.  In Mill, a single AI obligation
  /// chain is at most place/move + (1..3 removes), so 8 is conservative.
  final int maxStepsPerTurn;

  /// When `true`, treat *both* seats as AI-controlled (AI vs AI mode).
  /// Disables the [aiSeat] side filter so the controller advances the
  /// game on every active seat until terminal, mirroring master's
  /// `Search::executeSearch` continuously running while
  /// `gameMode == GameMode::aiVsAi`.
  final bool bothSidesAi;

  /// When set, called before applying a remove action inside [playIfAiTurn].
  final BeforeRemoveApplyHook? onBeforeRemoveApply;

  /// Optional opening-book lookup consulted before engine search.
  final OpeningBookProvider? openingBook;

  /// Optional Human Database lookup consulted before engine search.
  final MillHumanDatabaseProvider? humanDatabase;

  PlayerSeat get aiSeat =>
      generalSettings.aiMovesFirst ? PlayerSeat.first : PlayerSeat.second;

  bool isAiTurn(NativeMillGameSession session) {
    final bool notTerminal = !session.outcome.isTerminal;
    if (!notTerminal) {
      logger.w(
        '[NativeMillAiTurnController] isAiTurn=false: game is terminal '
        '(outcome=${session.outcome})',
      );
      return false;
    }
    if (bothSidesAi) {
      // AI vs AI: every non-terminal active seat is an AI turn.  Skip
      // the seat-equality filter so the controller drives both white
      // and black moves consecutively.
      return true;
    }
    final PlayerSeat active = session.state.value.activeSeat;
    final bool result = active == aiSeat;
    if (!result) {
      logger.w(
        '[NativeMillAiTurnController] isAiTurn=false: '
        'activeSeat=$active aiSeat=$aiSeat phase=${session.state.value.phase}',
      );
    }
    return result;
  }

  int searchDepthForSession(NativeMillGameSession session) {
    return depth ?? searchDepthForSnapshot(session.state.value);
  }

  int searchDepthForSnapshot(GameStateSnapshot snapshot) {
    if (depth != null) {
      return depth!.clamp(1, 64);
    }
    final int level = generalSettings.skillLevel.clamp(1, 30);
    if (!generalSettings.drawOnHumanExperience || snapshot.phase != 'placing') {
      return level;
    }

    final Object? rawPayload = snapshot.payload['tgfPayload'];
    if (rawPayload is! List<int> || rawPayload.length < 28) {
      return level;
    }

    final int whiteInHand = rawPayload[24];
    final int blackInHand = rawPayload[25];
    final int whiteOnBoard = rawPayload[26];
    final int blackOnBoard = rawPayload[27];
    final int whiteTotal = whiteInHand + whiteOnBoard;
    final int blackTotal = blackInHand + blackOnBoard;
    final int pieceCount = (whiteTotal > blackTotal ? whiteTotal : blackTotal)
        .clamp(0, 12);
    final int index = (pieceCount * 2 - whiteInHand - blackInHand).clamp(0, 24);

    final List<int> table = pieceCount == 12
        ? _placingDepthTable12
        : _placingDepthTable9;
    final int tableDepth = table[index];
    if (tableDepth <= 0) {
      return level;
    }
    return level > tableDepth ? tableDepth : level;
  }

  /// Search time limit in milliseconds derived from [generalSettings.moveTime].
  /// A value of 0 means unlimited (depth alone drives termination).
  int get moveLimitMs {
    final int secs = generalSettings.moveTime;
    return secs > 0 ? secs * 1000 : 0;
  }

  /// Run native search-and-apply until the active seat changes away from the
  /// AI (or the game ends).  This handles mill formation correctly: after a
  /// Place that completes a mill, `state.value.activeSeat` stays on the AI
  /// side because `pending_removals[ai] > 0`, so the caller still sees an
  /// AI turn and we must keep searching for the Remove action.
  ///
  /// Returns the LAST applied action for logging / UI.  Returns null when no
  /// AI move was applied (e.g. the search aborted on the first iteration).
  ///
  /// In [bothSidesAi] mode the inner loop additionally stops as soon as the
  /// active seat changes -- otherwise a single call would consume both
  /// sides' moves back-to-back without giving the outer driver a chance to
  /// repaint the board between them.
  Future<GameAction?> playIfAiTurn(NativeMillGameSession session) async {
    if (EnvironmentConfig.devMode) {
      logger.i(
        '[NativeMillAiTurnController] playIfAiTurn entry: '
        'bothSidesAi=$bothSidesAi, '
        'activeSeat=${session.state.value.activeSeat}, '
        'aiSeat=$aiSeat, '
        'phase=${session.state.value.phase}, '
        'isTerminal=${session.outcome.isTerminal}',
      );
    }
    if (!isAiTurn(session)) {
      logger.w('[NativeMillAiTurnController] playIfAiTurn abort: not AI turn');
      return null;
    }
    final int searchDepth = searchDepthForSession(session);
    final int timeLimit = moveLimitMs;
    final PlayerSeat startingSeat = session.state.value.activeSeat;
    if (EnvironmentConfig.devMode) {
      logger.i(
        '[NativeMillAiTurnController] playIfAiTurn loop: '
        'searchDepth=$searchDepth, timeLimit=$timeLimit, startingSeat=$startingSeat',
      );
    }
    GameAction? lastApplied;
    for (int step = 0; step < maxStepsPerTurn; step++) {
      if (EnvironmentConfig.devMode) {
        logger.i(
          '[NativeMillAiTurnController] step=$step '
          'activeSeat=${session.state.value.activeSeat}',
        );
      }
      if (!isAiTurn(session)) {
        if (EnvironmentConfig.devMode) {
          logger.i('[NativeMillAiTurnController] step=$step !isAiTurn; break.');
        }
        break;
      }
      // In aiVsAi we deliberately stop after the side flips so the
      // outer driver can yield to the Flutter event loop between the
      // two AIs' turns.  Mill mill-formation chains keep the same
      // active seat (pending_removals stays on the mover) so this
      // still consumes Place + Remove correctly.
      if (bothSidesAi &&
          lastApplied != null &&
          session.state.value.activeSeat != startingSeat) {
        if (EnvironmentConfig.devMode) {
          logger.i(
            '[NativeMillAiTurnController] step=$step seat flipped from '
            '$startingSeat to ${session.state.value.activeSeat}; '
            'yielding to outer loop.',
          );
        }
        break;
      }
      final GameAction? bookAction = openingBook?.lookup(session);
      if (bookAction != null) {
        if (bookAction.type == MillActionTypes.remove) {
          await onBeforeRemoveApply?.call();
        }
        await session.apply(bookAction);
        session.lastAiMoveType = AiMoveType.openingBook;
        session.lastAiBestValue = 0;
        session.lastHumanDatabaseMoveStats = null;
        lastApplied = bookAction;
        if (EnvironmentConfig.devMode) {
          logger.i(
            '[NativeMillAiTurnController] step=$step opening-book '
            'applied=${bookAction.payload['move']}',
          );
        }
        continue;
      }

      final GameAction? humanDatabaseAction = humanDatabase?.lookup(session);
      if (humanDatabaseAction != null) {
        final HumanDatabaseMoveStats? stats = humanDatabase?.lastStats;
        final GameAction? perfectAction = session.perfectDatabaseBestAction(
          engineSettings: generalSettings,
        );
        final bool correctedByPerfect =
            perfectAction != null &&
            !_isSameAction(perfectAction, humanDatabaseAction);
        final GameAction action = correctedByPerfect
            ? perfectAction
            : humanDatabaseAction;
        final int graphScore = correctedByPerfect
            ? _perfectDatabaseGraphScore(session, action)
            : _humanDatabaseGraphScore(session, stats);
        if (correctedByPerfect) {
          humanDatabase?.discardPendingMove();
        }

        if (action.type == MillActionTypes.remove) {
          await onBeforeRemoveApply?.call();
        }
        await session.apply(action);
        session.lastAiMoveType = correctedByPerfect
            ? AiMoveType.perfect
            : AiMoveType.humanDatabase;
        session.lastAiBestValue = graphScore;
        session.lastHumanDatabaseMoveStats = correctedByPerfect ? null : stats;
        lastApplied = action;
        if (EnvironmentConfig.devMode) {
          logger.i(
            '[NativeMillAiTurnController] step=$step human-db '
            'candidate=${humanDatabaseAction.payload['move']} '
            'applied=${action.payload['move']} '
            'perfectCorrected=$correctedByPerfect',
          );
        }
        continue;
      }

      session.lastHumanDatabaseMoveStats = null;
      final Stopwatch sw = Stopwatch()..start();
      // Pass the controller's live [generalSettings] so the engine honours
      // the *current* user settings (shuffling, algorithm, skill level, lazy
      // mode, perfect database).  Without this the search would read the
      // stale snapshot captured by the session's rules port at construction
      // time, so toggling e.g. the shuffling switch mid-session would have no
      // effect — diverging from the master engine, which read `gameOptions`
      // live on every search.
      final GameAction? action = await session.searchBestAction(
        depth: searchDepth,
        moveLimitMs: timeLimit,
        engineSettings: generalSettings,
      );
      if (action == null) {
        sw.stop();
        logger.w(
          '[NativeMillAiTurnController] step=$step searchBestAction=null; '
          'break.',
        );
        break;
      }
      if (action.type == MillActionTypes.remove) {
        await onBeforeRemoveApply?.call();
      }
      if (session.lastAiMoveType == AiMoveType.perfect ||
          session.lastAiMoveType == AiMoveType.consensus) {
        session.lastAiBestValue = _perfectDatabaseGraphScore(session, action);
      }
      await session.apply(action);
      sw.stop();
      if (EnvironmentConfig.devMode) {
        logger.i(
          '[NativeMillAiTurnController] step=$step search+apply '
          'returned in ${sw.elapsedMilliseconds}ms: '
          'applied=${action.payload['move']}',
        );
      }
      lastApplied = action;
    }
    if (EnvironmentConfig.devMode) {
      logger.i(
        '[NativeMillAiTurnController] playIfAiTurn done: '
        'lastApplied=${lastApplied?.payload['move'] ?? '(null)'}',
      );
    }
    return lastApplied;
  }

  bool _isSameAction(GameAction left, GameAction right) {
    return left.type == right.type &&
        MillActionCodec.moveStringFrom(left) ==
            MillActionCodec.moveStringFrom(right);
  }

  int _humanDatabaseGraphScore(
    NativeMillGameSession session,
    HumanDatabaseMoveStats? stats,
  ) {
    assert(stats != null, 'Human Database move must carry move statistics.');
    if (stats == null) {
      return 0;
    }
    return _whitePerspectiveGraphScore(
      session.state.value.activeSeat,
      stats.scoreDelta * 200.0,
    );
  }

  int _perfectDatabaseGraphScore(
    NativeMillGameSession session,
    GameAction action,
  ) {
    final String? selectedMove = MillActionCodec.moveStringFrom(action);
    assert(
      selectedMove != null,
      'Perfect Database action must be a Mill move.',
    );
    if (selectedMove == null) {
      return 0;
    }

    final tgf.MillAnalysisReport report = session.analyzePerfectDb();
    for (final tgf.MillMoveAnalysis move in report.moves) {
      if (move.mv != selectedMove) {
        continue;
      }
      final double moverScore = switch (move.outcome) {
        'win' => 100.0,
        'draw' => 0.0,
        'loss' => -100.0,
        _ => move.value.toDouble(),
      };
      return _whitePerspectiveGraphScore(
        session.state.value.activeSeat,
        moverScore,
      );
    }

    assert(
      false,
      'Perfect Database analysis must include chosen move $selectedMove.',
    );
    return 0;
  }

  int _whitePerspectiveGraphScore(PlayerSeat activeSeat, double moverScore) {
    assert(
      activeSeat != PlayerSeat.none,
      'Graph score mapping requires an active side to move.',
    );
    final double whiteScore = switch (activeSeat) {
      PlayerSeat.first => moverScore,
      PlayerSeat.second => -moverScore,
      PlayerSeat.none => 0.0,
    };
    return whiteScore.round().clamp(-100, 100);
  }
}

// Matches legacy `Mills::get_search_depth` for non-developer placing phase
// when "DrawOnHumanExperience" is enabled.
const List<int> _placingDepthTable9 = <int>[
  1, 1, 1, 1, // 0 ~ 3
  3, 3, 3, 15, // 4 ~ 7
  15, 5, 18, 0, // 8 ~ 11
  0, 0, 0, 0, // 12 ~ 15
  0, 0, 0, 0, // 16 ~ 19
  0, 0, 0, 0, // 20 ~ 23
  0, // 24
];

const List<int> _placingDepthTable12 = <int>[
  1, 2, 2, 4, // 0 ~ 3
  4, 12, 12, 18, // 4 ~ 7
  12, 0, 0, 0, // 8 ~ 11
  0, 0, 0, 0, // 12 ~ 15
  0, 0, 0, 0, // 16 ~ 19
  0, 0, 0, 0, // 20 ~ 23
  0, // 24
];
