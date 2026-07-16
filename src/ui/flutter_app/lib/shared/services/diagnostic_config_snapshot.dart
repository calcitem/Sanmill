// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import '../../appearance_settings/models/color_settings.dart';
import '../../appearance_settings/models/display_settings.dart';
import '../../general_settings/models/general_settings.dart';
import '../../rule_settings/models/rule_settings.dart';
import '../database/database.dart';

/// How one settings field may participate in diagnostics.
enum DiagnosticSettingClassification {
  /// Included in reports and safe to apply during reproduction.
  reportAndApply,

  /// Included only as presence/status metadata and never applied.
  reportOnly,

  /// Never copied into a diagnostic artifact.
  sensitiveLocal,
}

/// Explicit settings allowlist used by reports, checkpoints and imports.
///
/// Tests compare every generated JSON key with these classifications. A new
/// setting therefore fails review until it is explicitly placed in one group.
class DiagnosticConfigSchema {
  const DiagnosticConfigSchema._();

  static const Set<String> generalReportAndApply = <String>{
    'ToneEnabled',
    'KeepMuteWhenTakingBack',
    'ScreenReaderSupport',
    'AiMovesFirst',
    'AiIsLazy',
    'SkillLevel',
    'MoveTime',
    'HumanMoveTime',
    'IsAutoRestart',
    'IsAutoChangeFirstMove',
    'ResignIfMostLose',
    'ShufflingEnabled',
    'LearnEndgame',
    'OpeningBook',
    'Algorithm',
    'SearchAlgorithm',
    'DrawOnHumanExperience',
    'ConsiderMobility',
    'FocusOnBlockingPaths',
    'UsePerfectDatabase',
    'VibrationEnabled',
    'SoundTheme',
    'UseOpeningBook',
    'TrapAwareness',
    'ShowHumanDatabaseStats',
    'ShowOpeningInfo',
    'PreferFavoredOpenings',
    'OpeningRandomness',
    'UseLazySmp',
    'EngineThreads',
    'PatchAvoidTraps',
    'PatchMakeTraps',
    'OfflineBoardTimeSeconds',
    'OfflineBoardIncrementSeconds',
    'OfflineBoardFlipAfterMove',
  };

  static const Set<String> generalReportOnly = <String>{
    'LlmProvider',
    'LlmModel',
    'LlmTemperature',
    'AiChatEnabled',
    'BackgroundMusicEnabled',
    'HumanDatabaseEnabled',
  };

  static const Set<String> generalSensitiveLocal = <String>{
    'IsPrivacyPolicyAccepted',
    'DeveloperMode',
    'ExperimentsEnabled',
    'UsesHiveDB',
    'FirstRun',
    'GameScreenRecorderSupport',
    'GameScreenRecorderDuration',
    'GameScreenRecorderPixelRatio',
    'ShowTutorial',
    'RemindedOpponentMayFly',
    'LlmPromptHeader',
    'LlmPromptFooter',
    'LlmApiKey',
    'LlmBaseUrl',
    'BackgroundMusicFilePath',
    'LastPgnSaveDirectory',
    'ExperienceRecordingEnabled',
    'DiagnosticActionTrailEnabled',
    'HumanDatabaseFilePath',
    'UseNativeMillSession',
  };

