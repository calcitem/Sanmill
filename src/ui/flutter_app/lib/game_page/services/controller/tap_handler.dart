// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// tap_handler.dart

part of '../mill.dart';

class TapHandler {
  TapHandler({required this.context});

  //final position = GameController().position;

  static const String _logTag = "[Tap Handler]";
  static final MillSessionTapController _nativeSessionTapController =
      MillSessionTapController();

  final BuildContext context;

  final GameController controller = GameController();

  //final gameMode = GameController().gameInstance.gameMode;
  final void Function(String tip, {bool snackBar}) showTip =
      GameController().headerTipNotifier.showTip;

  bool get isAiSideToMove => controller.gameInstance.isAiSideToMove;

  Map<String, dynamic> _boardTapPayload(int sq) {
    final GameStateSnapshot? snapshot = GameController().activeSessionSnapshot;
    return <String, dynamic>{
      'sq': sq,
      if (snapshot?.phase case final String phase) 'phase': phase,
      if (snapshot?.payload['action'] case final Object action)
        'action': action.toString(),
      if (snapshot?.activeSeat case final PlayerSeat seat)
        'sideToMove': seat.name,
      if (_nativeSessionTapController.selectedFrom case final String selected)
        'selectedFrom': selected,
      'gameMode': GameController().gameInstance.gameMode.name,
    };
  }

  void _recordBoardTapAttempt(int sq, String correlationId) {
    RecordingService().recordEvent(
      RecordingEventType.boardTap,
      _boardTapPayload(sq),
      diagnosticPhase: UserActionPhase.attempt,
      correlationId: correlationId,
    );
  }

  void _recordBoardTapResult(
    int sq,
    String correlationId,
    UserActionPhase phase,
  ) {
    DiagnosticActionTrailService().record(
      actionId: 'game.board.tap',
      phase: phase,
      correlationId: correlationId,
      payload: _boardTapPayload(sq),
    );
  }

  String _recordAiAttempt(PieceColor side) {
    final String correlationId = const Uuid().v4();
    DiagnosticActionTrailService().record(
      actionId: 'game.ai.move',
      phase: UserActionPhase.attempt,
      correlationId: correlationId,
      payload: <String, dynamic>{'side': side.name},
    );
    return correlationId;
  }

  void _recordAiSuccess(
    GameAction action,
    PieceColor side,
    String correlationId,
  ) {
    RecordingService().recordEvent(RecordingEventType.aiMove, <String, dynamic>{
      'move': action.payload['move']?.toString() ?? '',
      'side': side.name,
    }, correlationId: correlationId);
  }

  void _recordAiFailure(PieceColor side, String correlationId, Object error) {
    DiagnosticActionTrailService().record(
      actionId: 'game.ai.move',
      phase: UserActionPhase.failure,
      correlationId: correlationId,
      payload: <String, dynamic>{
        'side': side.name,
        'errorCategory': error.runtimeType.toString(),
      },
    );
  }

