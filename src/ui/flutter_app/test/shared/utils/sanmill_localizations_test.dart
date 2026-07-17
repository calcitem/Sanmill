// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/generated/intl/l10n.dart';
import 'package:sanmill/shared/utils/localizations/sanmill_localizations.dart';

void main() {
  test('separates computer-play and generative AI terminology', () {
    final S english = lookupS(const Locale('en'));
    final S chinese = lookupS(const Locale('zh'));

    expect(english.humanVsAi, 'Human vs computer');
    expect(english.aiVsAi, 'Computer vs computer');
    expect(english.humanAiRobotLevel(7), 'Computer level 7');
    expect(english.advancedAiSearch, 'Advanced engine search');
    expect(english.aiChatTitle, 'AI Assistant');
    expect(english.aiAnalysisTitle, 'AI Game Analysis');

    expect(chinese.humanVsAi, '人机对弈');
    expect(chinese.aiVsAi, '电脑自弈');
    expect(chinese.humanAiRobotLevel(7), '电脑等级 7');
    expect(chinese.advancedAiSearch, '高级引擎搜索');
    expect(chinese.aiChatTitle, 'AI 助手');
    expect(chinese.aiAnalysisTitle, 'AI 棋局分析');
  });

  test('localizes screenshot save failures in English and Chinese', () {
    final S english = lookupS(const Locale('en'));
    final S chinese = lookupS(const Locale('zh'));

    expect(english.failedToSaveImageToGallery, 'Could not save the image.');
    expect(
      english.imageSavingNotSupported,
      'Saving images is not supported on this platform.',
    );
    expect(chinese.failedToSaveImageToGallery, '无法保存图片。');
    expect(chinese.imageSavingNotSupported, '当前平台不支持保存图片。');
  });

  test('localizes annotation semantics in English and Chinese', () {
    final S english = lookupS(const Locale('en'));
    final S chinese = lookupS(const Locale('zh'));

    expect(english.annotationToolName('line'), 'Line tool');
    expect(
      english.selectAnnotationColor(english.annotationColorName('red')),
      'Select red',
    );
    expect(chinese.annotationToolName('line'), '直线工具');
    expect(
      chinese.selectAnnotationColor(chinese.annotationColorName('red')),
      '选择红色',
    );
  });

  test('uses clear English take-back terminology', () {
    final S english = lookupS(const Locale('en'));

    expect(english.takeBack, 'Take back');
    expect(english.takeBackRejected, 'Take-back request declined.');
    expect(english.takeBackAccepted, 'Take-back request accepted.');
    expect(english.takeBackRequestSentToTheOpponent, 'Take-back request sent.');
    expect(
      english.cannotRequestATakeBackWhenItSNotYourTurn,
      'You can request a take back only on your turn.',
    );
    expect(
      english.opponentRequestsTakeBackAccept('1'),
      'Your opponent wants to take back 1 move. Accept?',
    );
    expect(
      english.remoteHistoryNavigationUnavailable,
      'Remote games support only a take-back request for your latest move.',
    );
  });

  test('uses actionable English board-recognition feedback', () {
    final S english = lookupS(const Locale('en'));

    expect(english.analyzingGameBoardImage, 'Analyzing board image…');
    expect(english.identificationResults, 'Recognition results');
    expect(
      english.noPiecesWereRecognizedInTheImagePleaseTryAgain,
      'No pieces were detected. Try a clearer board image.',
    );
    expect(
      english.boardRecognitionFailedTryAgain,
      'Board recognition failed. Try a clearer image with the full board '
      'visible.',
    );
    expect(english.whiteSMove, 'White to move');
    expect(english.blackSMove, 'Black to move');
    expect(english.recognitionParameters, 'Recognition settings');
    expect(
      english.boardRecognitionParameterName('pieceDetectionThreshold'),
      'Piece detection threshold',
    );
    expect(english.generatedFen, 'Generated FEN');
    expect(english.applyThisResultToBoard, 'Apply to board');
    expect(
      english.boardRecognitionApplyHint,
      'Choose “Apply to board” to use this position.',
    );
    expect(
      <String, String>{
        for (final String stage in <String>[
          'originalImage',
          'resizedImage',
          'enhancedImage',
          'boardMaskRaw',
          'boardMaskProcessed',
          'boardDetection',
          'boardPointsDetection',
          'colorAnalysis',
          'pieceDetection',
          'finalResult',
        ])
          stage: english.boardRecognitionDebugStageName(stage),
      },
      <String, String>{
        'originalImage': 'Original image',
        'resizedImage': 'Resized image',
        'enhancedImage': 'Enhanced contrast',
        'boardMaskRaw': 'Initial mask',
        'boardMaskProcessed': 'Processed mask',
        'boardDetection': 'Board detection',
        'boardPointsDetection': 'Point detection',
        'colorAnalysis': 'Color analysis',
        'pieceDetection': 'Piece detection',
        'finalResult': 'Final result',
      },
    );
    expect(
      english.boardRecognitionPointDetectionHelp,
      contains("standard Nine Men's Morris layout"),
    );
    expect(
      english.boardRecognitionPointDetectionHelp.toLowerCase(),
      isNot(contains('chess')),
    );
    expect(english.boardRecognitionPointCount(18), 'Detected 18 of 24 points.');
    expect(
      english.boardRecognitionIdentifiedPieces(4, 3),
      'Detected pieces: 4 white · 3 black',
    );
  });

  test('uses consistent English cat-fishing terminology', () {
    final S english = lookupS(const Locale('en'));

    expect(english.catFishingGameDeveloper, 'Cat fishing game (developer)');
    expect(
      english.catFishingDebugStats(4, '0.13'),
      'Fish caught: 4\nDifficulty: 0.13',
    );
  });

  test('describes analysis board markers accurately in English', () {
    final S english = lookupS(const Locale('en'));

    expect(english.analysisBestMoveArrow, 'Engine line markers');
    expect(
      english.analysisBestMoveArrowDescription,
      'Show the first move of each visible engine line on the board',
    );
  });

  test('uses recipient terminology in English diagnostic reports', () {
    final S english = lookupS(const Locale('en'));

    expect(
      english.diagnosticRecipient('Sanmill diagnostics'),
      'Recipient: Sanmill diagnostics',
    );
  });

  test('uses a plural English home training heading', () {
    final S english = lookupS(const Locale('en'));

    expect(english.dailyTraining, 'Puzzles and training');
  });

  test('describes English puzzle streaks naturally', () {
    final S english = lookupS(const Locale('en'));

    expect(english.puzzleStreakDesc, 'Solve puzzles in a row without mistakes');
  });

  test('distinguishes the current English puzzle rating label', () {
    final S english = lookupS(const Locale('en'));

    expect(english.puzzleStatsRating, 'Puzzle rating');
    expect(english.puzzleStatsCurrentRating, 'Current rating');
    expect(english.puzzleStatsDeviation, 'Rating uncertainty');
  });

  test('uses a direct English import-field hint', () {
    final S english = lookupS(const Locale('en'));

    expect(english.pasteAndImportGameHint, 'Tap to paste and import a game');
  });

  test('explains what the English FEN copy action copies', () {
    final S english = lookupS(const Locale('en'));

    expect(english.copyFen, 'Copy position as FEN');
  });

  test('confirms unlimited English computer thinking time', () {
    final S english = lookupS(const Locale('en'));

    expect(
      english.noTimeLimitForThinking,
      'Computer thinking time is now unlimited.',
    );
  });

  test('punctuates the English background-music description', () {
    final S english = lookupS(const Locale('en'));

    expect(
      english.backgroundMusicDescription,
      'Play a local audio file as background music.',
    );
  });

  test('labels English engine-line values for assistive technology', () {
    final S english = lookupS(const Locale('en'));

    expect(english.analysisEngineLineSemantics(2), 'Engine line 2');
    expect(english.analysisEvaluationSemantics('+3'), 'Evaluation +3');
    expect(english.analysisDepthSemantics(24), 'Depth 24');
  });

  test('explains the English PVS algorithm without search jargon', () {
    final S english = lookupS(const Locale('en'));

    expect(
      english.whatIsPvs,
      'PVS (Principal Variation Search) examines the most promising '
      'sequence of moves first, then quickly checks whether other moves '
      'need a deeper search. This often makes it more efficient than basic '
      'alpha-beta search.',
    );
    expect(english.whatIsPvs, isNot(contains('null or zero window')));
  });

  test('states English human database game counts without ambiguity', () {
    final S english = lookupS(const Locale('en'));

    expect(
      english.humanGameDatabaseStatsLine('d6', '50', '30', '20', 100),
      'd6  W 50%  D 30%  L 20%  Games 100',
    );
    expect(
      english.humanGameDatabaseStatsSemantics('d6', '100', '0', '0', 1),
      "Human game database move d6. From the moving player's perspective: "
      '100 percent wins, 0 percent draws, and 0 percent losses. '
      'Recorded games: 1.',
    );
    expect(
      english.humanGameDatabaseResultsSemantics(50, 20, 30, 2),
      "Human game database results. From the moving player's perspective: "
      '50 percent wins, 20 percent draws, and 30 percent losses. '
      'Recorded games: 2.',
    );
  });

  test('provides framework localizations for every Sanmill locale', () async {
    for (final Locale locale in S.supportedLocales) {
      final WidgetsLocalizations widgetsLocalizations =
          await _loadFirstSupportedLocalization<WidgetsLocalizations>(locale);
      final MaterialLocalizations materialLocalizations =
          await _loadFirstSupportedLocalization<MaterialLocalizations>(locale);
      final CupertinoLocalizations cupertinoLocalizations =
          await _loadFirstSupportedLocalization<CupertinoLocalizations>(locale);

      expect(widgetsLocalizations.textDirection, isA<TextDirection>());
      expect(materialLocalizations.okButtonLabel, isNotEmpty);
      expect(cupertinoLocalizations.alertDialogLabel, isNotEmpty);
    }
  });

  test('uses Flutter Tibetan WidgetsLocalizations', () async {
    const Locale tibetan = Locale('bo');

    expect(GlobalWidgetsLocalizations.delegate.isSupported(tibetan), isTrue);
    expect(S.supportedLocales, contains(tibetan));

    final WidgetsLocalizations widgetsLocalizations =
        await _loadFirstSupportedLocalization<WidgetsLocalizations>(tibetan);

    expect(widgetsLocalizations, isNot(isA<DefaultWidgetsLocalizations>()));
  });
}

Future<T> _loadFirstSupportedLocalization<T>(Locale locale) {
  final LocalizationsDelegate<T> delegate = sanmillLocalizationsDelegates
      .whereType<LocalizationsDelegate<T>>()
      .firstWhere((LocalizationsDelegate<T> delegate) {
        return delegate.isSupported(locale);
      });

  return delegate.load(locale);
}
