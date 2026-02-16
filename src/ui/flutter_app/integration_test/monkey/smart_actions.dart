// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// smart_actions.dart
//
// Phase-aware random action generators for smart monkey testing.
// Each action understands the current game state and performs a valid
// (or intentionally invalid) interaction appropriate for the situation.

// ignore_for_file: avoid_print

import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_page/services/mill.dart';

import '../helpers.dart';
import 'board_tap_helper.dart';
import 'game_state_reader.dart';

/// Result of a smart action attempt.
enum ActionResult {
  /// Action completed successfully.
  success,

  /// Action was skipped (e.g. no valid target).
  skipped,

  /// The board widget is not visible (e.g. navigated away).
  boardNotVisible,

  /// The game is over.
  gameOver,
}

/// Central coordinator for smart monkey actions.
///
/// Reads the current game state, selects an appropriate action,
/// and executes it via board taps or UI interactions.
class SmartActions {
  SmartActions({int? seed}) : _random = Random(seed);

  final Random _random;

  /// Running counters for logging.
  int placingActions = 0;
  int movingActions = 0;
  int removingActions = 0;
  int uiActions = 0;
  int newGameActions = 0;
  int skippedActions = 0;

  /// Perform one smart action based on the current game state.
  ///
  /// With [gameActionProbability] controlling how often game-relevant
  /// actions are chosen over random UI interactions.
  Future<ActionResult> performAction(
    WidgetTester tester, {
    double gameActionProbability = 0.85,
  }) async {
    // If the game page is not showing, try to navigate back.
    if (find.byKey(const Key('game_page_scaffold')).evaluate().isEmpty) {
      print('[SmartAction] Not on game page, attempting to navigate back');
      return _navigateBackToGame(tester);
    }

    // Wait for the controller to be ready before game actions.
    if (!GameController().isControllerReady) {
      print('[SmartAction] Controller not ready, pumping...');
      await tester.pump(const Duration(milliseconds: 300));
      skippedActions++;
      return ActionResult.skipped;
    }

    // Decide: game action or UI action.
    if (_random.nextDouble() < gameActionProbability) {
      return _performGameAction(tester);
    } else {
      return _performUIAction(tester);
    }
  }

  /// Perform a game-relevant action based on the current phase and action.
  Future<ActionResult> _performGameAction(WidgetTester tester) async {
    // In setup position mode, just tap random board positions.
    if (GameStateReader.gameMode == GameMode.setupPosition) {
      return _performSetupPositionAction(tester);
    }

    if (GameStateReader.isGameOver) {
      return _handleGameOver(tester);
    }

    // If we need to remove a piece, that takes priority.
    if (GameStateReader.isRemoving) {
      return _performRemoveAction(tester);
    }

    if (GameStateReader.isPlacing) {
      return _performPlaceAction(tester);
    }

    if (GameStateReader.isMoving) {
      return _performMoveAction(tester);
    }

    // Fallback: tap a random empty square.
    print('[SmartAction] Unknown state, tapping random empty square');
    return _tapRandomEmptySquare(tester);
  }

  // --------------------------------------------------------------------------
  // Setup position mode
  // --------------------------------------------------------------------------

  /// In setup position mode, tap random board positions to place or remove
  /// pieces freely.
  Future<ActionResult> _performSetupPositionAction(
    WidgetTester tester,
  ) async {
    final List<int> allSquares = BoardTapHelper.getAllSquares();
    if (allSquares.isEmpty) {
      skippedActions++;
      return ActionResult.skipped;
    }

    final int target = allSquares[_random.nextInt(allSquares.length)];
    print('[SmartAction] SetupPosition: tapping square '
        '${squareToNotation(target)}');

    final bool ok = await BoardTapHelper.tapSquare(tester, target);
    await tester.pump(const Duration(milliseconds: 100));

    if (ok) {
      placingActions++;
      return ActionResult.success;
    }
    return ActionResult.boardNotVisible;
  }

  // --------------------------------------------------------------------------
  // Placing phase
  // --------------------------------------------------------------------------