  Future<EngineResponse?> _tryNativeSessionTap(
    int sq,
    void Function(UserActionPhase phase) completeAction,
  ) async {
    // The Rust-native session path is now supported for:
    //   - humanVsHuman, humanVsAi (placing / moving / removing)
    //   - remote LAN, Bluetooth, and server-authoritative cloud matches
    //   - puzzle (human plays one side; opponent moves are auto-played
    //     by PuzzlePage from the solution line, not the engine)
    // Replay still depends on legacy side effects.
    final GameMode mode = controller.gameInstance.gameMode;
    if (mode != GameMode.humanVsHuman &&
        mode != GameMode.humanVsAi &&
        mode != GameMode.analysis &&
        mode != GameMode.humanVsLAN &&
        mode != GameMode.humanVsBluetooth &&
        mode != GameMode.humanVsCloud &&
        mode != GameMode.puzzle) {
      _nativeSessionTapController.clearSelection();
      return null;
    }
    final GameSession? session = GameSessionScope.sessionOf(context);
    if (session == null) {
      logger.w("$_logTag Native Mill session flag is on but no GameSession.");
      return const EngineResponseSkip();
    }
    if (session is! NativeMillGameSession) {
      logger.w(
        "$_logTag Native Mill flag is on but session is ${session.runtimeType}.",
      );
      return const EngineResponseSkip();
    }

    // Master parity (onBoardTap): ignore board taps while an experience
    // replay is driving the session.  The replay engine applies both sides'
    // recorded moves; a user tap here would inject an out-of-band move or a
    // concurrent AI search into the replay timeline.
    if (controller.isExperienceReplayActive) {
      logger.i("$_logTag Experience replay active; ignoring tap <$sq>.");
      return const EngineResponseSkip();
    }

    // Serialize AI search: while one search is already in flight, a second
    // board tap must not launch another.  Both searches would read the same
    // pre-move snapshot; the first applies its move and the second's identical
    // result is then rejected as illegal (`bestMove ... is no longer legal`),
    // surfacing as a spurious EngineNoBestMove.  Ignoring the tap lets the
    // single in-flight search finish cleanly.
    if (controller.isEngineRunning) {
      logger.i("$_logTag AI search in flight; ignoring tap <$sq>.");
      return const EngineResponseSkip();
    }

    final bool isRemoteMode =
        mode == GameMode.humanVsLAN ||
        mode == GameMode.humanVsBluetooth ||
        mode == GameMode.humanVsCloud;
    if (isRemoteMode) {
      if (controller.isNativeRemoteOpponentTurn(session)) {
        rootScaffoldMessengerKey.currentState!.showSnackBarClear(
          S.of(context).notYourTurn,
        );
        return const EngineResponseSkip();
      }
      if (!controller.isRemoteConnected) {
        logger.w("$_logTag No ready remote connection");
        showTip(S.of(context).remoteNotConnected, snackBar: true);
        return const EngineResponseSkip();
      }
    }

    // Puzzle mode: the user only controls one side, tracked by
    // GameController.puzzleHumanColor (set by PuzzlePage).  Block taps when it
    // is the opponent's turn or while the app auto-plays the solution line.
    if (mode == GameMode.puzzle) {
      final PieceColor? humanColor = controller.puzzleHumanColor;
      if (humanColor != null) {
        final bool isHumanTurn =
            controller.activeBoardView.sideToMove == humanColor;
        if (!isHumanTurn || controller.isPuzzleAutoMoveInProgress) {
          showTip(S.of(context).opponentSTurn, snackBar: true);
          return const EngineResponseSkip();
        }
      }
    }

    final NativeMillAiTurnController aiTurnController =
        NativeMillAiTurnController(
          generalSettings: DB().generalSettings,
          onBeforeRemoveApply:
              controller.gameInstance.awaitPendingMillSoundBeforeRemove,
          openingBook: MillOpeningBookProvider(
            ruleSettings: session.activeRuleSettings,
            generalSettings: DB().generalSettings,
            placementHistory: openingBookPlacementHistory,
          ),
          humanDatabase: MillHumanDatabaseProvider(
            ruleSettings: session.activeRuleSettings,
            generalSettings: DB().generalSettings,
          ),
        );
    if (mode == GameMode.humanVsAi && aiTurnController.isAiTurn(session)) {
      completeAction(UserActionPhase.cancel);
      final PieceColor aiSide = controller.activeBoardView.sideToMove;
      final String aiCorrelationId = _recordAiAttempt(aiSide);
      controller.isEngineRunning = true;
      controller.refreshNativeSessionHeader(
        context,
        session,
        showThinking: true,
      );
      try {
        final GameAction? aiAction = await aiTurnController.playIfAiTurn(
          session,
        );
        if (aiAction == null) {
          _recordAiFailure(
            aiSide,
            aiCorrelationId,
            StateError('AI returned no move.'),
          );
        } else {
          _recordAiSuccess(aiAction, aiSide, aiCorrelationId);
        }
        if (!context.mounted) {
          return aiAction == null
              ? const EngineNoBestMove()
              : const EngineResponseOK();
        }
        controller.refreshNativeSessionHeader(context, session);
        controller.syncAiMoveTypeFromSession(session);
        logger.i(
          "$_logTag Native Mill AI pre-tap action: ${aiAction?.payload['move'] ?? '(none)'}",
        );
        return aiAction == null
            ? const EngineNoBestMove()
            : const EngineResponseOK();
      } catch (e, st) {
        _recordAiFailure(aiSide, aiCorrelationId, e);
        if (context.mounted) {
          controller.refreshNativeSessionHeader(context, session);
        }
        logger.e(
          "$_logTag Native Mill AI pre-tap action failed: $e",
          stackTrace: st,
        );
        return const EngineNoBestMove();
      } finally {
        controller.isEngineRunning = false;
      }
    }

    final String tappedLabel = ExtMove.sqToNotation(sq);
    final String tipMove = S.of(context).tipMove;
    final PieceColor sideBeforeTap = controller.activeBoardView.sideToMove;
    final MillSessionTapResult result = await _nativeSessionTapController.tap(
      session: session,
      tappedLabel: tappedLabel,
      applyAction: !isRemoteMode,
    );
    if (!context.mounted) {
      return const EngineResponseSkip();
    }

    switch (result.status) {
      case MillSessionTapStatus.selectedSource:
        logger.t(
          "$_logTag Native Mill selected ${result.selectedFrom}; waiting for destination.",
        );
        _applySelectionFeedback(result.selectedFrom);
        showTip(tipMove, snackBar: false);
        completeAction(UserActionPhase.success);
        return const EngineResponseSkip();
      case MillSessionTapStatus.applied:
        final String appliedMove =
            result.action?.payload['move'] as String? ?? tappedLabel;
        if (isRemoteMode) {
          final bool accepted = await controller.submitRemoteMove(appliedMove);
          if (!accepted) {
            completeAction(UserActionPhase.failure);
            if (context.mounted) {
              showTip(S.of(context).remoteActionRejected, snackBar: true);
            }
            return const EngineResponseSkip();
          }
          if (!context.mounted) {
            return const EngineResponseSkip();
          }
        }
        logger.i("$_logTag Native Mill applied $appliedMove");
        completeAction(UserActionPhase.success);
        if (mode == GameMode.humanVsHuman) {
          final PieceColor sideAfterTap = controller.activeBoardView.sideToMove;
          final Phase phaseAfterTap = controller.activeBoardView.phase;
          if (phaseAfterTap == Phase.gameOver) {
            OfflineBoardClock().pause();
          } else if (sideAfterTap != sideBeforeTap &&
              (sideAfterTap == PieceColor.white ||
                  sideAfterTap == PieceColor.black)) {
            OfflineBoardClock().completeTurn(
              sideMoved: sideBeforeTap,
              nextSide: sideAfterTap,
            );
          }
        } else if (!isRemoteMode) {
          PlayerTimer().stop();
        }
        GameController().boardSemanticsNotifier.updateSemantics();
        final bool shouldPlayAi =
            mode == GameMode.humanVsAi && aiTurnController.isAiTurn(session);
        controller.refreshNativeSessionHeader(
          context,
          session,
          showThinking: shouldPlayAi,
        );
        if (shouldPlayAi) {
          final PieceColor aiSide = controller.activeBoardView.sideToMove;
          final String aiCorrelationId = _recordAiAttempt(aiSide);
          controller.isEngineRunning = true;
          try {
            final GameAction? aiAction = await aiTurnController.playIfAiTurn(
              session,
            );
            if (aiAction != null) {
              _recordAiSuccess(aiAction, aiSide, aiCorrelationId);
            } else {
              _recordAiFailure(
                aiSide,
                aiCorrelationId,
                StateError('AI returned no move.'),
              );
            }
            if (!context.mounted) {
              return aiAction == null
                  ? const EngineNoBestMove()
                  : const EngineResponseOK();
            }
            controller.refreshNativeSessionHeader(context, session);
            if (aiAction != null) {
              controller.syncAiMoveTypeFromSession(session);
              PlayerTimer().start();
            }
            logger.i(
              "$_logTag Native Mill AI response: ${aiAction?.payload['move'] ?? '(none)'}",
            );
            return aiAction == null
                ? const EngineNoBestMove()
                : const EngineResponseOK();
          } catch (e, st) {
            _recordAiFailure(aiSide, aiCorrelationId, e);
            if (context.mounted) {
              controller.refreshNativeSessionHeader(context, session);
            }
            logger.e(
              "$_logTag Native Mill AI response failed: $e",
              stackTrace: st,
            );
            return const EngineNoBestMove();
          } finally {
            controller.isEngineRunning = false;
          }
        }
        if (mode != GameMode.humanVsHuman && !isRemoteMode) {
          PlayerTimer().start();
        }
        if (!context.mounted) {
          return const EngineResponseSkip();
        }
        controller.refreshNativeSessionHeader(context, session);
        return const EngineResponseHumanOK();
      case MillSessionTapStatus.ignored:
        logger.t("$_logTag Native Mill ignored tap <$tappedLabel>.");
        completeAction(UserActionPhase.cancel);
        return const EngineResponseSkip();
    }
  }