  static const Set<String> ruleReportAndApply = <String>{
    'PiecesCount',
    'FlyPieceCount',
    'PiecesAtLeastCount',
    'HasDiagonalLines',
    'HasBannedLocations',
    'MayMoveInPlacingPhase',
    'IsDefenderMoveFirst',
    'MayRemoveMultiple',
    'MayRemoveFromMillsAlways',
    'MayOnlyRemoveUnplacedPieceInPlacingPhase',
    'IsWhiteLoseButNotDrawWhenBoardFull',
    'BoardFullAction',
    'IsLoseButNotChangeSideWhenNoWay',
    'StalemateAction',
    'MayFly',
    'NMoveRule',
    'EndgameNMoveRule',
    'ThreefoldRepetitionRule',
    'MillFormationActionInPlacingPhase',
    'RestrictRepeatedMillsFormation',
    'OneTimeUseMill',
    'EnableCustodianCapture',
    'CustodianCaptureOnSquareEdges',
    'CustodianCaptureOnCrossLines',
    'CustodianCaptureOnDiagonalLines',
    'CustodianCaptureInPlacingPhase',
    'CustodianCaptureInMovingPhase',
    'CustodianCaptureOnlyWhenOwnPiecesLeq3',
    'EnableInterventionCapture',
    'InterventionCaptureOnSquareEdges',
    'InterventionCaptureOnCrossLines',
    'InterventionCaptureOnDiagonalLines',
    'InterventionCaptureInPlacingPhase',
    'InterventionCaptureInMovingPhase',
    'InterventionCaptureOnlyWhenOwnPiecesLeq3',
    'EnableLeapCapture',
    'LeapCaptureOnSquareEdges',
    'LeapCaptureOnCrossLines',
    'LeapCaptureOnDiagonalLines',
    'LeapCaptureInPlacingPhase',
    'LeapCaptureInMovingPhase',
    'LeapCaptureOnlyWhenOwnPiecesLeq3',
    'StopPlacingWhenTwoEmptySquares',
  };

  static const Set<String> displayReportAndApply = <String>{
    'LanguageCode',
    'StandardNotationEnabled',
    'IsPieceCountInHandShown',
    'IsNotationsShown',
    'IsHistoryNavigationToolbarShown',
    'BoardBorderLineWidth',
    'BoardInnerLineWidth',
    'PointStyle',
    'PointWidth',
    'PieceWidth',
    'FontSize',
    'BoardTop',
    'AnimationDuration',
    'Locale',
    'PointPaintingStyle',
    'FontScale',
    'IsUnplacedAndRemovedPiecesShown',
    'IsFullScreen',
    'AiResponseDelayTime',
    'IsPositionalAdvantageIndicatorShown',
    'BackgroundImagePath',
    'IsNumbersOnPiecesShown',
    'IsAnalysisToolbarShown',
    'WhitePieceImagePath',
    'BlackPieceImagePath',
    'MarkedPieceImagePath',
    'BoardImagePath',
    'VignetteEffectEnabled',
    'PlaceEffectAnimation',
    'RemoveEffectAnimation',
    'IsToolbarAtBottom',
    'BoardCornerRadius',
    'IsAdvantageGraphShown',
    'IsAnnotationToolbarShown',
    'MovesViewLayout',
    'SwipeToRevealTheDrawer',
    'IsScreenshotGameInfoShown',
    'BoardInnerRingSize',
    'BoardShadowEnabled',
    'IsCapturablePiecesHighlightShown',
    'IsPiecePickUpAnimationEnabled',
    'ShowBranchTree',
    'ThemeMode',
    'AnalysisSmallBoard',
    'AnalysisInlineNotation',
    'AnalysisShowEngineLines',
    'AnalysisEngineLineCount',
    'AnalysisEngineSearchTimeMs',
    'AnalysisShowMoveAnnotations',
    'AnalysisShowMoveComments',
    'AnalysisShowBestMoveArrow',
    'AnalysisShowEvaluationGauge',
    'AnalysisShowAllBoardResults',
  };

  static const Set<String> displaySensitiveLocal = <String>{
    'CustomBackgroundImagePath',
    'CustomBoardImagePath',
    'CustomWhitePieceImagePath',
    'CustomBlackPieceImagePath',
  };