  /// During placing phase: tap a random empty position on the board.
  Future<ActionResult> _performPlaceAction(WidgetTester tester) async {
    final List<int> empty = GameStateReader.emptySquares;
    if (empty.isEmpty) {
      print('[SmartAction] Place: no empty squares');
      skippedActions++;
      return ActionResult.skipped;
    }

    final int target = empty[_random.nextInt(empty.length)];
    print('[SmartAction] Place: tapping empty square $target '
        '(${squareToNotation(target)}) '
        'for ${GameStateReader.sideToMove}');

    final bool ok = await BoardTapHelper.tapSquare(tester, target);
    await _safePumpAndSettle(tester);

    if (ok) {
      placingActions++;
      return ActionResult.success;
    }
    return ActionResult.boardNotVisible;
  }

  // --------------------------------------------------------------------------
  // Moving phase
  // --------------------------------------------------------------------------

  /// During moving phase: select an own piece, then tap an adjacent empty
  /// square (or any empty square if the piece can fly).
  Future<ActionResult> _performMoveAction(WidgetTester tester) async {
    final PieceColor side = GameStateReader.sideToMove;
    final bool canFly = GameStateReader.canCurrentSideFly;

    // Find pieces that have at least one valid destination.
    List<int> candidates;
    if (canFly) {
      // When flying, any owned piece can move to any empty square.
      candidates = GameStateReader.occupiedSquares(side);
    } else {
      candidates = GameStateReader.movablePieces(side);
    }

    if (candidates.isEmpty) {
      print('[SmartAction] Move: no movable pieces for $side');
      skippedActions++;
      return ActionResult.skipped;
    }

    // Pick a random piece to move.
    final int piece = candidates[_random.nextInt(candidates.length)];

    // Pick a destination.
    List<int> destinations;
    if (canFly) {
      destinations = GameStateReader.emptySquares;
    } else {
      destinations = GameStateReader.adjacentEmptySquaresOf(piece);
    }

    if (destinations.isEmpty) {
      print('[SmartAction] Move: piece $piece has no destinations');
      skippedActions++;
      return ActionResult.skipped;
    }

    final int dest = destinations[_random.nextInt(destinations.length)];

    print('[SmartAction] Move: select ${squareToNotation(piece)} '
        '→ ${squareToNotation(dest)} for $side'
        '${canFly ? " (flying)" : ""}');

    // Step 1: tap the piece to select it.
    bool ok = await BoardTapHelper.tapSquare(tester, piece);
    if (!ok) return ActionResult.boardNotVisible;
    await tester.pump(const Duration(milliseconds: 150));

    // Step 2: tap the destination to move.
    ok = await BoardTapHelper.tapSquare(tester, dest);
    if (!ok) return ActionResult.boardNotVisible;
    await _safePumpAndSettle(tester);

    movingActions++;
    return ActionResult.success;
  }

  // --------------------------------------------------------------------------
  // Removing phase
  // --------------------------------------------------------------------------

  /// During remove action: tap a random opponent piece.
  Future<ActionResult> _performRemoveAction(WidgetTester tester) async {
    final List<int> opponentPieces = GameStateReader.opponentSquares;
    if (opponentPieces.isEmpty) {
      print('[SmartAction] Remove: no opponent pieces');
      skippedActions++;
      return ActionResult.skipped;
    }

    // Pick a random opponent piece to remove.
    final int target =
        opponentPieces[_random.nextInt(opponentPieces.length)];
    print('[SmartAction] Remove: tapping opponent piece at '
        '${squareToNotation(target)} for ${GameStateReader.sideToMove}');

    final bool ok = await BoardTapHelper.tapSquare(tester, target);
    await _safePumpAndSettle(tester);

    if (ok) {
      removingActions++;
      return ActionResult.success;
    }
    return ActionResult.boardNotVisible;
  }

  // --------------------------------------------------------------------------
  // Game over handling
  // --------------------------------------------------------------------------

  /// When the game is over, start a new one.
  Future<ActionResult> _handleGameOver(WidgetTester tester) async {
    print('[SmartAction] Game over (winner=${GameStateReader.winner}), '
        'starting new game');

    // Dismiss any dialogs that may be showing (game result dialog).
    await _dismissDialogs(tester);

    // Start a new game via the toolbar.
    try {
      await startNewGame(tester);
      newGameActions++;
      return ActionResult.success;
    } catch (e) {
      print('[SmartAction] Failed to start new game: $e');
      return ActionResult.skipped;
    }
  }