  /// Visual + audio feedback when the first tap of a move selects a source
  /// piece (moving phase).  Mirrors the legacy `position.dart` selection
  /// behaviour: lift the chosen piece (pick-up animation), highlight it, and
  /// play the select tone.  The destination tap is handled by the session
  /// `moveApplied` event through [MillSessionAnimationBridge].
  void _applySelectionFeedback(String? selectedFrom) {
    if (selectedFrom == null || selectedFrom.isEmpty) {
      return;
    }
    final int node = MillBoardCoordinateMaps.notationToNode(selectedFrom);
    final int? square = MillBoardCoordinateMaps.nodeToLegacySquare[node];
    final int? gridIndex = square == null
        ? null
        : MillBoardCoordinateMaps.squareToGridIndex[square];
    controller.gameInstance
      ..blurIndex = gridIndex
      ..focusIndex = null;
    controller.animationManager.animatePickUp();
    SoundManager().playTone(Sound.select);
  }

  Future<EngineResponse> onBoardTap(int sq) async {
    final String correlationId = const Uuid().v4();
    _recordBoardTapAttempt(sq, correlationId);
    bool completed = false;
    void completeAction(UserActionPhase phase) {
      if (completed) {
        return;
      }
      completed = true;
      _recordBoardTapResult(sq, correlationId, phase);
    }

    try {
      final EngineResponse response = await _handleBoardTap(sq, completeAction);
      if (!completed) {
        final UserActionPhase phase = switch (response) {
          EngineResponseOK() ||
          EngineResponseHumanOK() ||
          EngineGameIsOver() => UserActionPhase.success,
          EngineNoBestMove() || EngineTimeOut() => UserActionPhase.failure,
          EngineResponseSkip() ||
          EngineCancelled() ||
          EngineDummy() => UserActionPhase.cancel,
          _ => UserActionPhase.failure,
        };
        completeAction(phase);
      }
      return response;
    } on Object {
      completeAction(UserActionPhase.failure);
      rethrow;
    }
  }

