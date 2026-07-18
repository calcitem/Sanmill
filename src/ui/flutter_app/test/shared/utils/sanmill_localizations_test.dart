// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/generated/intl/l10n.dart';
import 'package:sanmill/shared/utils/localizations/sanmill_localizations.dart';

void main() {
  test('distinguishes Chinese ring-swap semantics from its compact label', () {
    final S chinese = lookupS(const Locale('zh'));

    expect(chinese.innerOuterFlip, '交换内外环');
    expect(chinese.innerOuterFlipShort, '内外环');
  });

  test('describes special-capture phases in player-facing language', () {
    final S english = lookupS(const Locale('en'));

    expect(english.captureExecutionPhases, 'Available during');
  });

  test('describes special-capture phases naturally in Chinese', () {
    final S chinese = lookupS(const Locale('zh'));

    expect(chinese.captureExecutionPhases, '可用阶段');
  });

  test('names the minimum-piece rule in player-facing language', () {
    final S english = lookupS(const Locale('en'));

    expect(english.piecesAtLeastCount, 'Minimum pieces to continue');
  });

  test('names the minimum-piece rule naturally in Chinese', () {
    final S chinese = lookupS(const Locale('zh'));

    expect(chinese.piecesAtLeastCount, '继续对局的最少棋子数');
  });

  test('distinguishes GIF sharing setup from the share action', () {
    final S english = lookupS(const Locale('en'));

    expect(english.gameScreenRecorder, 'GIF sharing');
    expect(english.enableGifSharing, 'Enable GIF sharing');
    expect(english.shareGIF, 'Share GIF');
    expect(english.duration, 'Repeat count');
    expect(
      english.gifRepeatCountDescription,
      'Number of times the exported GIF repeats.',
    );
    expect(english.pixelRatio, 'Image scale');
    expect(
      english.gifImageScaleDescription,
      'Export resolution relative to the board on screen.',
    );
  });

  test('distinguishes Chinese GIF sharing from video recording', () {
    final S chinese = lookupS(const Locale('zh'));

    expect(chinese.gameScreenRecorder, 'GIF 分享');
    expect(chinese.enableGifSharing, '启用 GIF 分享');
    expect(chinese.shareGIF, '分享 GIF');
    expect(chinese.duration, '重复次数');
    expect(chinese.gifRepeatCountDescription, '导出的 GIF 重复播放次数。');
    expect(chinese.pixelRatio, '图像缩放比例');
    expect(chinese.gifImageScaleDescription, '导出分辨率相对于屏幕棋盘尺寸的比例。');
  });

  test('gives actionable English background-music import errors', () {
    final S english = lookupS(const Locale('en'));

    expect(
      english.backgroundMusicFormatUnsupported('.ogg', '.mp3, .wav'),
      'The .ogg format is not supported on this device. '
      'Choose one of these formats: .mp3, .wav.',
    );
    expect(
      english.backgroundMusicImportFailed,
      'Could not import this audio file. Choose another file and try again.',
    );
  });

  test('gives actionable Chinese background-music import errors', () {
    final S chinese = lookupS(const Locale('zh'));

    expect(
      chinese.backgroundMusicFormatUnsupported('.ogg', '.mp3、.wav'),
      '此设备不支持 .ogg 格式。请选择以下格式之一：.mp3、.wav。',
    );
    expect(chinese.backgroundMusicImportFailed, '无法导入此音频文件。请选择其他文件后重试。');
  });

  test('keeps internal review terminology out of the English UI', () {
    final S english = lookupS(const Locale('en'));

    expect(
      english.reviewStructureCounts(12, 15, 1),
      '12 moves · 15 actions · 1 variation',
    );
    expect(
      english.reviewStructureCounts(1, 1, 2),
      '1 move · 1 action · 2 variations',
    );
    expect(english.reviewStructureCounts(12, 15, 1), isNot(contains('atomic')));
  });

  test('keeps internal review terminology out of the Chinese UI', () {
    final S chinese = lookupS(const Locale('zh'));

    expect(chinese.reviewStructureCounts(3, 4, 1), '3 手 · 4 个动作 · 1 条变化');
    expect(chinese.reviewStructureCounts(3, 4, 1), isNot(contains('原子')));
  });

  test('uses player-facing wording for deeper move analysis', () {
    final S english = lookupS(const Locale('en'));

    expect(english.deepAnalysis, 'Analyze this move more deeply');
    expect(english.deepAnalysis, isNot(contains('turn')));
    expect(english.deepAnalysis, isNot(contains('deepen')));
  });

  test('uses player-facing Chinese wording for deeper move analysis', () {
    final S chinese = lookupS(const Locale('zh'));

    expect(chinese.deepAnalysis, '深入分析这手棋');
  });

  test('explains Chinese review search-capacity limits precisely', () {
    final S chinese = lookupS(const Locale('zh'));

    expect(
      chinese.reviewUnsupportedPosition(73, 72),
      '当前规则下，此局面有 73 个合法动作，超过支持的搜索容量 72。',
    );
  });

  test('labels English review navigation as moves rather than pages', () {
    final S english = lookupS(const Locale('en'));

    expect(english.reviewFirstMove, 'First move');
    expect(english.reviewPreviousMove, 'Previous move');
    expect(english.reviewNextMove, 'Next move');
    expect(english.reviewLastMove, 'Last move');
    expect(english.reviewMoveProgress(2, 14), 'Move 2 of 14');
  });

  test('labels Chinese review navigation as moves rather than steps', () {
    final S chinese = lookupS(const Locale('zh'));

    expect(chinese.reviewFirstMove, '第一手');
    expect(chinese.reviewPreviousMove, '上一手');
    expect(chinese.reviewNextMove, '下一手');
    expect(chinese.reviewLastMove, '最后一手');
    expect(chinese.reviewMoveProgress(2, 14), '第 2 手，共 14 手');
  });

  test('labels English analysis move counts without export jargon', () {
    final S english = lookupS(const Locale('en'));

    expect(english.analysisMoveCount(0), 'No moves');
    expect(english.analysisMoveCount(1), '1 move');
    expect(english.analysisMoveCount(12), '12 moves');
    expect(english.analysisVariationCount(1), '1 variation');
    expect(english.analysisVariationCount(2), '2 variations');
    expect(
      english.openMoveListWithSmallBoard,
      'Open move list with board previews',
    );
    expect(english.boardPreviews, 'Board previews');
  });

  test('labels Chinese analysis move and variation counts naturally', () {
    final S chinese = lookupS(const Locale('zh'));

    expect(chinese.analysisMoveCount(0), '暂无着法');
    expect(chinese.analysisMoveCount(1), '1 手');
    expect(chinese.analysisMoveCount(12), '12 手');
    expect(chinese.analysisVariationCount(1), '1 条变化');
    expect(chinese.analysisVariationCount(2), '2 条变化');
    expect(chinese.openMoveListWithSmallBoard, '打开带棋盘预览的着法列表');
  });

  test('expands English clock controls for assistive technology', () {
    final S english = lookupS(const Locale('en'));

    expect(english.exitClock, 'Exit clock');
    expect(english.resetClock, 'Reset clock');
    expect(english.clockPresetSemantics(1, 0), '1 minute, no increment');
    expect(english.clockPresetSemantics(5, 1), '5 minutes, 1-second increment');
    expect(
      english.clockPresetSemantics(10, 3),
      '10 minutes, 3-second increment',
    );
  });

  test('expands Chinese clock controls for assistive technology', () {
    final S chinese = lookupS(const Locale('zh'));

    expect(chinese.exitClock, '退出棋钟');
    expect(chinese.resetClock, '重置棋钟');
    expect(chinese.clockPresetSemantics(1, 0), '1 分钟，每步不加时');
    expect(chinese.clockPresetSemantics(5, 1), '5 分钟，每步加 1 秒');
    expect(chinese.clockPresetSemantics(10, 3), '10 分钟，每步加 3 秒');
  });

  test('uses concise chess-style feedback in English mistake review', () {
    final S english = lookupS(const Locale('en'));

    expect(english.interactiveCorrection, 'Review mistakes');
    expect(english.correctionPrompt('d6xf4'), 'Find a better move than d6xf4.');
    expect(english.correctionAccepted, 'Good move!');
    expect(english.correctionTryAgain, 'You can do better. Try another move.');
    expect(english.correctionAnswer('b6'), 'Best move: b6');
    expect(english.correctionComplete, 'Mistake review complete');
    expect(english.noHumanMistakesToCorrect, 'No human mistakes to review.');
  });

  test('uses concise chess-style feedback in Chinese correction review', () {
    final S chinese = lookupS(const Locale('zh'));

    expect(chinese.interactiveCorrection, '互动纠错');
    expect(chinese.correctionPrompt('d6xf4'), '找出比 d6xf4 更好的着法。');
    expect(chinese.correctionAccepted, '好棋！');
    expect(chinese.correctionTryAgain, '还可以更好，请换一手。');
    expect(chinese.correctionAnswer('b6'), '最佳着法：b6');
    expect(chinese.correctionComplete, '互动纠错完成');
    expect(chinese.noHumanMistakesToCorrect, '没有可供纠错的真人失误。');
  });

  test('explains English opening randomness without implementation detail', () {
    final S english = lookupS(const Locale('en'));

    expect(
      english.openingRandomness_Detail,
      'Controls how widely the computer varies opening-book moves: 0% always '
      'picks the strongest, while 100% treats all candidates equally.',
    );
    expect(english.openingRandomness_Detail, isNot(contains('bias')));
  });

  test('explains Chinese opening randomness concisely', () {
    final S chinese = lookupS(const Locale('zh'));

    expect(
      chinese.openingRandomness_Detail,
      '控制电脑采用开局库着法时的变化程度：0% 始终选择最强着法，100% 则同等对待所有候选着法。',
    );
  });

  test('describes removal of the imported background-music file', () {
    final S english = lookupS(const Locale('en'));

    expect(english.clearBackgroundMusic, 'Remove background music file');
  });

  test('describes Chinese removal of the imported background-music file', () {
    final S chinese = lookupS(const Locale('zh'));

    expect(chinese.clearBackgroundMusic, '移除背景音乐文件');
  });

  test('uses complete English labels for analysis sharing actions', () {
    final S english = lookupS(const Locale('en'));

    expect(english.sharePgn, 'Share PGN');
    expect(english.shareFen, 'Share position as FEN');
  });

  test('uses complete Chinese labels for analysis sharing actions', () {
    final S chinese = lookupS(const Locale('zh'));

    expect(chinese.copyPgn, '复制 PGN');
    expect(chinese.sharePgn, '分享 PGN');
    expect(chinese.copyFen, '复制局面（FEN）');
    expect(chinese.shareFen, '分享局面（FEN）');
  });

  test(
    'distinguishes the English saved-games library from loading actions',
    () {
      final S english = lookupS(const Locale('en'));

      expect(english.loadGame, 'Load game');
      expect(english.savedGames, 'Saved games');
      expect(english.noSavedGames, 'No saved games yet.');
      expect(
        english.savedGamesExportFailed,
        'Could not export saved games. Try again.',
      );
      expect(
        english.savedGameDeleteFailed,
        'Could not delete this saved game. Try again.',
      );
      expect(
        english.savedGameRenameFailed,
        'Could not rename this saved game. Check the filename and try again.',
      );
      expect(
        english.savedGameOpenFailed,
        'Could not open this PGN file. Choose another file and try again.',
      );
      expect(
        english.gameArchiveImportFailed,
        'Could not import this game archive. Choose a valid ZIP file and try '
        'again.',
      );
      expect(
        english.gameImportFailed,
        'Could not import this game. Check the PGN and current rules, then try '
        'again.',
      );
    },
  );

  test(
    'distinguishes the Chinese saved-games library from loading actions',
    () {
      final S chinese = lookupS(const Locale('zh'));

      expect(chinese.saveGame, '保存棋局');
      expect(chinese.loadGame, '载入棋局');
      expect(chinese.savedGames, '已保存棋局');
      expect(chinese.noSavedGames, '暂无已保存棋局。');
      expect(chinese.savedGamesExportFailed, '无法导出已保存棋局，请重试。');
      expect(chinese.savedGameDeleteFailed, '无法删除这局棋，请重试。');
      expect(chinese.savedGameRenameFailed, '无法重命名这局棋。请检查文件名后重试。');
      expect(chinese.savedGameOpenFailed, '无法打开此 PGN 文件。请选择其他文件后重试。');
      expect(chinese.gameArchiveImportFailed, '无法导入棋局归档。请选择有效的 ZIP 文件后重试。');
      expect(chinese.gameImportFailed, '无法导入此棋局。请检查 PGN 和当前规则后重试。');
    },
  );

  test('names Chinese automatic game history without privacy jargon', () {
    final S chinese = lookupS(const Locale('zh'));

    expect(chinese.privateHistory, '对局历史');
    expect(chinese.privateHistoryDescription, '仅保存在本机，最多保留 100 条不重复的对局记录。');
  });

  test('separates computer-play and generative AI terminology', () {
    final S english = lookupS(const Locale('en'));
    final S chinese = lookupS(const Locale('zh'));

    expect(english.humanVsAi, 'Human vs computer');
    expect(english.aiVsAi, 'Computer vs computer');
    expect(english.skillLevel, 'Computer level');
    expect(english.humanAiRobotLevel(7), 'Computer level 7');
    expect(english.advancedAiSearch, 'Advanced engine search');
    expect(english.aiChatTitle, 'AI Assistant');
    expect(english.aiAnalysisTitle, 'AI Game Analysis');

    expect(chinese.humanVsAi, '人机对弈');
    expect(chinese.aiVsAi, '电脑自弈');
    expect(chinese.skillLevel, '电脑等级');
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

  test('uses clear Chinese take-back terminology', () {
    final S chinese = lookupS(const Locale('zh'));

    expect(chinese.takeBackRejected, '悔棋请求已被拒绝。');
    expect(chinese.takeBackAccepted, '悔棋请求已被接受。');
    expect(chinese.takeBackRequestSentToTheOpponent, '悔棋请求已发送。');
    expect(chinese.takeBackRequestWasRejectedOrFailed, '悔棋请求被拒绝或无法完成。');
    expect(chinese.cannotRequestATakeBackWhenItSNotYourTurn, '仅能在轮到您行棋时请求悔棋。');
    expect(chinese.opponentRequestsTakeBackAccept('2'), '对手请求悔棋 2 手，是否接受？');
    expect(chinese.remoteHistoryNavigationUnavailable, '联网对局只能针对自己最近的一手棋申请悔棋。');
  });

  test('uses action-specific English annotation clearing copy', () {
    final S english = lookupS(const Locale('en'));

    expect(english.confirmClear, 'Clear annotations?');
    expect(
      english.areYouSureYouWantToClearAllAnnotations,
      'All board annotations will be removed.',
    );
  });

  test('uses action-specific Chinese annotation clearing copy', () {
    final S chinese = lookupS(const Locale('zh'));

    expect(chinese.confirmClear, '清除棋盘标注？');
    expect(chinese.areYouSureYouWantToClearAllAnnotations, '所有棋盘标注都将被清除。');
  });

  test('explains the English diagnostic log clearing consequence', () {
    final S english = lookupS(const Locale('en'));

    expect(
      english.clearLogsConfirmation,
      'All diagnostic logs will be permanently deleted.',
    );
    expect(english.downloadFailed, 'Could not save logs. Try again.');
    expect(
      english.logStoragePermissionRequired,
      'Storage permission is required to save logs.',
    );
    expect(english.shareLogsFailed, 'Could not share logs. Try again.');
  });

  test('explains the Chinese diagnostic log clearing consequence', () {
    final S chinese = lookupS(const Locale('zh'));

    expect(chinese.clearLogsConfirmation, '所有诊断日志都将被永久删除。');
  });

  test('gives actionable Chinese diagnostic log export errors', () {
    final S chinese = lookupS(const Locale('zh'));

    expect(chinese.logStoragePermissionRequired, '保存日志需要存储权限。');
    expect(chinese.shareLogsFailed, '无法分享日志，请重试。');
  });

  test('explains the English prompt-template restore consequence', () {
    final S english = lookupS(const Locale('en'));

    expect(
      english.areYouSureYouWantToResetThePromptTemplatesToDefaultValues,
      'The prompt header and footer will be replaced with their defaults.',
    );
  });

  test('uses consistent Chinese prompt-template terms and consequences', () {
    final S chinese = lookupS(const Locale('zh'));

    expect(chinese.llmPromptTemplateHeader, '大模型提示词模板开头');
    expect(chinese.llmPromptTemplateFooter, '大模型提示词模板结尾');
    expect(
      chinese.areYouSureYouWantToResetThePromptTemplatesToDefaultValues,
      '提示词模板的开头和结尾将恢复为默认内容。',
    );
  });

  test('uses consequence-focused English game confirmations', () {
    final S english = lookupS(const Locale('en'));

    expect(english.confirmResignation, 'Resign this game?');
    expect(
      english.areYouSureYouWantToResignThisGame,
      'The game will end immediately.',
    );
    expect(english.confirmOfferDraw, 'Offer a draw?');
    expect(
      english.areYouSureYouWantToOfferADraw,
      'The game ends as a draw if your opponent accepts.',
    );
  });

  test('uses consequence-focused Chinese leave-game confirmation', () {
    final S chinese = lookupS(const Locale('zh'));

    expect(chinese.leaveCurrentGame, '离开当前对局？');
    expect(chinese.currentGameWillBeKept, '当前对局会保留。');
    expect(chinese.leave, '离开');
  });

  test('gives actionable English resignation failure feedback', () {
    final S english = lookupS(const Locale('en'));

    expect(
      english.failedToSendResignation,
      'Could not resign. Check your connection and try again.',
    );
  });

  test('gives actionable Chinese resignation failure feedback', () {
    final S chinese = lookupS(const Locale('zh'));

    expect(chinese.failedToSendResignation, '无法认输。请检查网络连接后重试。');
  });

  test('accurately describes the English statistics reset scope', () {
    final S english = lookupS(const Locale('en'));

    expect(
      english.thisWillResetAllGameStatistics,
      'All ratings and game results will be reset. This cannot be undone.',
    );
  });

  test('accurately describes the Chinese statistics reset scope', () {
    final S chinese = lookupS(const Locale('zh'));

    expect(chinese.thisWillResetAllGameStatistics, '所有等级分和对局结果都将重置。此操作无法撤销。');
  });

  test('accurately describes the English app-data reset scope', () {
    final S english = lookupS(const Locale('en'));

    expect(english.resetAppData, 'Reset app data');
    expect(
      english.restoreDefaultSettingsConfirmation,
      'This resets settings and ratings, and permanently deletes puzzle '
      'progress, game history, saved reviews, and custom themes. '
      'This cannot be undone.',
    );
  });

  test('accurately describes the Chinese app-data reset scope', () {
    final S chinese = lookupS(const Locale('zh'));

    expect(chinese.resetAppData, '重置应用数据');
    expect(
      chinese.restoreDefaultSettingsConfirmation,
      '这会重置设置和等级分，并永久删除谜题进度、对局历史、已保存的复盘和自定义主题。此操作无法撤销。',
    );
  });

  test('explains English recording deletion consequences', () {
    final S english = lookupS(const Locale('en'));

    expect(
      english.confirmDeleteSession,
      'This recording session will be permanently deleted.',
    );
    expect(
      english.confirmDeleteAllSessions,
      'All recording sessions will be permanently deleted.',
    );
  });

  test('explains Chinese recording deletion consequences', () {
    final S chinese = lookupS(const Locale('zh'));

    expect(chinese.confirmDeleteSession, '此录制会话将被永久删除。');
    expect(chinese.confirmDeleteAllSessions, '所有录制会话都将被永久删除。');
  });

  test('gives actionable English recording import feedback', () {
    final S english = lookupS(const Locale('en'));

    expect(
      english.importSessionFailed,
      'Could not import this recording session. Check the file format and '
      'try again.',
    );
  });

  test('gives actionable Chinese recording import feedback', () {
    final S chinese = lookupS(const Locale('zh'));

    expect(chinese.importSessionFailed, '无法导入此录制会话。请检查文件格式后重试。');
  });

  test('uses consistent English variation-deletion terminology', () {
    final S english = lookupS(const Locale('en'));

    expect(english.deleteCurrentBranch, 'Delete current variation');
    expect(
      english.deleteCurrentBranchConfirm,
      'Delete the current variation and all following moves?',
    );
    expect(
      english.deleteCurrentBranchWarning,
      'This variation contains the current position. You will return to its '
      'parent position.',
    );
    expect(english.deleteBranchTitle, 'Delete variation');
    expect(
      english.deleteBranchConfirmWithNotation('d6'),
      'Delete the variation “d6” and all following moves?',
    );
    expect(
      english.deleteBranchContainsPosition,
      english.deleteCurrentBranchWarning,
    );
    expect(english.deleteBranch, 'Delete variation');
    expect(english.branchDeleted, 'Variation deleted.');
    expect(english.branchMoves, 'Moves in this variation');
  });

  test('uses consistent Chinese variation-deletion terminology', () {
    final S chinese = lookupS(const Locale('zh'));

    expect(chinese.deleteCurrentBranch, '删除当前变化');
    expect(chinese.deleteCurrentBranchConfirm, '删除当前变化及其所有后续着法？');
    expect(chinese.deleteCurrentBranchWarning, '当前局面位于此变化中。删除后将返回上一局面。');
    expect(chinese.deleteBranchTitle, '删除变化');
    expect(chinese.deleteBranchConfirmWithNotation('d6'), '删除变化“d6”及其所有后续着法？');
    expect(
      chinese.deleteBranchContainsPosition,
      chinese.deleteCurrentBranchWarning,
    );
    expect(chinese.deleteBranch, '删除变化');
    expect(chinese.branchDeleted, '变化已删除。');
    expect(chinese.branchMoves, '此变化中的着法');
  });

  test('uses plain English variation-navigation terminology', () {
    final S english = lookupS(const Locale('en'));

    expect(english.jumpToMainLine, 'Go to main line');
    expect(english.jumpToVariation, 'Open variation');
    expect(english.jumpToThisVariation, 'Open this variation');
    expect(english.switchToThisBranch, 'Go to its first move');
    expect(english.previousBranchPoint, 'Previous variation point');
    expect(english.nextBranchPoint, 'Next variation point');
    expect(english.noBranchPointsFound, 'No variation points found.');
    expect(
      english.jumpedToPreviousBranchPoint,
      'Moved to the previous variation point.',
    );
    expect(
      english.jumpedToNextBranchPoint,
      'Moved to the next variation point.',
    );
    expect(english.noPreviousBranchPoint, 'No previous variation point.');
    expect(english.noNextBranchPoint, 'No next variation point.');
  });

  test('uses consistent Chinese variation-navigation terminology', () {
    final S chinese = lookupS(const Locale('zh'));

    expect(chinese.jumpToMainLine, '前往主线');
    expect(chinese.jumpToVariation, '打开变化');
    expect(chinese.jumpToThisVariation, '打开此变化');
    expect(chinese.switchToThisBranch, '前往此变化的第一手');
    expect(chinese.previousBranchPoint, '上一个变化点');
    expect(chinese.nextBranchPoint, '下一个变化点');
    expect(chinese.noBranchPointsFound, '未找到变化点。');
    expect(chinese.jumpedToPreviousBranchPoint, '已前往上一个变化点。');
    expect(chinese.jumpedToNextBranchPoint, '已前往下一个变化点。');
    expect(chinese.noPreviousBranchPoint, '没有上一个变化点。');
    expect(chinese.noNextBranchPoint, '没有下一个变化点。');
  });

  test('describes Chinese move-tree view controls precisely', () {
    final S chinese = lookupS(const Locale('zh'));

    expect(chinese.switchToActiveLineView, '切换到当前变化视图');
    expect(chinese.switchToFullTreeView, '切换到完整着法树视图');
    expect(chinese.reverseMoveOrder, '反转着法顺序');
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

  test('localizes board-recognition feedback in Chinese', () {
    final S chinese = lookupS(const Locale('zh'));

    expect(
      chinese.boardRecognitionFailedTryAgain,
      '棋盘识别失败。请使用棋盘完整可见且更清晰的图片重试。',
    );
    expect(
      chinese.boardRecognitionParameterName('pieceDetectionThreshold'),
      '棋子检测阈值',
    );
    expect(chinese.boardRecognitionApplyHint, '选择“应用到棋盘”以使用此局面。');
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
          stage: chinese.boardRecognitionDebugStageName(stage),
      },
      <String, String>{
        'originalImage': '原始图片',
        'resizedImage': '缩放后的图片',
        'enhancedImage': '增强对比度',
        'boardMaskRaw': '初始掩码',
        'boardMaskProcessed': '处理后的掩码',
        'boardDetection': '棋盘检测',
        'boardPointsDetection': '点位检测',
        'colorAnalysis': '颜色分析',
        'pieceDetection': '棋子检测',
        'finalResult': '最终结果',
      },
    );
    expect(
      chinese.boardRecognitionBoardDetectionHelp,
      contains('光线均匀、棋盘完整清晰可见'),
    );
    expect(chinese.boardRecognitionPointDetectionHelp, contains('标准莫里斯九子棋布局'));
    expect(chinese.boardRecognitionPointCount(18), '已检测到 24 个点位中的 18 个。');
    expect(
      chinese.boardRecognitionColorSampleStats('白棋', '210.1', '4.2'),
      '白棋：均值 210.1 · 标准差 4.2',
    );
    expect(
      chinese.boardRecognitionIdentifiedPieces(4, 3),
      '检测到的棋子：白棋 4 枚 · 黑棋 3 枚',
    );
    expect(chinese.boardRecognitionFinalLegend, '红色圆圈：黑棋 · 绿色圆圈：白棋');
  });

  test('localizes diagnostic privacy controls in Chinese', () {
    final S english = lookupS(const Locale('en'));
    final S chinese = lookupS(const Locale('zh'));

    expect(chinese.diagnostics, '诊断');
    expect(chinese.recordUserInteractions, '记录用户操作');
    expect(
      chinese.diagnosticSendConfirmation('Sanmill diagnostics'),
      '要将预览中显示的全部数据发送给 Sanmill diagnostics，用于诊断故障并核验应用的分发来源吗？不包含截图；发送失败不会自动重试。',
    );
    expect(chinese.diagnosticIncludeConfiguration, '包含用于复现问题的非敏感设置');
    expect(
      english.diagnosticIncludeConfiguration,
      'Include safe settings for reproduction',
    );
    expect(english.diagnosticExactPreview, 'Exact diagnostic bundle preview');
    expect(chinese.diagnosticExactPreview, '诊断包实际内容预览');
    expect(chinese.diagnosticIncludeLogs, '包含已脱敏日志');
    expect(
      chinese.diagnosticActionTrailDescription,
      contains('绝不记录输入文字、原始触摸、截图、音频或视频'),
    );
    expect(
      chinese.diagnosticPasteAndReproduceDescription,
      '校验校验和，备份当前的非敏感设置和棋局，然后还原报告中的状态。',
    );
    expect(chinese.unsafeLegacyRecording, contains('已禁用分享和回放；你只能删除它。'));
  });

  test('uses consistent English cat-fishing terminology', () {
    final S english = lookupS(const Locale('en'));
    final S chinese = lookupS(const Locale('zh'));

    expect(english.catFishingGameDeveloper, 'Cat fishing game (developer)');
    expect(
      english.catFishingDebugStats(4, '0.13'),
      'Fish caught: 4\nDifficulty: 0.13',
    );
    expect(chinese.catFishingGameDeveloper, '猫钓鱼（开发者）');
    expect(chinese.catFishingDebugStats(4, '0.13'), '已钓到：4\n难度：0.13');
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

  test('describes untimed English coordinate training directly', () {
    final S english = lookupS(const Locale('en'));

    expect(
      english.coordinateTrainingDescription,
      'For each coordinate, tap the matching point on the board. There is no '
      'time limit; finish whenever you like.',
    );
  });

  test('describes English puzzle streaks naturally', () {
    final S english = lookupS(const Locale('en'));

    expect(english.puzzleStreakDesc, 'Solve puzzles in a row without mistakes');
  });

  test('describes Chinese puzzle streaks precisely', () {
    final S chinese = lookupS(const Locale('zh'));

    expect(chinese.puzzleStreakDesc, '连续解对谜题，不能出错');
  });

  test('names the Chinese daily puzzle total explicitly', () {
    final S chinese = lookupS(const Locale('zh'));

    expect(chinese.dailyPuzzleTotalCompleted, '已完成的每日谜题');
  });

  test('distinguishes the current English puzzle rating label', () {
    final S english = lookupS(const Locale('en'));

    expect(english.puzzleStatsRating, 'Puzzle rating');
    expect(english.puzzleStatsCurrentRating, 'Current rating');
    expect(english.puzzleStatsDeviation, 'Rating uncertainty');
  });

  test('names Chinese puzzle rating uncertainty explicitly', () {
    final S chinese = lookupS(const Locale('zh'));

    expect(chinese.puzzleStatsDeviation, '等级分不确定性');
  });

  test('uses a direct English import-field hint', () {
    final S english = lookupS(const Locale('en'));

    expect(english.pasteAndImportGameHint, 'Enter or paste PGN');
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
      english.showHumanGameDatabaseStats,
      'Show human database move statistics during games',
    );
    expect(
      english.showHumanGameDatabaseStats_Detail,
      "After the computer plays a human database move, show its win, draw, "
      "and loss rates from that side's perspective, plus the number of "
      'recorded games.',
    );
    expect(
      english.humanDatabaseRulesUnsupported,
      'Human game database is unavailable for the current rules',
    );
    expect(
      english.humanDatabaseRulesUnsupportedHint,
      "Use rules compatible with Nine Men's Morris to see human move "
      'statistics.',
    );
    expect(
      english.humanGameDatabaseStatsUnavailable,
      'No human database move played yet',
    );
    expect(
      english.humanDatabaseNoPositionRecords,
      'No recorded human games for this position',
    );
    expect(
      english.humanDatabaseUnavailableHint,
      'Select Manage to review or replace the database file.',
    );
    expect(
      english.perfectDatabaseSuggestion,
      'Recommended move (no human game data)',
    );
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

  test('explains the Chinese PVS algorithm without search jargon', () {
    final S chinese = lookupS(const Locale('zh'));

    expect(
      chinese.whatIsPvs,
      'PVS（主要变化搜索）会先检查最有希望的一系列着法，再快速判断其他着法是否需要深入搜索。'
      '与基本的 Alpha-Beta 搜索相比，这通常更高效。',
    );
  });

  test('distinguishes an empty Chinese human database result', () {
    final S chinese = lookupS(const Locale('zh'));

    expect(chinese.humanDatabaseNoPositionRecords, '当前局面没有人类实战记录');
  });

  test('states Chinese human database game counts without ambiguity', () {
    final S chinese = lookupS(const Locale('zh'));

    expect(
      chinese.humanGameDatabaseStatsLine('d6', '50', '30', '20', 100),
      'd6  胜 50%  和 30%  负 20%  对局 100',
    );
  });

  test('uses standard FEN wording for puzzle validation errors', () {
    final S strings = lookupS(const Locale('en'));

    expect(
      strings.puzzleImportInvalidFen(3, 'Fork practice'),
      'Puzzle 3 ("Fork practice") has an invalid FEN',
    );
    expect(
      strings.puzzleValidationInvalidFen,
      'The puzzle has an invalid FEN. Check the position.',
    );
  });

  test('uses concise Chinese FEN wording for puzzle errors', () {
    final S chinese = lookupS(const Locale('zh'));

    expect(
      chinese.puzzleImportInvalidFen(3, '双重攻击练习'),
      '谜题 3（“双重攻击练习”）的 FEN 无效',
    );
    expect(chinese.puzzleValidationInvalidFen, '谜题的 FEN 无效，请检查局面。');
  });

  test('gives complete Chinese puzzle validation guidance', () {
    final S chinese = lookupS(const Locale('zh'));

    expect(
      chinese.puzzleRuleMismatchWarning('Nine Men\'s Morris', 'Custom'),
      "此谜题使用 Nine Men's Morris；当前规则为 Custom。",
    );
    expect(chinese.puzzleValidationAuthorRequired, '贡献前，请将您的姓名填写为作者。');
  });

  test('uses the established Chinese advantage-graph term', () {
    final S chinese = lookupS(const Locale('zh'));

    expect(chinese.showAdvantageGraph, '显示优势图');
    expect(chinese.advantageGraph, '优势图');
  });

  test('uses natural Chinese turn guidance for the removal step', () {
    final S chinese = lookupS(const Locale('zh'));

    expect(chinese.tipToMove(chinese.white), '轮到先手方行棋');
    expect(chinese.tipToRemove(chinese.white), '轮到先手方吃子');
  });

  test('describes Chinese removed-piece counts from the owning side', () {
    final S chinese = lookupS(const Locale('zh'));

    expect(chinese.piecesRemoved(chinese.white, 0), '先手方：被吃掉 0 枚棋子');
    expect(chinese.piecesRemoved(chinese.black, 2), '后手方：被吃掉 2 枚棋子');
  });

  test('names the Chinese Analysis clear action by its actual scope', () {
    final S chinese = lookupS(const Locale('zh'));

    expect(chinese.clearAnalysisMoves, '清空着法');
    expect(chinese.analysisMovesCleared, '已清空分析着法。');
  });

  test('lists Chinese computer move sources in lookup order', () {
    final S chinese = lookupS(const Locale('zh'));

    expect(chinese.aiKnowledgeSources_Detail, '开局库、人类对局数据库、完美数据库和陷阱库。');
  });

  test('distinguishes local and host addresses in Chinese LAN setup', () {
    final S chinese = lookupS(const Locale('zh'));

    expect(chinese.lanLocalAddress, '本机地址');
    expect(chinese.serverIp, '主机地址');
  });

  test('identifies the host-controlled side in Chinese remote setup', () {
    final S chinese = lookupS(const Locale('zh'));

    expect(chinese.remotePlayAs(chinese.white), '主机控制先手方');
    expect(chinese.remotePlayAs(chinese.black), '主机控制后手方');
  });

  test('distinguishes Chinese board previews from a small main board', () {
    final S chinese = lookupS(const Locale('zh'));

    expect(chinese.boardPreviews, '棋盘预览');
    expect(chinese.smallBoard, '小棋盘');
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
