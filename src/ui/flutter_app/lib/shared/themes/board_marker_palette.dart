// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/material.dart';

/// Semantic colors for temporary information drawn over a Mill board.
///
/// These colors belong to the active board theme rather than user-imported
/// legacy highlight fields. Shape remains the primary distinction; color adds
/// emphasis without being the only carrier of meaning.
@immutable
class BoardMarkerPalette {
  const BoardMarkerPalette._({
    required this.contrast,
    required this.completedMove,
    required this.bestMove,
    required this.secondaryMove,
    required this.threat,
  });

  factory BoardMarkerPalette.fromBackground(Color background) {
    final bool dark = background.computeLuminance() < 0.42;
    return BoardMarkerPalette._(
      contrast: dark ? Colors.white : Colors.black,
      completedMove: dark ? const Color(0xFFD4E76A) : const Color(0xFF5F7300),
      bestMove: dark ? const Color(0xFF64B5F6) : const Color(0xFF1565C0),
      secondaryMove: dark ? const Color(0xFFCFD8DC) : const Color(0xFF546E7A),
      threat: dark ? const Color(0xFFEF9A9A) : const Color(0xFFB71C1C),
    );
  }

  /// High-contrast black or white used for selection and neutral markers.
  final Color contrast;

  /// Yellow-green trail for the most recently played complete or partial turn.
  final Color completedMove;

  /// Blue used for a hint or the engine's preferred move.
  final Color bestMove;

  /// Neutral grey used for lower-ranked engine candidates.
  final Color secondaryMove;

  /// Red used only for opponent-threat overlays.
  final Color threat;

  @override
  bool operator ==(Object other) =>
      other is BoardMarkerPalette &&
      other.contrast == contrast &&
      other.completedMove == completedMove &&
      other.bestMove == bestMove &&
      other.secondaryMove == secondaryMove &&
      other.threat == threat;

  @override
  int get hashCode =>
      Object.hash(contrast, completedMove, bestMove, secondaryMove, threat);
}