  Future<EngineResponse> _handleBoardTap(
    int sq,
    void Function(UserActionPhase phase) completeAction,
  ) async {
    // Prevent interaction when analysis is in progress
    if (AnalysisMode.isAnalyzing) {
      logger.i("$_logTag Analysis in progress, ignoring tap.");
      return const EngineResponseSkip();
    }

    // Clear any existing analysis markers when player makes a move
    AnalysisMode.disable();

    // Setup-position editing: route taps to the setup controller, which
    // paints/clears the tapped point and re-syncs the native session.
    if (GameController().gameInstance.gameMode == GameMode.setupPosition) {
      final MillSetupPositionController? setup =
          GameController().setupPositionController;
      if (setup != null) {
        final int node = MillBoardCoordinateMaps.legacySquareToNode[sq] ?? -1;
        if (node >= 0) {
          setup.tapNode(node);
          GameController().setupPositionNotifier.updateIcons();
          GameController().boardSemanticsNotifier.updateSemantics();
          completeAction(UserActionPhase.success);
        }
      }
      return const EngineResponseSkip();
    }

    if (!GameController().isControllerReady) {
      final MillBoardView view = GameController().activeBoardView;
      logger.w(
        "$_logTag [STATE_SNAPSHOT] Tap ignored: isControllerReady=false | "
        "isEngineRunning=${GameController().isEngineRunning} | "
        "isControllerActive=${GameController().isControllerActive} | "
        "isDisposed=${GameController().isDisposed} | "
        "gameMode=${GameController().gameInstance.gameMode} | "
        "phase=${view.phase} | "
        "sideToMove=${view.sideToMove} | "
        "action=${view.action}",
      );
      return const EngineResponseSkip();
    }

    if (GameController().isRemoteGameMode) {
      if (GameController().isRemoteOpponentTurn) {
        rootScaffoldMessengerKey.currentState!.showSnackBarClear(
          S.of(context).notYourTurn,
        );
        return const EngineResponseSkip();
      }
      if (!GameController().isRemoteConnected) {
        logger.w("$_logTag No ready remote connection");
        showTip(S.of(context).remoteNotConnected, snackBar: true);
        return const EngineResponseSkip();
      }
    }

    GameController().loadedGameFilenamePrefix = null;

    if (GameController().gameInstance.gameMode == GameMode.testViaLAN) {
      logger.t("$_logTag Engine type is no human, ignore tapping.");
      return const EngineResponseSkip();
    }

    final EngineResponse? nativeSessionResponse = await _tryNativeSessionTap(
      sq,
      completeAction,
    );
    if (nativeSessionResponse != null) {
      return nativeSessionResponse;
    }

    // Reaching this point means `_tryNativeSessionTap` returned null,
    // which only happens for game modes outside its allow-list
    // (aiVsAi, testViaLAN). None of
    // these accept human taps in steady state.  Surface loudly if a
    // future game mode is added without an explicit native-tap
    // branch; the previous legacy fall-through that mutated
    // `Position` directly is gone with the puzzle removal.
    assert(
      false,
      "$_logTag onBoardTap unreachable: gameMode="
      "${GameController().gameInstance.gameMode}, sq=$sq",
    );
    return const EngineResponseSkip();
  }
}
