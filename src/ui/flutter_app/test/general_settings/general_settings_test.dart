// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// general_settings_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/general_settings/models/general_settings.dart';

void main() {
  // ---------------------------------------------------------------------------
  // Default values
  // ---------------------------------------------------------------------------
  group('GeneralSettings defaults', () {
    test('should have sensible defaults for all fields', () {
      const GeneralSettings s = GeneralSettings();

      expect(s.isPrivacyPolicyAccepted, isFalse);
      expect(s.toneEnabled, isTrue);
      expect(s.keepMuteWhenTakingBack, isTrue);
      expect(s.screenReaderSupport, isFalse);
      expect(s.aiMovesFirst, isFalse);
      expect(s.aiIsLazy, isFalse);
      expect(s.skillLevel, 1);
      expect(s.moveTime, 1);
      expect(s.humanMoveTime, 0);
      expect(s.isAutoRestart, isFalse);
      expect(s.isAutoChangeFirstMove, isFalse);
      expect(s.resignIfMostLose, isFalse);
      expect(s.shufflingEnabled, isTrue);
      expect(s.learnEndgame, isFalse);
      expect(s.searchAlgorithm, SearchAlgorithm.mtdf);
      expect(s.usePerfectDatabase, isFalse);
      expect(s.drawOnHumanExperience, isTrue);
      expect(s.considerMobility, isTrue);
      expect(s.focusOnBlockingPaths, isFalse);
      expect(s.firstRun, isTrue);
      expect(s.gameScreenRecorderSupport, isFalse);
      expect(s.gameScreenRecorderDuration, 2);
      expect(s.gameScreenRecorderPixelRatio, 50);
      expect(s.showTutorial, isTrue);
      expect(s.remindedOpponentMayFly, isFalse);
      expect(s.vibrationEnabled, isFalse);
      expect(s.soundTheme, SoundTheme.ball);
      expect(s.useOpeningBook, isFalse);
      expect(s.llmProvider, LlmProvider.openai);
      expect(s.llmTemperature, 0.7);
      expect(s.aiChatEnabled, isFalse);
      expect(s.trapAwareness, isFalse);
      expect(s.backgroundMusicEnabled, isFalse);
      expect(s.backgroundMusicFilePath, '');
      expect(s.lastPgnSaveDirectory, '');
    });
  });

  // ---------------------------------------------------------------------------
  // SearchAlgorithm extension
  // ---------------------------------------------------------------------------
  group('SearchAlgorithm.name', () {
    test('should return human-readable names', () {
      expect(SearchAlgorithm.alphaBeta.name, 'Alpha-Beta');
      expect(SearchAlgorithm.pvs.name, 'PVS');
      expect(SearchAlgorithm.mtdf.name, 'MTD(f)');
      expect(SearchAlgorithm.mcts.name, 'MCTS');
      expect(SearchAlgorithm.random.name, 'Random');
    });

    test('should cover all SearchAlgorithm values', () {
      for (final SearchAlgorithm algo in SearchAlgorithm.values) {
        expect(algo.name, isNotEmpty, reason: 'Name for $algo');
      }
    });
  });

  // ---------------------------------------------------------------------------
  // SoundTheme extension
  // ---------------------------------------------------------------------------
  group('SoundTheme.name', () {
    test('should return directory-friendly names', () {
      expect(SoundTheme.ball.name, 'ball');
      expect(SoundTheme.liquid.name, 'liquid');
      expect(SoundTheme.wood.name, 'wood');
    });

    test('should cover all SoundTheme values', () {
      for (final SoundTheme theme in SoundTheme.values) {
        expect(theme.name, isNotEmpty, reason: 'Name for $theme');
      }
    });
  });

  // ---------------------------------------------------------------------------
  // LlmProvider extension
  // ---------------------------------------------------------------------------
  group('LlmProvider.name', () {
    test('should return human-readable names', () {
      expect(LlmProvider.openai.name, 'OpenAI API');
      expect(LlmProvider.google.name, 'Google Gemini API');
      expect(LlmProvider.ollama.name, 'Ollama API');
    });

    test('should cover all LlmProvider values', () {
      for (final LlmProvider provider in LlmProvider.values) {
        expect(provider.name, isNotEmpty, reason: 'Name for $provider');
      }
    });
  });

  // ---------------------------------------------------------------------------
  // Default prompt helpers
  // ---------------------------------------------------------------------------
  group('Default prompt headers/footers', () {
    test('defaultLlmPromptHeader should be accessible', () {
      // It may be empty string or actual content
      expect(GeneralSettings.defaultLlmPromptHeader, isA<String>());
    });

    test('defaultLlmPromptFooter should be accessible', () {
      expect(GeneralSettings.defaultLlmPromptFooter, isA<String>());
    });
  });
}
