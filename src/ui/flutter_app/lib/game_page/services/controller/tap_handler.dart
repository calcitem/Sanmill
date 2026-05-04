// SPDX-License-Identifier: GPL-3.0-or-later
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

  void _recordBoardTap(int sq) {
    final GameStateSnapshot? snapshot = GameController().activeSessionSnapshot;
    RecordingService()
        .recordEvent(RecordingEventType.boardTap, <String, dynamic>{
          'sq': sq,
          'phase': snapshot?.phase,
          'action': snapshot?.payload['action']?.toString(),
          'sideToMove': snapshot?.activeSeat.name,
          if (snapshot != null)
            'selectedFrom': _nativeSessionTapController.selectedFrom,
          'gameMode': GameController().gameInstance.gameMode.toString(),
        });
  }

  Future<EngineResponse?> _tryNativeSessionTap(int sq) async {
    // The Rust-native session path is now supported for:
    //   - humanVsHuman, humanVsAi (placing / moving / removing)
    //   - humanVsLAN
    // Replay still depends on legacy side effects.
    final GameMode mode = controller.gameInstance.gameMode;
    if (mode != GameMode.humanVsHuman &&
        mode != GameMode.humanVsAi &&
        mode != GameMode.humanVsLAN) {
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

    if (mode == GameMode.humanVsLAN) {
      if (controller.isNativeLanOpponentTurn(session)) {
        rootScaffoldMessengerKey.currentState!.showSnackBarClear(
          S.of(context).notYourTurn,
        );
        return const EngineResponseSkip();
      }
      if (GameController().networkService == null ||
          !GameController().networkService!.isConnected) {
        logger.w("$_logTag No active LAN connection");
        showTip(S.of(context).noLanConnection, snackBar: true);
        return const EngineResponseSkip();
      }
    }

    final NativeMillAiTurnController aiTurnController =
        NativeMillAiTurnController(generalSettings: DB().generalSettings);
    if (mode == GameMode.humanVsAi && aiTurnController.isAiTurn(session)) {
      controller.refreshNativeSessionHeader(
        context,
        session,
        showThinking: true,
      );
      try {
        final GameAction? aiAction = await aiTurnController.playIfAiTurn(
          session,
        );
        if (!context.mounted) {
          return aiAction == null
              ? const EngineNoBestMove()
              : const EngineResponseOK();
        }
        controller.refreshNativeSessionHeader(context, session);
        logger.i(
          "$_logTag Native Mill AI pre-tap action: ${aiAction?.payload['move'] ?? '(none)'}",
        );
        return aiAction == null
            ? const EngineNoBestMove()
            : const EngineResponseOK();
      } catch (e, st) {
        if (context.mounted) {
          controller.refreshNativeSessionHeader(context, session);
        }
        logger.e(
          "$_logTag Native Mill AI pre-tap action failed: $e",
          stackTrace: st,
        );
        return const EngineNoBestMove();
      }
    }

    final String tappedLabel = ExtMove.sqToNotation(sq);
    final String tipMove = S.of(context).tipMove;
    final MillSessionTapResult result = await _nativeSessionTapController.tap(
      session: session,
      tappedLabel: tappedLabel,
    );
    if (!context.mounted) {
      return const EngineResponseSkip();
    }

    switch (result.status) {
      case MillSessionTapStatus.selectedSource:
        logger.t(
          "$_logTag Native Mill selected ${result.selectedFrom}; waiting for destination.",
        );
        showTip(tipMove, snackBar: false);
        return const EngineResponseSkip();
      case MillSessionTapStatus.applied:
        logger.i(
          "$_logTag Native Mill applied ${result.action?.payload['move'] ?? tappedLabel}",
        );
        PlayerTimer().stop();
        GameController().boardSemanticsNotifier.updateSemantics();
        if (mode == GameMode.humanVsLAN) {
          final String? appliedMove = result.action?.payload['move'] as String?;
          GameController().sendLanMove(appliedMove ?? tappedLabel);
        }
        final bool shouldPlayAi =
            mode == GameMode.humanVsAi && aiTurnController.isAiTurn(session);
        controller.refreshNativeSessionHeader(
          context,
          session,
          showThinking: shouldPlayAi,
        );
        if (shouldPlayAi) {
          try {
            final GameAction? aiAction = await aiTurnController.playIfAiTurn(
              session,
            );
            if (!context.mounted) {
              return aiAction == null
                  ? const EngineNoBestMove()
                  : const EngineResponseOK();
            }
            controller.refreshNativeSessionHeader(context, session);
            logger.i(
              "$_logTag Native Mill AI response: ${aiAction?.payload['move'] ?? '(none)'}",
            );
            return aiAction == null
                ? const EngineNoBestMove()
                : const EngineResponseOK();
          } catch (e, st) {
            if (context.mounted) {
              controller.refreshNativeSessionHeader(context, session);
            }
            logger.e(
              "$_logTag Native Mill AI response failed: $e",
              stackTrace: st,
            );
            return const EngineNoBestMove();
          }
        }
        controller.refreshNativeSessionHeader(context, session);
        return const EngineResponseHumanOK();
      case MillSessionTapStatus.ignored:
        logger.t("$_logTag Native Mill ignored tap <$tappedLabel>.");
        return const EngineResponseSkip();
    }
  }

  Future<EngineResponse> onBoardTap(int sq) async {
    // Record every tap so replay can reproduce selection + move sequences.
    _recordBoardTap(sq);

    // Prevent interaction when analysis is in progress
    if (AnalysisMode.isAnalyzing) {
      logger.i("$_logTag Analysis in progress, ignoring tap.");
      return const EngineResponseSkip();
    }

    // Clear any existing analysis markers when player makes a move
    AnalysisMode.disable();

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

    if (GameController().gameInstance.gameMode == GameMode.humanVsLAN) {
      if (GameController().isLanOpponentTurn) {
        rootScaffoldMessengerKey.currentState!.showSnackBarClear(
          S.of(context).notYourTurn,
        );
        return const EngineResponseSkip();
      }
      if (GameController().networkService == null ||
          !GameController().networkService!.isConnected) {
        logger.w("$_logTag No active LAN connection");
        showTip(S.of(context).noLanConnection, snackBar: true);
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
    );
    if (nativeSessionResponse != null) {
      return nativeSessionResponse;
    }

    // Reaching this point means `_tryNativeSessionTap` returned null,
    // which only happens for game modes outside its allow-list
    // (aiVsAi, humanVsCloud-not-implemented, testViaLAN).  None of
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