  // --------------------------------------------------------------------------
  // UI interactions
  // --------------------------------------------------------------------------

  /// Perform a random UI interaction.
  Future<ActionResult> _performUIAction(WidgetTester tester) async {
    final int choice = _random.nextInt(6);
    switch (choice) {
      case 0:
        return _uiTapToolbarInfo(tester);
      case 1:
        return _uiTapToolbarMove(tester);
      case 2:
        return _uiOpenCloseDrawer(tester);
      case 3:
        return _uiStartNewGame(tester);
      case 4:
        return _uiTapToolbarOptions(tester);
      case 5:
      default:
        // Tap a random area on the board (stress test for invalid positions).
        return _tapRandomBoardArea(tester);
    }
  }

  Future<ActionResult> _uiTapToolbarInfo(WidgetTester tester) async {
    print('[SmartAction] UI: tap Info toolbar');
    try {
      await tapToolbarItem(tester, 'play_area_toolbar_item_info');
      await _safePumpAndSettle(tester);

      // Dismiss the info dialog if it appeared.
      await _dismissDialogs(tester);
      uiActions++;
      return ActionResult.success;
    } catch (e) {
      print('[SmartAction] UI Info failed: $e');
      return ActionResult.skipped;
    }
  }

  Future<ActionResult> _uiTapToolbarMove(WidgetTester tester) async {
    print('[SmartAction] UI: tap Move toolbar');
    try {
      await tapToolbarItem(tester, 'play_area_toolbar_item_move');
      await _safePumpAndSettle(tester);

      // If we navigated to MovesListPage, go back.
      if (find.byKey(const Key('game_page_scaffold')).evaluate().isEmpty) {
        await _navigateBackToGame(tester);
      }
      uiActions++;
      return ActionResult.success;
    } catch (e) {
      print('[SmartAction] UI Move failed: $e');
      return ActionResult.skipped;
    }
  }

  Future<ActionResult> _uiTapToolbarOptions(WidgetTester tester) async {
    print('[SmartAction] UI: tap Options toolbar');
    try {
      await tapToolbarItem(tester, 'play_area_toolbar_item_options');
      await _safePumpAndSettle(tester);

      // Navigate back from settings page.
      if (find.byKey(const Key('game_page_scaffold')).evaluate().isEmpty) {
        await _navigateBackToGame(tester);
      }
      uiActions++;
      return ActionResult.success;
    } catch (e) {
      print('[SmartAction] UI Options failed: $e');
      return ActionResult.skipped;
    }
  }

  Future<ActionResult> _uiOpenCloseDrawer(WidgetTester tester) async {
    print('[SmartAction] UI: open/close drawer');
    try {
      await openDrawer(tester);
      await _safePumpAndSettle(tester);
      await closeDrawer(tester);
      await _safePumpAndSettle(tester);
      uiActions++;
      return ActionResult.success;
    } catch (e) {
      print('[SmartAction] UI Drawer failed: $e');
      return ActionResult.skipped;
    }
  }

  Future<ActionResult> _uiStartNewGame(WidgetTester tester) async {
    print('[SmartAction] UI: start new game');
    try {
      await _dismissDialogs(tester);
      await startNewGame(tester);
      newGameActions++;
      return ActionResult.success;
    } catch (e) {
      print('[SmartAction] UI NewGame failed: $e');
      return ActionResult.skipped;
    }
  }

  // --------------------------------------------------------------------------
  // Helper methods
  // --------------------------------------------------------------------------

  /// Tap a random empty square on the board.
  Future<ActionResult> _tapRandomEmptySquare(WidgetTester tester) async {
    final List<int> empty = GameStateReader.emptySquares;
    if (empty.isEmpty) {
      skippedActions++;
      return ActionResult.skipped;
    }
    final int target = empty[_random.nextInt(empty.length)];
    final bool ok = await BoardTapHelper.tapSquare(tester, target);
    await _safePumpAndSettle(tester);
    return ok ? ActionResult.success : ActionResult.boardNotVisible;
  }