  static const Set<String> colorReportAndApply = <String>{
    'BoardLineColor',
    'DarkBackgroundColor',
    'BoardBackgroundColor',
    'WhitePieceColor',
    'BlackPieceColor',
    'PieceHighlightColor',
    'MessageColor',
    'DrawerColor',
    'DrawerBackgroundColor',
    'DrawerTextColor',
    'DrawerHighlightItemColor',
    'MainToolbarBackgroundColor',
    'MainToolbarIconColor',
    'NavigationToolbarBackgroundColor',
    'NavigationToolbarIconColor',
    'AnalysisToolbarBackgroundColor',
    'AnalysisToolbarIconColor',
    'AnnotationToolbarBackgroundColor',
    'AnnotationToolbarIconColor',
    'CapturablePieceHighlightColor',
  };

  static Set<String> get classifiedGeneralKeys => <String>{
    ...generalReportAndApply,
    ...generalReportOnly,
    ...generalSensitiveLocal,
  };

  static Set<String> get classifiedDisplayKeys => <String>{
    ...displayReportAndApply,
    ...displaySensitiveLocal,
  };

  static Set<String> get classifiedColorKeys => <String>{
    ...colorReportAndApply,
  };
}

/// Captures and applies only fields reviewed by [DiagnosticConfigSchema].
class DiagnosticConfigSnapshot {
  const DiagnosticConfigSnapshot._();

  static Map<String, dynamic> capture() {
    final Map<String, dynamic> general = DB().generalSettings.toJson();
    final Map<String, dynamic> display = DB().displaySettings.toJson();
    final Map<String, dynamic> reportGeneral = _select(
      general,
      DiagnosticConfigSchema.generalReportAndApply,
    );
    final Map<String, dynamic> reportDisplay = _select(
      display,
      DiagnosticConfigSchema.displayReportAndApply,
    );
    for (final String pathField in const <String>{
      'BackgroundImagePath',
      'WhitePieceImagePath',
      'BlackPieceImagePath',
      'MarkedPieceImagePath',
      'BoardImagePath',
    }) {
      final Object? value = reportDisplay[pathField];
      if (value is String && !_isBundledResource(value)) {
        reportDisplay.remove(pathField);
      }
    }

    final Map<String, dynamic> informational = _select(
      general,
      DiagnosticConfigSchema.generalReportOnly,
    );
    informational['HasCustomBackgroundImage'] =
        display['CustomBackgroundImagePath'] is String &&
        (display['CustomBackgroundImagePath'] as String).isNotEmpty;
    informational['HasCustomBoardImage'] =
        display['CustomBoardImagePath'] is String &&
        (display['CustomBoardImagePath'] as String).isNotEmpty;
    informational['HasCustomPieceImages'] =
        const <String>{
          'CustomWhitePieceImagePath',
          'CustomBlackPieceImagePath',
        }.any(
          (String key) =>
              display[key] is String && (display[key] as String).isNotEmpty,
        );
    informational['HasBackgroundMusicFile'] =
        general['BackgroundMusicFilePath'] is String &&
        (general['BackgroundMusicFilePath'] as String).isNotEmpty;
    informational['HasHumanDatabaseFile'] =
        general['HumanDatabaseFilePath'] is String &&
        (general['HumanDatabaseFilePath'] as String).isNotEmpty;

    return <String, dynamic>{
      'generalSettings': reportGeneral,
      'ruleSettings': _select(
        DB().ruleSettings.toJson(),
        DiagnosticConfigSchema.ruleReportAndApply,
      ),
      'displaySettings': reportDisplay,
      'colorSettings': _select(
        DB().colorSettings.toJson(),
        DiagnosticConfigSchema.colorReportAndApply,
      ),
      'informationalOnly': informational,
    };
  }

