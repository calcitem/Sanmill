// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/foundation.dart';

enum LlmTask { positionAnalysis, explainLastMove, gameReview, explainRules }

enum LlmSafetyDecision { allow, block }

enum LlmErrorCode {
  notConfigured,
  consentRequired,
  unsupportedPlatform,
  invalidEndpoint,
  network,
  timeout,
  invalidResponse,
  safetyBlocked,
}

class LlmException implements Exception {
  const LlmException(this.code);
  final LlmErrorCode code;
}

@immutable
class LlmGameContext {
  const LlmGameContext({
    required this.fen,
    required this.variant,
    required this.sideToMove,
    required this.phase,
    required this.action,
    required this.whitePiecesOnBoard,
    required this.whitePiecesInHand,
    required this.blackPiecesOnBoard,
    required this.blackPiecesInHand,
    required this.rules,
    required this.moves,
    required this.movesTruncated,
  });

  final String fen;
  final String variant;
  final String sideToMove;
  final String phase;
  final String action;
  final int whitePiecesOnBoard;
  final int whitePiecesInHand;
  final int blackPiecesOnBoard;
  final int blackPiecesInHand;
  final Map<String, Object?> rules;
  final List<String> moves;
  final bool movesTruncated;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'fen': fen,
    'variant': variant,
    'sideToMove': sideToMove,
    'phase': phase,
    'action': action,
    'pieceCounts': <String, int>{
      'whiteOnBoard': whitePiecesOnBoard,
      'whiteInHand': whitePiecesInHand,
      'blackOnBoard': blackPiecesOnBoard,
      'blackInHand': blackPiecesInHand,
    },
    'rules': rules,
    'moves': moves,
    'movesTruncated': movesTruncated,
  };
}

@immutable
class LlmAnalysisRequest {
  const LlmAnalysisRequest({
    required this.task,
    required this.locale,
    required this.gameContext,
  });

  static const int schemaVersion = 1;
  final LlmTask task;
  final String locale;
  final LlmGameContext gameContext;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'schemaVersion': schemaVersion,
    'task': task.name,
    'locale': locale,
    'gameContext': gameContext.toJson(),
  };
}

@immutable
class LlmAnalysisResult {
  const LlmAnalysisResult({
    required this.requestId,
    required this.answer,
    required this.provider,
    required this.model,
    required this.safetyDecision,
    required this.safetyPolicyVersion,
  });

  final String requestId;
  final String answer;
  final String provider;
  final String model;
  final LlmSafetyDecision safetyDecision;
  final String safetyPolicyVersion;
}