  /// Tap a random area on the board (not necessarily a valid intersection).
  Future<ActionResult> _tapRandomBoardArea(WidgetTester tester) async {
    print('[SmartAction] UI: tap random board area');
    final bool ok = await BoardTapHelper.tapRandomBoardArea(tester);
    await tester.pump(const Duration(milliseconds: 100));
    uiActions++;
    return ok ? ActionResult.success : ActionResult.boardNotVisible;
  }

  /// Try to dismiss any visible dialogs by tapping common dismiss buttons.
  Future<void> _dismissDialogs(WidgetTester tester) async {
    // Try OK / Yes / close buttons commonly used in dialogs.
    for (final String key in <String>[
      'game_result_alert_dialog_yes_button',
      'game_result_alert_dialog_no_button',
      'game_result_alert_dialog_cancel_button',
      'game_result_alert_dialog_restart_button',
      'ai_vs_ai_game_result_dialog_close_button',
      'ai_vs_ai_game_result_dialog_restart_button',
      'restart_game_yes_button',
      'info_dialog_ok_button',
    ]) {
      final Finder btn = find.byKey(Key(key));
      if (btn.evaluate().isNotEmpty) {
        await tester.tap(btn.first);
        await _safePumpAndSettle(tester);
      }
    }

    // Try generic OK / text buttons.
    final Finder okText = find.text('OK');
    if (okText.evaluate().isNotEmpty) {
      try {
        await tester.tap(okText.first);
        await _safePumpAndSettle(tester);
      } catch (_) {
        // Ignore if not tappable.
      }
    }
  }

  /// Try to navigate back to the game page.
  Future<ActionResult> _navigateBackToGame(WidgetTester tester) async {
    // First dismiss any dialogs that might be open.
    await _dismissDialogs(tester);

    // Try a keyed back button.
    final Finder backButton = find.byKey(const Key('game_page_back_button'));
    if (backButton.evaluate().isNotEmpty) {
      await tester.tap(backButton.first);
      await _safePumpAndSettle(tester);
      return ActionResult.success;
    }

    // Try the AppBar back arrow by tooltip.
    final Finder anyBackButton = find.byTooltip('Back');
    if (anyBackButton.evaluate().isNotEmpty) {
      await tester.tap(anyBackButton.first);
      await _safePumpAndSettle(tester);
      return ActionResult.success;
    }

    // Try the system back gesture (pop the current route).
    final NavigatorState? nav = _findNavigator(tester);
    if (nav != null && nav.canPop()) {
      nav.pop();
      await _safePumpAndSettle(tester);
      return ActionResult.success;
    }

    print('[SmartAction] Cannot navigate back to game page');
    return ActionResult.skipped;
  }

  /// Find the root Navigator from the widget tree.
  NavigatorState? _findNavigator(WidgetTester tester) {
    try {
      final Finder navFinder = find.byType(Navigator);
      if (navFinder.evaluate().isNotEmpty) {
        return tester.state<NavigatorState>(navFinder.last);
      }
    } catch (_) {
      // Ignore.
    }
    return null;
  }

  /// Pump and settle with a timeout guard.
  ///
  /// Unlike [WidgetTester.pumpAndSettle] this will not throw if the
  /// widget tree does not settle within [timeout]. It simply pumps for
  /// the given duration and continues.
  Future<void> _safePumpAndSettle(
    WidgetTester tester, {
    Duration timeout = const Duration(seconds: 3),
  }) async {
    try {
      await tester.pumpAndSettle(timeout);
    } on FlutterError {
      // pumpAndSettle timed out — the tree may still be animating
      // (e.g. AI thinking indicator). Pump once and move on.
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// Print a summary of all actions performed.
  void printSummary() {
    final int total =
        placingActions +
        movingActions +
        removingActions +
        uiActions +
        newGameActions +
        skippedActions;
    print('');
    print('[SmartMonkey] ============= ACTION SUMMARY =============');
    print('[SmartMonkey] Total actions:    $total');
    print('[SmartMonkey] Placing actions:  $placingActions');
    print('[SmartMonkey] Moving actions:   $movingActions');
    print('[SmartMonkey] Removing actions: $removingActions');
    print('[SmartMonkey] UI actions:       $uiActions');
    print('[SmartMonkey] New game actions: $newGameActions');
    print('[SmartMonkey] Skipped actions:  $skippedActions');
    print('[SmartMonkey] ==========================================');
    print('');
  }
}