  /// Strictly validates an untrusted snapshot without changing local state.
  static Map<String, dynamic> validate(Map<String, dynamic> snapshot) {
    const Set<String> categories = <String>{
      'generalSettings',
      'ruleSettings',
      'displaySettings',
      'colorSettings',
      'informationalOnly',
    };
    final Set<String> unknown = snapshot.keys.toSet().difference(categories);
    if (unknown.isNotEmpty) {
      throw FormatException(
        'Unknown diagnostic config categories: ${unknown.toList()..sort()}',
      );
    }
    final Map<String, dynamic> general = _validatedCategory(
      snapshot,
      'generalSettings',
      DiagnosticConfigSchema.generalReportAndApply,
    );
    final Map<String, dynamic> rules = _validatedCategory(
      snapshot,
      'ruleSettings',
      DiagnosticConfigSchema.ruleReportAndApply,
    );
    final Map<String, dynamic> display = _validatedCategory(
      snapshot,
      'displaySettings',
      DiagnosticConfigSchema.displayReportAndApply,
    );
    final Map<String, dynamic> colors = _category(snapshot, 'colorSettings');
    final Map<String, dynamic> informational = _category(
      snapshot,
      'informationalOnly',
    );
    _validateScalarValues(general, 'generalSettings');
    _validateScalarValues(rules, 'ruleSettings');
    _validateScalarValues(display, 'displaySettings');
    _validateScalarValues(colors, 'colorSettings');
    _validateRange(general, 'EngineThreads', 1, 256);
    _validateRange(general, 'SkillLevel', 0, 30);
    _validateRange(general, 'OpeningRandomness', 0, 100);
    _validateRange(rules, 'PiecesCount', 3, 24);
    _validateRange(rules, 'FlyPieceCount', 0, 24);
    _validateRange(display, 'AnalysisEngineLineCount', 1, 32);
    _validateRange(display, 'AnalysisEngineSearchTimeMs', 1, 3600000);

    GeneralSettings.fromJson(<String, dynamic>{
      ...const GeneralSettings().toJson(),
      ...general,
    });
    RuleSettings.fromJson(<String, dynamic>{
      ...const RuleSettings().toJson(),
      ...rules,
    });
    DisplaySettings.fromJson(<String, dynamic>{
      ...const DisplaySettings().toJson(),
      ...display,
    });
    for (final String resourceKey in const <String>{
      'BackgroundImagePath',
      'WhitePieceImagePath',
      'BlackPieceImagePath',
      'MarkedPieceImagePath',
      'BoardImagePath',
    }) {
      final Object? value = display[resourceKey];
      if (value is String && !_isBundledResource(value)) {
        throw FormatException('$resourceKey is not a bundled resource ID.');
      }
    }
    final Set<String> unknownColors = colors.keys.toSet().difference(
      DiagnosticConfigSchema.colorReportAndApply,
    );
    if (unknownColors.isNotEmpty) {
      throw FormatException(
        'Unknown color settings: ${unknownColors.toList()..sort()}',
      );
    }
    ColorSettings.fromJson(<String, dynamic>{
      ...const ColorSettings().toJson(),
      ...colors,
    });

    const Set<String> informationalKeys = <String>{
      ...DiagnosticConfigSchema.generalReportOnly,
      'HasCustomBackgroundImage',
      'HasCustomBoardImage',
      'HasCustomPieceImages',
      'HasBackgroundMusicFile',
      'HasHumanDatabaseFile',
    };
    final Set<String> unknownInformational = informational.keys
        .toSet()
        .difference(informationalKeys);
    if (unknownInformational.isNotEmpty) {
      throw FormatException(
        'Unknown informational settings: '
        '${unknownInformational.toList()..sort()}',
      );
    }
    for (final MapEntry<String, dynamic> entry in informational.entries) {
      final Object? value = entry.value;
      if (value is! bool &&
          value is! num &&
          value is! String &&
          value != null) {
        throw FormatException(
          'Informational setting ${entry.key} is not a JSON scalar.',
        );
      }
      if (value is String && value.length > 160) {
        throw FormatException(
          'Informational setting ${entry.key} is too long.',
        );
      }
    }

    return <String, dynamic>{
      'generalSettings': general,
      'ruleSettings': rules,
      'displaySettings': display,
      'colorSettings': colors,
      'informationalOnly': informational,
    };
  }

