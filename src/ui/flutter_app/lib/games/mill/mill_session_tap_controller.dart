// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import '../../game_platform/game_session.dart';
import 'mill_tap_action_selector.dart';

enum MillSessionTapStatus { ignored, selectedSource, applied }

class MillSessionTapResult {
  const MillSessionTapResult._(this.status, {this.action, this.selectedFrom});

  const MillSessionTapResult.ignored() : this._(MillSessionTapStatus.ignored);

  const MillSessionTapResult.selectedSource(String selectedFrom)
    : this._(MillSessionTapStatus.selectedSource, selectedFrom: selectedFrom);

  const MillSessionTapResult.applied(GameAction action)
    : this._(MillSessionTapStatus.applied, action: action);

  final MillSessionTapStatus status;
  final GameAction? action;
  final String? selectedFrom;
}

/// Stateful board-tap adapter for the session-backed Mill path.
///
/// The controller stores only the source label selected by the first tap of a
/// Move action.  It does not know about rendering, timers, AI, LAN, or tips;
/// those remain in `TapHandler`.  This makes the rules-port transition small:
/// `TapHandler` can convert a board square to notation, call [tap], and react
/// to whether a source was selected or an action was applied.
class MillSessionTapController {
  String? _selectedFrom;

  String? get selectedFrom => _selectedFrom;

  void clearSelection() {
    _selectedFrom = null;
  }

  Future<MillSessionTapResult> tap({
    required GameSession session,
    required String tappedLabel,
  }) async {
    if (session.outcome.isTerminal) {
      clearSelection();
      return const MillSessionTapResult.ignored();
    }

    final MillTapActionSelection selection = MillTapActionSelector.select(
      legalActions: session.legalActions,
      tappedLabel: tappedLabel,
      selectedFrom: _selectedFrom,
    );

    final GameAction? action = selection.action;
    if (action != null) {
      clearSelection();
      await session.apply(action);
      return MillSessionTapResult.applied(action);
    }

    final String? selected = selection.selectedFrom;
    if (selected != null) {
      _selectedFrom = selected;
      return MillSessionTapResult.selectedSource(selected);
    }

    clearSelection();
    return const MillSessionTapResult.ignored();
  }
}