  /// Persistently overlays a validated diagnostic snapshot on local settings.
  /// Sensitive, report-only and external-resource settings are never changed.
  static void apply(Map<String, dynamic> snapshot) {
    final Map<String, dynamic> validated = validate(snapshot);

    final Map<String, dynamic> general = _validatedCategory(
      validated,
      'generalSettings',
      DiagnosticConfigSchema.generalReportAndApply,
    );
    final Map<String, dynamic> rules = _validatedCategory(
      validated,
      'ruleSettings',
      DiagnosticConfigSchema.ruleReportAndApply,
    );
    final Map<String, dynamic> display = _validatedCategory(
      validated,
      'displaySettings',
      DiagnosticConfigSchema.displayReportAndApply,
    );
    final Map<String, dynamic> colors = _category(validated, 'colorSettings');

    if (general.isNotEmpty) {
      DB().generalSettings = GeneralSettings.fromJson(<String, dynamic>{
        ...DB().generalSettings.toJson(),
        ...general,
      });
    }
    if (rules.isNotEmpty) {
      DB().ruleSettings = RuleSettings.fromJson(<String, dynamic>{
        ...DB().ruleSettings.toJson(),
        ...rules,
      });
    }
    if (display.isNotEmpty) {
      DB().displaySettings = DisplaySettings.fromJson(<String, dynamic>{
        ...DB().displaySettings.toJson(),
        ...display,
      });
    }
    if (colors.isNotEmpty) {
      DB().colorSettings = ColorSettings.fromJson(<String, dynamic>{
        ...DB().colorSettings.toJson(),
        ...colors,
      });
    }
  }

  static Map<String, dynamic> _select(
    Map<String, dynamic> source,
    Set<String> keys,
  ) {
    return <String, dynamic>{
      for (final String key in keys)
        if (source.containsKey(key)) key: source[key],
    };
  }

  static Map<String, dynamic> _validatedCategory(
    Map<String, dynamic> snapshot,
    String category,
    Set<String> allowed,
  ) {
    final Map<String, dynamic> values = _category(snapshot, category);
    final Set<String> unknown = values.keys.toSet().difference(allowed);
    if (unknown.isNotEmpty) {
      throw FormatException(
        'Unsafe or unknown $category fields: ${unknown.toList()..sort()}',
      );
    }
    return values;
  }

  static Map<String, dynamic> _category(
    Map<String, dynamic> snapshot,
    String key,
  ) {
    final Object? value = snapshot[key];
    if (value == null) {
      return <String, dynamic>{};
    }
    if (value is! Map<String, dynamic>) {
      throw FormatException('$key must be a JSON object.');
    }
    return Map<String, dynamic>.from(value);
  }

  static bool _isBundledResource(String value) {
    return value.isEmpty || value.startsWith('assets/');
  }

  static void _validateScalarValues(
    Map<String, dynamic> values,
    String category,
  ) {
    for (final MapEntry<String, dynamic> entry in values.entries) {
      final Object? value = entry.value;
      if (value is num && (!value.isFinite || value.abs() > 10000000)) {
        throw FormatException('$category.${entry.key} is out of range.');
      }
      if (value is String && value.length > 512) {
        throw FormatException('$category.${entry.key} is too long.');
      }
      if (value != null &&
          value is! bool &&
          value is! num &&
          value is! String) {
        throw FormatException('$category.${entry.key} is not a JSON scalar.');
      }
    }
  }

  static void _validateRange(
    Map<String, dynamic> values,
    String key,
    num minimum,
    num maximum,
  ) {
    final Object? value = values[key];
    if (value != null &&
        (value is! num || value < minimum || value > maximum)) {
      throw FormatException('$key must be between $minimum and $maximum.');
    }
  }
}
