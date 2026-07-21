// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// play_area.dart

import 'dart:async';
import 'dart:math' as math;

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:native_screenshot_widget/native_screenshot_widget.dart';
import 'package:share_plus/share_plus.dart';

import '../../appearance_settings/models/display_settings.dart';
import '../../experience_recording/models/recording_models.dart';
import '../../experience_recording/services/diagnostic_reproduction_service.dart';
import '../../experience_recording/services/recording_service.dart';
import '../../game_platform/game_session.dart'
    show GameAction, GameSession, PlayerSeat;
import '../../game_shell/game_session_scope.dart';
import '../../games/mill/mill_action_codec.dart';
import '../../games/mill/mill_board_coordinate_maps.dart';
import '../../games/mill/mill_board_transform_actions.dart';
import '../../games/mill/mill_human_database_provider.dart';
import '../../games/mill/mill_opening_book_provider.dart';
import '../../games/mill/mill_variant_localization.dart';
import '../../games/mill/native_mill_ai_turn_controller.dart';
import '../../games/mill/native_mill_game_session.dart';
import '../../games/mill/native_mill_rules_port.dart';
import '../../games/mill/opening_explorer/opening_explorer_page.dart';
import '../../general_settings/models/general_settings.dart';
import '../../general_settings/widgets/general_settings_page.dart';
import '../../generated/intl/l10n.dart';
import '../../puzzle/models/rule_variant.dart';
import '../../shared/config/ai_compliance_config.dart';
import '../../shared/config/constants.dart';
import '../../shared/database/database.dart';
import '../../shared/services/accessibility_status.dart';
import '../../shared/services/screenshot_service.dart';
import '../../shared/themes/app_styles.dart';
import '../../shared/themes/app_theme.dart';
import '../../shared/utils/helpers/color_helpers/color_helper.dart';
import '../../shared/utils/screen_insets.dart';
import '../../shared/widgets/lichess_action_sheet.dart';
import '../../shared/widgets/lichess_bottom_bar.dart';
import '../../shared/widgets/lichess_list_section.dart';
import '../../shared/widgets/move_feedback_reasons.dart';
import '../../shared/widgets/quality_annotation_sheet.dart';
import '../../shared/widgets/snackbars/scaffold_messenger.dart';
import '../../statistics/services/stats_service.dart';
import '../services/analysis/analysis_service.dart';
import '../services/analysis/move_feedback.dart';
import '../services/analysis/move_feedback_analysis_controller.dart';
import '../services/analysis_mode.dart';
import '../services/import_export/pgn.dart';
import '../services/mill.dart';
import '../services/offline_board_clock.dart';
import '../services/offline_board_history.dart';
import '../services/painters/advantage_graph_painter.dart';
import '../services/transform/transform.dart';
import 'ai_chat_dialog.dart';
import 'board_marker_guide_sheet.dart';
import 'game_page.dart';
import 'mini_board.dart';
import 'modals/game_options_modal.dart';
import 'modals/offline_board_options_sheet.dart';
import 'moves_list_page.dart';
import 'toolbars/game_toolbar.dart';

String _evaluationGaugePositionLabel(
  S strings,
  EvaluationGaugePosition position,
) {
  return switch (position) {
    EvaluationGaugePosition.left => strings.evaluationGaugePositionLeft,
    EvaluationGaugePosition.top => strings.evaluationGaugePositionTop,
    EvaluationGaugePosition.right => strings.evaluationGaugePositionRight,
    EvaluationGaugePosition.bottom => strings.evaluationGaugePositionBottom,
  };
}

IconData _evaluationGaugePositionIcon(EvaluationGaugePosition position) {
  return switch (position) {
    EvaluationGaugePosition.left => Icons.align_horizontal_left,
    EvaluationGaugePosition.top => Icons.align_vertical_top,
    EvaluationGaugePosition.right => Icons.align_horizontal_right,
    EvaluationGaugePosition.bottom => Icons.align_vertical_bottom,
  };
}

Future<void> _showEvaluationGaugePositionSheet(
  BuildContext context, {
  required S strings,
}) async {
  final EvaluationGaugePosition selected = AnalysisMode.evaluationGaugePosition;
  await showLichessActionSheet<void>(
    context: context,
    sheetKey: const Key('play_area_analysis_evaluation_gauge_position_sheet'),
    title: Text(strings.evaluationGaugePosition),
    actions: <LichessActionSheetAction>[
      for (final EvaluationGaugePosition position
          in EvaluationGaugePosition.values)
        LichessActionSheetAction(
          key: Key(
            'play_area_analysis_evaluation_gauge_position_${position.name}',
          ),
          leading: Icon(_evaluationGaugePositionIcon(position)),
          trailing: selected == position
              ? const Icon(Icons.check_rounded)
              : null,
          makeLabel: (BuildContext context) =>
              Text(_evaluationGaugePositionLabel(strings, position)),
          onPressed: () {
            RecordingService().recordEvent(
              RecordingEventType.toolbarAction,
              <String, dynamic>{
                'toolbar': 'analysisSettings',
                'action': 'setEvaluationGaugePosition',
                'position': position.name,
              },
            );
            AnalysisMode.setEvaluationGaugePosition(position, persist: true);
          },
        ),
    ],
  );
}

Future<void> showAnalysisSettingsSheet(
  BuildContext context, {
  required S strings,
}) {
  assert(
    GameController().gameInstance.gameMode == GameMode.analysis,
    'Analysis settings are analysis-mode only.',
  );
  return showDialog<void>(
    context: context,
    builder: (BuildContext dialogContext) {
      final ThemeData theme = Theme.of(dialogContext);
      final ColorScheme colorScheme = theme.colorScheme;
      final bool useFullScreenPage =
          MediaQuery.sizeOf(dialogContext).width < 600;
      final Widget content = ValueListenableBuilder<bool>(
        valueListenable: AnalysisMode.stateNotifier,
        builder: (BuildContext context, _, Widget? child) {
          final int currentEngineThreads = DB().generalSettings.engineThreads;
          final bool canUseAnalysisThreads = AnalysisMode.engineLineCount == 1;
          return SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    useFullScreenPage ? 4 : 16,
                    8,
                    8,
                    8,
                  ),
                  child: Row(
                    children: <Widget>[
                      if (useFullScreenPage)
                        IconButton(
                          key: const Key('play_area_analysis_settings_back'),
                          tooltip: strings.back,
                          onPressed: () => Navigator.of(dialogContext).pop(),
                          icon: Icon(
                            theme.platform == TargetPlatform.iOS
                                ? CupertinoIcons.back
                                : Icons.arrow_back,
                          ),
                        ),
                      Expanded(
                        child: Text(
                          strings.analysisSettingsTitle,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0,
                          ),
                        ),
                      ),
                      if (!useFullScreenPage &&
                          theme.platform == TargetPlatform.iOS)
                        CupertinoButton(
                          key: const Key('play_area_analysis_settings_cancel'),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 6,
                          ),
                          onPressed: () => Navigator.of(dialogContext).pop(),
                          child: Text(strings.cancel),
                        )
                      else if (!useFullScreenPage)
                        IconButton(
                          key: const Key('play_area_analysis_settings_close'),
                          tooltip: strings.close,
                          onPressed: () => Navigator.of(dialogContext).pop(),
                          icon: const Icon(Icons.close),
                        ),
                    ],
                  ),
                ),
                LichessListSection(
                  header: Text(strings.analysisSettingsLayout),
                  cardKey: const Key('play_area_analysis_settings_layout_card'),
                  children: <Widget>[
                    SwitchListTile.adaptive(
                      key: const Key('play_area_analysis_settings_small_board'),
                      secondary: const Icon(Icons.fit_screen_outlined),
                      title: Text(strings.smallBoard),
                      value: AnalysisMode.smallBoard,
                      onChanged: (bool value) {
                        RecordingService().recordEvent(
                          RecordingEventType.toolbarAction,
                          <String, dynamic>{
                            'toolbar': 'analysisSettings',
                            'action': 'setSmallBoard',
                            'enabled': value,
                          },
                        );
                        AnalysisMode.setSmallBoard(value, persist: true);
                      },
                    ),
                    SwitchListTile.adaptive(
                      key: const Key(
                        'play_area_analysis_settings_inline_notation',
                      ),
                      secondary: const Icon(Icons.short_text_outlined),
                      title: Text(strings.analysisInlineNotation),
                      value: AnalysisMode.inlineNotation,
                      onChanged: (bool value) {
                        RecordingService().recordEvent(
                          RecordingEventType.toolbarAction,
                          <String, dynamic>{
                            'toolbar': 'analysisSettings',
                            'action': 'setInlineNotation',
                            'enabled': value,
                          },
                        );
                        AnalysisMode.setInlineNotation(value, persist: true);
                      },
                    ),
                    SwitchListTile.adaptive(
                      key: const Key(
                        'play_area_analysis_settings_move_mini_boards',
                      ),
                      secondary: const Icon(Icons.grid_view_rounded),
                      title: Text(strings.analysisShowMoveMiniBoards),
                      value: AnalysisMode.showMoveMiniBoards,
                      onChanged: (bool value) {
                        RecordingService().recordEvent(
                          RecordingEventType.toolbarAction,
                          <String, dynamic>{
                            'toolbar': 'analysisSettings',
                            'action': 'setMoveMiniBoards',
                            'visible': value,
                          },
                        );
                        AnalysisMode.setShowMoveMiniBoards(
                          value,
                          persist: true,
                        );
                      },
                    ),
                    SwitchListTile.adaptive(
                      key: const Key(
                        'play_area_analysis_settings_evaluation_gauge',
                      ),
                      secondary: const Icon(Icons.align_horizontal_left),
                      title: Text(strings.showEvaluationGauge),
                      value: AnalysisMode.showEvaluationGauge,
                      onChanged: (bool value) {
                        RecordingService().recordEvent(
                          RecordingEventType.toolbarAction,
                          <String, dynamic>{
                            'toolbar': 'analysisSettings',
                            'action': 'setEvaluationGauge',
                            'visible': value,
                          },
                        );
                        AnalysisMode.setShowEvaluationGauge(
                          value,
                          persist: true,
                        );
                      },
                    ),
                    ListTile(
                      key: const Key(
                        'play_area_analysis_settings_evaluation_gauge_position',
                      ),
                      enabled: AnalysisMode.showEvaluationGauge,
                      leading: Icon(
                        _evaluationGaugePositionIcon(
                          AnalysisMode.evaluationGaugePosition,
                        ),
                      ),
                      title: Text(strings.evaluationGaugePosition),
                      subtitle: Text(
                        _evaluationGaugePositionLabel(
                          strings,
                          AnalysisMode.evaluationGaugePosition,
                        ),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: AnalysisMode.showEvaluationGauge
                          ? () => unawaited(
                              _showEvaluationGaugePositionSheet(
                                context,
                                strings: strings,
                              ),
                            )
                          : null,
                    ),
                    SwitchListTile.adaptive(
                      key: const Key(
                        'play_area_analysis_settings_move_annotations',
                      ),
                      secondary: const Icon(Icons.rate_review_outlined),
                      title: Text(strings.analysisShowMoveAnnotations),
                      value: AnalysisMode.showMoveAnnotations,
                      onChanged: (bool value) {
                        RecordingService().recordEvent(
                          RecordingEventType.toolbarAction,
                          <String, dynamic>{
                            'toolbar': 'analysisSettings',
                            'action': 'setMoveAnnotations',
                            'visible': value,
                          },
                        );
                        AnalysisMode.setShowMoveAnnotations(
                          value,
                          persist: true,
                        );
                      },
                    ),
                    SwitchListTile.adaptive(
                      key: const Key(
                        'play_area_analysis_settings_move_comments',
                      ),
                      secondary: const Icon(Icons.notes_outlined),
                      title: Text(strings.analysisShowMoveComments),
                      value: AnalysisMode.showMoveComments,
                      onChanged: (bool value) {
                        RecordingService().recordEvent(
                          RecordingEventType.toolbarAction,
                          <String, dynamic>{
                            'toolbar': 'analysisSettings',
                            'action': 'setMoveComments',
                            'visible': value,
                          },
                        );
                        AnalysisMode.setShowMoveComments(value, persist: true);
                      },
                    ),
                  ],
                ),
                LichessListSection(
                  header: Text(strings.analysisSettingsKnowledgeSources),
                  cardKey: const Key(
                    'play_area_analysis_settings_knowledge_card',
                  ),
                  children: <Widget>[
                    ListTile(
                      key: const Key(
                        'play_area_analysis_settings_opening_explorer_sources',
                      ),
                      leading: const Icon(Icons.travel_explore_outlined),
                      title: Text(strings.aiKnowledgeSources),
                      subtitle: Text(strings.aiKnowledgeSources_Detail),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () async {
                        RecordingService().recordEvent(
                          RecordingEventType.toolbarAction,
                          <String, dynamic>{
                            'toolbar': 'analysisSettings',
                            'action': 'openExplorerSources',
                          },
                        );
                        final NavigatorState navigator = Navigator.of(context);
                        Navigator.of(dialogContext).pop();
                        await navigator.push<void>(
                          GeneralSettingsPage.aiKnowledgeSourcesRoute(),
                        );
                        AnalysisMode.refresh();
                      },
                    ),
                    if (isRuleSupportingPerfectDatabase())
                      SwitchListTile.adaptive(
                        key: const Key(
                          'play_area_analysis_settings_perfect_database',
                        ),
                        secondary: const Icon(Icons.storage_outlined),
                        title: Text(strings.usePerfectDatabase),
                        value: DB().generalSettings.usePerfectDatabase,
                        onChanged: (bool value) {
                          RecordingService().recordEvent(
                            RecordingEventType.toolbarAction,
                            <String, dynamic>{
                              'toolbar': 'analysisSettings',
                              'action': 'setPerfectDatabase',
                              'enabled': value,
                            },
                          );
                          _setAnalysisPerfectDatabaseEnabled(context, value);
                        },
                      ),
                    if (isRuleSupportingPerfectDatabase())
                      SwitchListTile.adaptive(
                        key: const Key(
                          'play_area_analysis_settings_all_board_results',
                        ),
                        secondary: const Icon(Icons.hub_outlined),
                        title: Text(strings.showAllBoardResults),
                        subtitle: Text(strings.showAllBoardResultsDescription),
                        value: AnalysisMode.showAllBoardResults,
                        onChanged: (bool value) {
                          RecordingService().recordEvent(
                            RecordingEventType.toolbarAction,
                            <String, dynamic>{
                              'toolbar': 'analysisSettings',
                              'action': 'setAllBoardResults',
                              'visible': value,
                            },
                          );
                          AnalysisMode.setShowAllBoardResults(
                            value,
                            persist: true,
                          );
                        },
                      ),
                  ],
                ),
                LichessListSection(
                  header: Text(strings.analysisSettingsLocalEngine),
                  cardKey: const Key('play_area_analysis_settings_engine_card'),
                  children: <Widget>[
                    SwitchListTile.adaptive(
                      key: const Key(
                        'play_area_analysis_settings_advantage_graph',
                      ),
                      secondary: const Icon(Icons.show_chart_outlined),
                      title: Text(strings.showAdvantageGraph),
                      value: DB().displaySettings.isAdvantageGraphShown,
                      onChanged: (bool value) {
                        RecordingService().recordEvent(
                          RecordingEventType.toolbarAction,
                          <String, dynamic>{
                            'toolbar': 'analysisSettings',
                            'action': 'setEvaluationGraph',
                            'visible': value,
                          },
                        );
                        DB().displaySettings = DB().displaySettings.copyWith(
                          isAdvantageGraphShown: value,
                        );
                        AnalysisMode.refresh();
                      },
                    ),
                    SwitchListTile.adaptive(
                      key: const Key(
                        'play_area_analysis_settings_engine_lines',
                      ),
                      secondary: const Icon(Icons.subtitles_outlined),
                      title: Text(strings.showEngineLines),
                      subtitle: Text(strings.analysisEngineLinesDescription),
                      value: AnalysisMode.showEngineLines,
                      onChanged: (bool value) {
                        RecordingService().recordEvent(
                          RecordingEventType.toolbarAction,
                          <String, dynamic>{
                            'toolbar': 'analysisSettings',
                            'action': 'setEngineLines',
                            'visible': value,
                          },
                        );
                        AnalysisMode.setShowEngineLines(value, persist: true);
                      },
                    ),
                    SwitchListTile.adaptive(
                      key: const Key(
                        'play_area_analysis_settings_best_move_arrow',
                      ),
                      secondary: const Icon(Icons.near_me_outlined),
                      title: Text(strings.analysisBestMoveArrow),
                      subtitle: Text(strings.analysisBestMoveArrowDescription),
                      value: AnalysisMode.showBestMoveArrow,
                      onChanged: (bool value) {
                        RecordingService().recordEvent(
                          RecordingEventType.toolbarAction,
                          <String, dynamic>{
                            'toolbar': 'analysisSettings',
                            'action': 'setBestMoveArrow',
                            'visible': value,
                          },
                        );
                        AnalysisMode.setShowBestMoveArrow(value, persist: true);
                      },
                    ),
                    ListTile(
                      key: const Key(
                        'play_area_analysis_settings_engine_search_time',
                      ),
                      leading: const Icon(Icons.timer_outlined),
                      title: Text(strings.analysisSearchTime),
                      subtitle: Text(
                        _analysisSearchTimeValueLabel(
                          strings,
                          AnalysisMode.engineSearchTimeMs,
                        ),
                      ),
                      trailing: SizedBox(
                        width: 180,
                        child: Slider(
                          key: const Key(
                            'play_area_analysis_settings_engine_search_time_control',
                          ),
                          value: AnalysisMode.engineSearchTimeOptionIndex
                              .toDouble(),
                          max:
                              (AnalysisMode.engineSearchTimeOptionsMs.length -
                                      1)
                                  .toDouble(),
                          divisions:
                              AnalysisMode.engineSearchTimeOptionsMs.length - 1,
                          label: _analysisSearchTimeValueLabel(
                            strings,
                            AnalysisMode.engineSearchTimeMs,
                          ),
                          onChanged: (double value) {
                            final int searchTimeMs =
                                AnalysisMode.engineSearchTimeOptionAt(
                                  value.round(),
                                );
                            RecordingService().recordEvent(
                              RecordingEventType.toolbarAction,
                              <String, dynamic>{
                                'toolbar': 'analysisSettings',
                                'action': 'setEngineSearchTime',
                                'searchTimeMs': searchTimeMs,
                              },
                            );
                            AnalysisMode.setEngineSearchTimeMs(searchTimeMs);
                          },
                          onChangeEnd: (double value) {
                            final int searchTimeMs =
                                AnalysisMode.engineSearchTimeOptionAt(
                                  value.round(),
                                );
                            AnalysisMode.setEngineSearchTimeMs(
                              searchTimeMs,
                              persist: true,
                            );
                            _refreshEngineAnalysisAfterSettingsChange(context);
                          },
                        ),
                      ),
                    ),
                    ListTile(
                      key: const Key(
                        'play_area_analysis_settings_engine_threads',
                      ),
                      leading: const Icon(Icons.memory_outlined),
                      title: Text(strings.engineThreads),
                      subtitle: Text(
                        _analysisEngineThreadsSubtitle(
                          strings,
                          currentEngineThreads,
                          canUseAnalysisThreads,
                        ),
                      ),
                      trailing: SizedBox(
                        width: 180,
                        child: Slider(
                          key: const Key(
                            'play_area_analysis_settings_engine_threads_control',
                          ),
                          value: AnalysisMode.engineThreadOptionIndexFor(
                            currentEngineThreads,
                          ).toDouble(),
                          max: (AnalysisMode.engineThreadOptions.length - 1)
                              .toDouble(),
                          divisions:
                              AnalysisMode.engineThreadOptions.length - 1,
                          label: currentEngineThreads.toString(),
                          onChanged: canUseAnalysisThreads
                              ? (double value) {
                                  final int threads =
                                      AnalysisMode.engineThreadOptionAt(
                                        value.round(),
                                      );
                                  RecordingService().recordEvent(
                                    RecordingEventType.toolbarAction,
                                    <String, dynamic>{
                                      'toolbar': 'analysisSettings',
                                      'action': 'setEngineThreads',
                                      'threads': threads,
                                    },
                                  );
                                  _setAnalysisEngineThreads(threads);
                                }
                              : null,
                          onChangeEnd: canUseAnalysisThreads
                              ? (double value) {
                                  final int threads =
                                      AnalysisMode.engineThreadOptionAt(
                                        value.round(),
                                      );
                                  _setAnalysisEngineThreads(threads);
                                  _refreshEngineAnalysisAfterSettingsChange(
                                    context,
                                  );
                                }
                              : null,
                        ),
                      ),
                    ),
                    ListTile(
                      key: const Key(
                        'play_area_analysis_settings_engine_line_count',
                      ),
                      leading: const Icon(Icons.format_list_numbered),
                      title: Text(strings.multipleLines),
                      subtitle: Text(_analysisEngineLineCountSubtitle(strings)),
                      trailing: SizedBox(
                        width: 180,
                        child: Slider(
                          key: const Key(
                            'play_area_analysis_settings_engine_line_count_control',
                          ),
                          value: AnalysisMode.engineLineCount.toDouble(),
                          max: AnalysisMode.maxEngineLineCount.toDouble(),
                          divisions: AnalysisMode.maxEngineLineCount,
                          label: AnalysisMode.engineLineCount.toString(),
                          onChanged: (double value) {
                            final int count = value.round();
                            RecordingService().recordEvent(
                              RecordingEventType.toolbarAction,
                              <String, dynamic>{
                                'toolbar': 'analysisSettings',
                                'action': 'setEngineLineCount',
                                'count': count,
                              },
                            );
                            AnalysisMode.setEngineLineCount(count);
                          },
                          onChangeEnd: (double value) {
                            final int count = value.round();
                            AnalysisMode.setEngineLineCount(
                              count,
                              persist: true,
                            );
                            _refreshEngineAnalysisAfterSettingsChange(context);
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      );
      if (useFullScreenPage) {
        return Dialog.fullscreen(
          key: const Key('play_area_analysis_settings_sheet'),
          backgroundColor: colorScheme.surfaceContainerLow,
          child: SafeArea(child: content),
        );
      }
      return Dialog(
        key: const Key('play_area_analysis_settings_sheet'),
        backgroundColor: colorScheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: math.min(MediaQuery.sizeOf(dialogContext).width, 500),
          ),
          child: content,
        ),
      );
    },
  );
}

void _refreshEngineAnalysisAfterSettingsChange(BuildContext context) {
  if (!AnalysisMode.isFullAnalysis ||
      !AnalysisMode.hasEngineLinesSource ||
      AnalysisMode.isAnalyzing) {
    return;
  }
  unawaited(AnalysisService.refresh(context));
}

void _refreshAnalysisSourcesAfterSettingsChange(BuildContext context) {
  if (!AnalysisMode.isFullAnalysis || AnalysisMode.isAnalyzing) {
    return;
  }
  unawaited(AnalysisService.refresh(context));
}

void _setAnalysisPerfectDatabaseEnabled(BuildContext context, bool enabled) {
  assert(
    isRuleSupportingPerfectDatabase(),
    'Perfect database analysis toggle requires supported rules.',
  );
  final GeneralSettings current = DB().generalSettings;
  if (current.usePerfectDatabase == enabled) {
    return;
  }
  DB().generalSettings = current.copyWith(usePerfectDatabase: enabled);
  AnalysisMode.refresh();
  _refreshAnalysisSourcesAfterSettingsChange(context);
}

void _setAnalysisEngineThreads(int threads) {
  assert(
    AnalysisMode.engineThreadOptions.contains(threads),
    'Unsupported analysis engine thread count: $threads.',
  );
  final current = DB().generalSettings;
  if (current.engineThreads == threads) {
    return;
  }
  DB().generalSettings = current.copyWith(engineThreads: threads);
  AnalysisMode.refresh();
}

String _analysisSearchTimeValueLabel(S strings, int valueMs) {
  if (valueMs == AnalysisMode.maxEngineSearchTimeMs) {
    return '∞';
  }
  assert(valueMs % 1000 == 0, 'Analysis search time must be whole seconds.');
  // Analysis-board budget only. Do not reuse aiThinkingTimeValue / moveTime —
  // those control Human vs AI thinking time in GeneralSettings.
  if (valueMs >= 60 * 1000 && valueMs % (60 * 1000) == 0) {
    return strings.analysisSearchTimeMinutesValue(valueMs ~/ (60 * 1000));
  }
  return strings.analysisSearchTimeSecondsValue(valueMs ~/ 1000);
}

String _analysisEngineThreadsSubtitle(
  S strings,
  int currentEngineThreads,
  bool canUseAnalysisThreads,
) {
  if (canUseAnalysisThreads) {
    return '$currentEngineThreads';
  }
  return strings.analysisEngineThreadsSingleLineOnly;
}

String _analysisEngineLineCountSubtitle(S strings) {
  return strings.analysisEngineLineDisplay(AnalysisMode.engineLineCount);
}

String _analysisThreatLabel(S strings) {
  return strings.analysisThreat;
}

String _analysisThreatActionLabel(S strings) {
  return AnalysisMode.isThreatMode
      ? strings.stopShowingThreat
      : strings.showThreat;
}

String _analysisPerfectDatabaseShortLabel(S strings) {
  return strings.analysisPerfectDatabaseShortLabel;
}

/// The PlayArea widget is the main content of the game page.
class PlayArea extends StatefulWidget {
  /// Creates a PlayArea widget.
  ///
  /// The [boardImage] parameter is the ImageProvider for the selected board image.
  /// The [child] is typically the GameBoard widget.
  const PlayArea({
    super.key,
    required this.boardImage,
    required this.child, // new
  });

  /// The ImageProvider for the selected board image.
  final ImageProvider? boardImage;

  /// The child widget to be displayed, typically the GameBoard.
  final Widget child;

  @override
  PlayAreaState createState() => PlayAreaState();
}

class PlayAreaState extends State<PlayArea> {
  /// A list to store historical advantage values for the advantage chart.
  List<int> advantageData = <int>[];
  late final LiveAdvantageHistory _liveAdvantageHistory;

  bool _isBoardFlipped = false;
  bool _liveEvaluationSyncScheduled = false;
  bool _analysisPositionChangeInProgress = false;
  Timer? _analysisRefreshDebounceTimer;
  GameRecorder? _analysisMoveRecorder;
  PgnNode<ExtMove>? _lastAnalysisRefreshNode;
  PgnNode<ExtMove>? _scheduledAnalysisRefreshNode;
  List<MoveAnalysisResult>? _scheduledAnalysisRefreshResults;
  List<MoveAnalysisResult>? _scheduledAnalysisRefreshLineResults;
  static const double _kMoveListRouteTopInset = 80;
  static const double _kInlineMoveListHeight = 40;
  static const double _kWrappedMoveListMaxHeight = 104;
  static const double _kPlayerPanelHeight = 56;
  static const double _kOfflineBoardPlayerPanelHeight = 72;
  static const double _kOfflineBoardLayoutSafetyMargin = 4;
  static const double _kAnalysisEngineLinesReserveHeight = 90;
  static const double _kAnalysisSmallBoardScale = 0.8;
  static const Duration _kAnalysisRefreshDebounceDelay = Duration(
    milliseconds: 250,
  );

  static const double _kBalancedLayoutSafetyMargin = 24;
  static const double _kBalancedLayoutMinWidth = 240;
  static const double _kAdvantageIndicatorWidth = 16;
  static const double _kAdvantageIndicatorGap = 6;
  static const double _kAdvantageIndicatorReserve =
      _kAdvantageIndicatorWidth + _kAdvantageIndicatorGap;

  @override
  void initState() {
    super.initState();
    // Listen to changes in header icons (usually triggered after a move).
    GameController().headerIconsNotifier.addListener(_updateUI);
    _liveAdvantageHistory = LiveAdvantageHistory(advantageData);
    LiveEvaluationService.stateNotifier.addListener(
      _handleLiveEvaluationChanged,
    );
    _syncAnalysisMoveListener();

    // Optionally, initialize advantageData with the current value:
    advantageData.add(_getCurrentAdvantageValue());
    _scheduleLiveEvaluationSync();
  }

  @override
  void didUpdateWidget(covariant PlayArea oldWidget) {
    super.didUpdateWidget(oldWidget);
    _scheduleLiveEvaluationSync();
  }

  @override
  void dispose() {
    // Stopping the engine must not notify AnalysisMode listeners here: the
    // widget tree is locked during unmount (e.g. DisplaySettings rebuild after
    // persisting analysis search time) and ValueListenableBuilder.setState
    // would crash.
    AnalysisService.stopActiveEngineAnalysis(notify: false);
    AnalysisService.invalidateBestMoveHintCache();
    GameController().headerIconsNotifier.removeListener(_updateUI);
    LiveEvaluationService.stateNotifier.removeListener(
      _handleLiveEvaluationChanged,
    );
    _analysisMoveRecorder?.moveCountNotifier.removeListener(
      _handleAnalysisPositionChanged,
    );
    _analysisRefreshDebounceTimer?.cancel();
    unawaited(LiveEvaluationService.disableAndWait());
    super.dispose();
  }

  void _scheduleLiveEvaluationSync() {
    if (_liveEvaluationSyncScheduled) {
      return;
    }
    _liveEvaluationSyncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _liveEvaluationSyncScheduled = false;
      if (!mounted) {
        return;
      }
      unawaited(LiveEvaluationService.syncWithStoredDisplaySettings());
    });
  }

  void _syncAnalysisMoveListener() {
    final GameRecorder recorder = GameController().gameRecorder;
    if (identical(_analysisMoveRecorder, recorder)) {
      return;
    }
    _analysisMoveRecorder?.moveCountNotifier.removeListener(
      _handleAnalysisPositionChanged,
    );
    _analysisMoveRecorder = recorder;
    _lastAnalysisRefreshNode = recorder.activeNode ?? recorder.pgnRoot;
    recorder.moveCountNotifier.addListener(_handleAnalysisPositionChanged);
  }

  void _handleAnalysisPositionChanged() {
    _syncAnalysisMoveListener();
    final GameRecorder recorder = GameController().gameRecorder;
    final PgnNode<ExtMove> currentNode =
        recorder.activeNode ?? recorder.pgnRoot;
    if (identical(_lastAnalysisRefreshNode, currentNode)) {
      return;
    }
    _lastAnalysisRefreshNode = currentNode;
    AnalysisService.invalidateBestMoveHintCache();
    if (AnalysisService.isBestMoveHintSearching || AnalysisMode.isHint) {
      AnalysisService.stopBestMoveHint();
      return;
    }
    if (AnalysisMode.isFullAnalysis) {
      _scheduleAnalysisRefreshForCurrentPosition();
    }
  }

  void _scheduleAnalysisRefreshForCurrentPosition() {
    final GameRecorder recorder = GameController().gameRecorder;
    _scheduledAnalysisRefreshNode = recorder.activeNode ?? recorder.pgnRoot;
    _scheduledAnalysisRefreshResults = AnalysisMode.analysisResults;
    _scheduledAnalysisRefreshLineResults = AnalysisMode.analysisLineResults;
    _analysisRefreshDebounceTimer?.cancel();
    _analysisRefreshDebounceTimer = Timer(_kAnalysisRefreshDebounceDelay, () {
      if (!mounted || !AnalysisMode.isFullAnalysis) {
        return;
      }
      final PgnNode<ExtMove>? scheduledNode = _scheduledAnalysisRefreshNode;
      final List<MoveAnalysisResult>? scheduledResults =
          _scheduledAnalysisRefreshResults;
      final List<MoveAnalysisResult>? scheduledLineResults =
          _scheduledAnalysisRefreshLineResults;
      _scheduledAnalysisRefreshNode = null;
      _scheduledAnalysisRefreshResults = null;
      _scheduledAnalysisRefreshLineResults = null;
      final GameRecorder recorder = GameController().gameRecorder;
      final PgnNode<ExtMove> currentNode =
          recorder.activeNode ?? recorder.pgnRoot;
      if (!identical(scheduledNode, currentNode) ||
          !identical(scheduledResults, AnalysisMode.analysisResults) ||
          !identical(scheduledLineResults, AnalysisMode.analysisLineResults)) {
        return;
      }
      unawaited(AnalysisService.refreshForCurrentPosition(context));
    });
  }

  /// Retrieve the current advantage value from GameController.
  /// value > 0 means white advantage, value < 0 means black advantage.
  /// The range is [-100, 100].
  int _getCurrentAdvantageValue() {
    final int? liveScore = LiveEvaluationService.state.whiteScore;
    if (LiveEvaluationService.enabled && liveScore != null) {
      return liveScore;
    }
    return _getLegacyAdvantageValue();
  }

  int _getLegacyAdvantageValue() {
    final int value = GameController().value == null
        ? 0
        : int.parse(GameController().value!);
    return value;
  }

  void _handleLiveEvaluationChanged() {
    if (!mounted) {
      return;
    }
    final bool changed = _liveAdvantageHistory.update(
      LiveEvaluationService.state,
      fallbackScore: _getLegacyAdvantageValue(),
    );
    if (changed) {
      setState(() {});
    }
  }

  double _moveListRouteTopInset(BuildContext context) {
    return Navigator.canPop(context) ? _kMoveListRouteTopInset : 0;
  }

  Widget _withMoveListTopInset(BuildContext context, Widget child) {
    final double topInset = _moveListRouteTopInset(context);
    if (topInset == 0) {
      return child;
    }
    return Padding(
      key: const Key('play_area_move_list_route_top_inset'),
      padding: EdgeInsets.only(top: topInset),
      child: child,
    );
  }

  double _wrappedMoveListReservedHeightForRoute(BuildContext context) {
    return _kWrappedMoveListMaxHeight + _moveListRouteTopInset(context);
  }

  Color _actionSheetBackground(BuildContext context) {
    return Theme.of(context).colorScheme.surfaceContainerLow;
  }

  Color _actionSheetForeground(BuildContext context) {
    return Theme.of(context).colorScheme.onSurface;
  }

  BuildContext _stableActionContext(BuildContext fallbackContext) {
    final BuildContext? overlayContext =
        currentNavigatorKey.currentState?.overlay?.context;
    if (overlayContext != null && overlayContext.mounted) {
      return overlayContext;
    }

    final BuildContext? messengerContext =
        rootScaffoldMessengerKey.currentState?.context;
    if (messengerContext != null &&
        messengerContext.mounted &&
        Navigator.maybeOf(messengerContext) != null) {
      return messengerContext;
    }

    assert(fallbackContext.mounted, 'Action menus require a mounted context.');
    return fallbackContext;
  }

  bool _shouldShowAdvantageGraph({required bool isGameSurface}) {
    return isGameSurface &&
        DB().displaySettings.isAdvantageGraphShown &&
        advantageData.isNotEmpty;
  }

  double _pieceRowsHeightForLayout(BuildContext context) {
    final double scaledTextHeight = MediaQuery.textScalerOf(context).scale(18);
    return math.max(24, scaledTextHeight + 6) * 2;
  }

  double _humanAiPlayerPanelHeightForLayout(BuildContext context) {
    final double scaledTextHeight = MediaQuery.textScalerOf(context).scale(38);
    return math.max(_kPlayerPanelHeight, scaledTextHeight + 18);
  }

  double _gameTipPanelHeightForLayout(BuildContext context) {
    final double scaledTwoLineHeight = MediaQuery.textScalerOf(
      context,
    ).scale(28);
    return math.max(GameHeader.contextualHeight, scaledTwoLineHeight + 20);
  }

  /// Shrinks the board to fit the height left over after [nonBoardHeight] is
  /// reserved for the move list, player panels, and similar fixed-height
  /// chrome. Without this, a full-width board can overflow the available
  /// height (e.g. when a system navigation bar eats into it), forcing the
  /// user to scroll before the board -- and the controls below it -- become
  /// fully visible and playable.
  double _boardSizeForConstraints(
    BoxConstraints constraints,
    double nonBoardHeight,
  ) {
    if (!constraints.hasBoundedHeight) {
      return constraints.maxWidth;
    }
    final double heightBudget = math.max(
      0,
      constraints.maxHeight - nonBoardHeight,
    );
    return math.min(constraints.maxWidth, heightBudget);
  }

  /// Updates the UI by calling setState.
  /// Appends the current advantage value so that the chart reflects
  /// the latest advantage trend after each AI move.
  void _updateUI() {
    setState(() {
      if (GameController().gameRecorder.mainlineMoves.isEmpty) {
        advantageData.clear();
        advantageData.add(_getCurrentAdvantageValue());
      }

      if (!LiveEvaluationService.enabled &&
          GameController().lastMoveFromAI &&
          GameController().value != null &&
          GameController().aiMoveType != AiMoveType.unknown) {
        advantageData.add(_getCurrentAdvantageValue());
        GameController().lastMoveFromAI = false;
      }
    });
  }

  /// Takes a screenshot and saves it to the specified [storageLocation]
  /// with an optional [filename].
  Future<void> _takeScreenshot(
    String storageLocation, [
    String? filename,
  ]) async {
    await ScreenshotService.takeScreenshot(storageLocation, filename);
  }

  /// Opens a modal bottom sheet containing [modal].
  void _openModal(BuildContext context, Widget modal) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.modalBottomSheetBackgroundColor,
      builder: (_) => modal,
    );
  }

  /// Navigates to the GeneralSettingsPage.
  void _navigateToSettings(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute<GeneralSettingsPage>(
        settings: const RouteSettings(name: '/generalSettings'),
        builder: (_) => const GeneralSettingsPage(),
      ),
    );
  }

  /// Opens a dialog with the provided [dialog] widget.
  void _openDialog(BuildContext context, Widget dialog) {
    showDialog(context: context, builder: (_) => dialog);
  }

  void _openGameOptions(BuildContext context) {
    _openModal(
      context,
      GameOptionsModal(onTriggerScreenshot: () => _takeScreenshot("gallery")),
    );
  }

  void _requestRegularNewGame(NavigatorState navigator) {
    if (_isAnalysisMode) {
      RecordingService().recordEvent(
        RecordingEventType.toolbarAction,
        <String, dynamic>{'toolbar': 'analysisBottom', 'action': 'newGame'},
      );
      GameController().reset();
      GameController().headerIconsNotifier.showIcons();
      GameController().boardSemanticsNotifier.updateSemantics();
      return;
    }

    if (_isOfflineBoardMode) {
      unawaited(showOfflineBoardNewGameSheet(navigator.context));
      return;
    }

    _openGameOptions(navigator.context);
  }

  void _requestAiVsAiNewGame(NavigatorState navigator) {
    assert(_isAiVsAiMode, 'Computer self-play controls require AI vs AI mode.');
    RecordingService().recordEvent(
      RecordingEventType.toolbarAction,
      <String, dynamic>{'toolbar': 'aiVsAiBottom', 'action': 'newGame'},
    );
    _requestRegularNewGame(navigator);
  }

  void _openAiVsAiMoves(NavigatorState navigator) {
    assert(_isAiVsAiMode, 'Computer self-play controls require AI vs AI mode.');
    RecordingService().recordEvent(
      RecordingEventType.toolbarAction,
      <String, dynamic>{'toolbar': 'aiVsAiBottom', 'action': 'moveList'},
    );
    _openMovesWithNavigator(navigator);
  }

  void _pauseAiVsAiPlayback() {
    assert(_isAiVsAiMode, 'Computer self-play controls require AI vs AI mode.');
    RecordingService().recordEvent(
      RecordingEventType.toolbarAction,
      <String, dynamic>{'toolbar': 'aiVsAiBottom', 'action': 'pause'},
    );
    GameController().pauseAiVsAiPlayback();
  }

  Future<void> _resumeAiVsAiPlayback(BuildContext context) async {
    assert(_isAiVsAiMode, 'Computer self-play controls require AI vs AI mode.');
    RecordingService().recordEvent(
      RecordingEventType.toolbarAction,
      <String, dynamic>{'toolbar': 'aiVsAiBottom', 'action': 'resume'},
    );
    await GameController().resumeAiVsAiPlayback(
      context,
      session:
          GameSessionScope.sessionOf(context) ??
          GameController().activeNativeMillSession,
    );
  }

  Future<void> _stepAiVsAiPlayback(BuildContext context) async {
    assert(_isAiVsAiMode, 'Computer self-play controls require AI vs AI mode.');
    RecordingService().recordEvent(
      RecordingEventType.toolbarAction,
      <String, dynamic>{'toolbar': 'aiVsAiBottom', 'action': 'stepForward'},
    );
    await GameController().stepAiVsAiPlayback(
      context,
      session:
          GameSessionScope.sessionOf(context) ??
          GameController().activeNativeMillSession,
    );
  }

  void _openMovesWithNavigator(
    NavigatorState navigator, {
    bool? initialShowBranchTree,
  }) {
    if (AccessibilityStatus.isScreenReaderActive) {
      // On screen readers, use a bottom sheet.
      final BuildContext navigatorContext = navigator.context;
      _openModal(navigatorContext, _buildMoveModal(navigatorContext));
      return;
    }

    // Complete all ongoing animations before navigating to ensure pieces are
    // in their final positions when the user returns.
    GameController().animationManager.completeAllAnimations();
    navigator.push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: '/movesList'),
        builder: (BuildContext context) => MovesListPage(
          initialLayout: _isAnalysisMode ? MovesViewLayout.medium : null,
          initialShowBranchTree: initialShowBranchTree,
        ),
      ),
    );
  }

  Future<bool> _applyAnalysisExplorerMove(
    BuildContext context,
    GameAction action,
  ) async {
    final String? move = MillActionCodec.moveStringFrom(action);
    assert(
      move != null && move.isNotEmpty,
      'Analysis explorer move selection requires move notation.',
    );
    if (move == null || move.isEmpty) {
      return false;
    }
    return _applyAnalysisMove(context, move);
  }

  Future<T?> _runAnalysisPositionChange<T>(Future<T> Function() change) async {
    assert(_isAnalysisMode, 'Analysis position changes require analysis mode.');
    if (_analysisPositionChangeInProgress) {
      return null;
    }

    _analysisPositionChangeInProgress = true;
    final bool restartAnalysis =
        AnalysisMode.isFullAnalysis || AnalysisMode.isAnalyzing;
    try {
      // Native search cancellation is asynchronous. Mutating or replaying the
      // same session before the old pass has drained can otherwise race the
      // Rust search and recursively enter history replay under rapid taps.
      await AnalysisService.stopActiveEngineAnalysisAndWait();
      if (!mounted) {
        return null;
      }
      final T result = await change();
      if (restartAnalysis && mounted) {
        if (AnalysisMode.isFullAnalysis) {
          _scheduleAnalysisRefreshForCurrentPosition();
        } else {
          // The first engine pass may not have published a line yet, so there
          // is no enabled overlay for the normal debounce path to preserve.
          unawaited(AnalysisService.refresh(context));
        }
      }
      return result;
    } finally {
      _analysisPositionChangeInProgress = false;
    }
  }

  Future<void> _navigateAnalysisNode(
    BuildContext context,
    PgnNode<ExtMove> node,
  ) async {
    await _runAnalysisPositionChange<void>(() async {
      await HistoryNavigator.gotoNode(context, node, pop: false);
    });
  }

  Future<bool> _applyAnalysisMove(BuildContext context, String move) async {
    final GameSession? session = GameSessionScope.sessionOf(context);
    assert(session != null, 'Analysis move application requires a session.');
    if (session == null) {
      return false;
    }

    final bool? applied = await _runAnalysisPositionChange<bool>(() async {
      GameAction? selectedAction;
      for (final GameAction action in session.legalActions) {
        if (MillActionCodec.moveStringFrom(action) == move) {
          selectedAction = action;
          break;
        }
      }

      assert(
        selectedAction != null,
        'Analysis move "$move" must be legal in the active session.',
      );
      if (selectedAction == null) {
        return false;
      }

      await session.apply(selectedAction);
      return true;
    });
    return applied ?? false;
  }

  Future<void> _openBoardEditorFromAnalysis() async {
    assert(_isAnalysisMode, 'Board editor menu entry is analysis-mode only.');
    await AnalysisService.stopActiveEngineAnalysisAndWait();
    if (!mounted) {
      return;
    }
    GameController().enterSetupPosition();
    GameController().headerTipNotifier.showTip(
      S.of(context).boardEditor,
      snackBar: false,
    );
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _toggleAnalysisThreatFromAnalysis(
    BuildContext context, {
    required String toolbar,
  }) async {
    assert(_isAnalysisMode, 'Threat mode is analysis-mode only.');
    RecordingService()
        .recordEvent(RecordingEventType.toolbarAction, <String, dynamic>{
          'toolbar': toolbar,
          'action': AnalysisMode.isThreatMode ? 'stopThreat' : 'showThreat',
        });

    await AnalysisService.toggleThreat(context);
  }

  void _continueFromHere({
    required NativeMillGameSession session,
    required NavigatorState navigator,
    required GameMode mode,
  }) {
    assert(_isAnalysisMode, 'Continue from here is analysis-mode only.');
    assert(
      mode == GameMode.humanVsAi || mode == GameMode.humanVsHuman,
      'Continue from here only supports local playable modes.',
    );
    final String fen = session.getFen();
    final bool started = GameController().startGameFromFen(
      mode: mode,
      fen: fen,
    );
    assert(started, 'Continue from here must start from the current FEN.');

    RecordingService().recordEvent(
      RecordingEventType.toolbarAction,
      <String, dynamic>{
        'toolbar': 'analysisMenu',
        'action': 'continueFromHere',
        'mode': mode.toString(),
      },
    );

    navigator.pushReplacement(
      MaterialPageRoute<void>(
        settings: RouteSettings(name: '/continueFromHere/${mode.name}'),
        builder: (BuildContext routeContext) =>
            _ContinueFromHereGameRoute(mode: mode),
      ),
    );
  }

  void _showContinueFromHereMenu(
    BuildContext context, {
    required NativeMillGameSession session,
    required NavigatorState navigator,
    S? strings,
  }) {
    assert(_isAnalysisMode, 'Continue from here menu is analysis-mode only.');
    if (!mounted) {
      return;
    }
    final BuildContext sheetContext = context.mounted
        ? context
        : _stableActionContext(context);
    final S effectiveStrings = strings ?? S.of(sheetContext);
    showLichessActionSheet<void>(
      context: sheetContext,
      sheetKey: const Key('play_area_analysis_continue_from_here_sheet'),
      title: Text(effectiveStrings.continueFromHere),
      backgroundColor: _actionSheetBackground(sheetContext),
      foregroundColor: _actionSheetForeground(sheetContext),
      actions: <LichessActionSheetAction>[
        LichessActionSheetAction(
          key: const Key('play_area_analysis_continue_play_against_computer'),
          leading: const Icon(Icons.smart_toy_outlined),
          makeLabel: (BuildContext context) =>
              Text(effectiveStrings.playAgainstComputer),
          onPressed: () => _continueFromHere(
            session: session,
            navigator: navigator,
            mode: GameMode.humanVsAi,
          ),
        ),
        LichessActionSheetAction(
          key: const Key('play_area_analysis_continue_over_the_board'),
          leading: const Icon(Icons.groups_2_outlined),
          makeLabel: (BuildContext context) =>
              Text(effectiveStrings.offlineBoard),
          onPressed: () => _continueFromHere(
            session: session,
            navigator: navigator,
            mode: GameMode.humanVsHuman,
          ),
        ),
      ],
    );
  }

  void _showAnalysisShareExportMenu(BuildContext context, {S? strings}) {
    assert(_isAnalysisMode, 'Share/export menu is analysis-mode only.');
    if (!mounted) {
      return;
    }

    final BuildContext sheetContext = _stableActionContext(context);
    final S effectiveStrings = strings ?? S.of(sheetContext);
    final GameRecorder recorder = GameController().gameRecorder;
    final bool hasVariations = recorder.hasVariations();
    final String pgn = recorder.moveHistoryText.trim();
    final String mainlinePgn = recorder.moveHistoryTextWithoutVariations.trim();
    final String currentLinePgn = recorder.moveHistoryTextCurrentLine.trim();
    final String sharePgn = hasVariations ? pgn : mainlinePgn;
    final String? fen =
        GameController().activeFen ??
        GameController().activeNativeMillSession?.getFen();

    final List<LichessActionSheetAction> actions = <LichessActionSheetAction>[
      if (sharePgn.isNotEmpty)
        LichessActionSheetAction(
          key: const Key('play_area_analysis_share_export_share_pgn'),
          leading: const Icon(Icons.ios_share_outlined),
          makeLabel: (BuildContext context) => Text(effectiveStrings.sharePgn),
          onPressed: () => unawaited(
            _shareAnalysisText(
              text: sharePgn,
              subject: 'Game PGN',
              eventAction: 'sharePgn',
            ),
          ),
        ),
      if (fen != null && fen.trim().isNotEmpty)
        LichessActionSheetAction(
          key: const Key('play_area_analysis_share_export_share_fen'),
          leading: const Icon(Icons.ios_share_outlined),
          makeLabel: (BuildContext context) => Text(effectiveStrings.shareFen),
          onPressed: () => unawaited(
            _shareAnalysisText(
              text: fen,
              subject: 'Position FEN',
              eventAction: 'shareFen',
            ),
          ),
        ),
      if (!hasVariations && mainlinePgn.isNotEmpty)
        LichessActionSheetAction(
          key: const Key('play_area_analysis_share_export_copy_pgn'),
          leading: const Icon(Icons.article_outlined),
          makeLabel: (BuildContext context) => Text(effectiveStrings.copyPgn),
          onPressed: () => unawaited(
            _copyAnalysisTextToClipboard(
              text: mainlinePgn,
              message: effectiveStrings.moveHistoryCopied,
              eventAction: 'copyPgn',
            ),
          ),
        ),
      if (hasVariations && mainlinePgn.isNotEmpty)
        LichessActionSheetAction(
          key: const Key('play_area_analysis_share_export_copy_mainline'),
          leading: const Icon(Icons.show_chart_outlined),
          makeLabel: (BuildContext context) =>
              Text(effectiveStrings.includeVariationsMainline),
          onPressed: () => unawaited(
            _copyAnalysisTextToClipboard(
              text: mainlinePgn,
              message: effectiveStrings.moveHistoryCopied,
              eventAction: 'copyMainlinePgn',
            ),
          ),
        ),
      if (hasVariations && currentLinePgn.isNotEmpty)
        LichessActionSheetAction(
          key: const Key('play_area_analysis_share_export_copy_current_line'),
          leading: const Icon(Icons.trending_flat),
          makeLabel: (BuildContext context) =>
              Text(effectiveStrings.includeVariationsCurrentLine),
          onPressed: () => unawaited(
            _copyAnalysisTextToClipboard(
              text: currentLinePgn,
              message: effectiveStrings.moveHistoryCopied,
              eventAction: 'copyCurrentLinePgn',
            ),
          ),
        ),
      if (hasVariations && pgn.isNotEmpty)
        LichessActionSheetAction(
          key: const Key('play_area_analysis_share_export_copy_all_variations'),
          leading: const Icon(Icons.account_tree_outlined),
          makeLabel: (BuildContext context) =>
              Text(effectiveStrings.includeVariationsAll),
          onPressed: () => unawaited(
            _copyAnalysisTextToClipboard(
              text: pgn,
              message: effectiveStrings.moveHistoryCopied,
              eventAction: 'copyAllVariationsPgn',
            ),
          ),
        ),
      if (fen != null && fen.trim().isNotEmpty)
        LichessActionSheetAction(
          key: const Key('play_area_analysis_share_export_copy_fen'),
          leading: const Icon(Icons.content_copy_outlined),
          makeLabel: (BuildContext context) => Text(effectiveStrings.copyFen),
          onPressed: () => unawaited(
            _copyAnalysisTextToClipboard(
              text: fen,
              message: effectiveStrings.fenCopiedToClipboard,
              eventAction: 'copyFen',
            ),
          ),
        ),
    ];
    assert(
      actions.isNotEmpty,
      'Share/export menu requires at least one PGN or FEN action.',
    );
    if (actions.isEmpty) {
      return;
    }

    showLichessActionSheet<void>(
      context: sheetContext,
      sheetKey: const Key('play_area_analysis_share_export_sheet'),
      title: Text(effectiveStrings.shareAndExport),
      backgroundColor: _actionSheetBackground(sheetContext),
      foregroundColor: _actionSheetForeground(sheetContext),
      actions: actions,
    );
  }

  Future<void> _copyAnalysisTextToClipboard({
    required String text,
    required String message,
    required String eventAction,
  }) async {
    assert(_isAnalysisMode, 'Analysis export is analysis-mode only.');
    assert(text.trim().isNotEmpty, 'Analysis export text must not be empty.');
    DiagnosticReplayGuard.requireAllowed('Game clipboard exporting');
    RecordingService().recordEvent(
      RecordingEventType.toolbarAction,
      <String, dynamic>{'toolbar': 'analysisMenu', 'action': eventAction},
    );

    await Clipboard.setData(ClipboardData(text: text));

    assert(
      rootScaffoldMessengerKey.currentState != null,
      'Analysis export feedback requires the root scaffold messenger.',
    );
    rootScaffoldMessengerKey.currentState!.showSnackBarClear(message);
  }

  Future<void> _shareAnalysisText({
    required String text,
    required String subject,
    required String eventAction,
  }) async {
    assert(_isAnalysisMode, 'Analysis sharing is analysis-mode only.');
    assert(text.trim().isNotEmpty, 'Analysis sharing text must not be empty.');
    DiagnosticReplayGuard.requireAllowed('Game sharing');
    RecordingService().recordEvent(
      RecordingEventType.toolbarAction,
      <String, dynamic>{'toolbar': 'analysisMenu', 'action': eventAction},
    );

    await SharePlus.instance.share(ShareParams(text: text, subject: subject));
  }

  bool get _shouldShowAiChatMenuAction {
    if (!AiComplianceConfig.releaseGateSatisfied || !DB().llmSettings.enabled) {
      return false;
    }

    final GameMode mode = GameController().gameInstance.gameMode;
    return mode == GameMode.humanVsAi ||
        mode == GameMode.humanVsHuman ||
        mode == GameMode.aiVsAi;
  }

  void _showAiChatDialog(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) => const AiChatDialog(),
    );
  }

  bool get _usesLichessHumanAiToolbar =>
      GameController().gameInstance.gameMode == GameMode.humanVsAi;

  bool get _isOfflineBoardMode =>
      GameController().gameInstance.gameMode == GameMode.humanVsHuman;

  bool get _isAiVsAiMode =>
      GameController().gameInstance.gameMode == GameMode.aiVsAi;

  bool get _isAnalysisMode =>
      GameController().gameInstance.gameMode == GameMode.analysis;

  Phase get _activePhase {
    return GameController().activeSessionPhase ??
        GameController().activeBoardView.phase;
  }

  bool get _canResignFromBottomBar {
    return _usesLichessHumanAiToolbar &&
        GameController().gameRecorder.currentPath.length >= 2 &&
        _activePhase != Phase.ready &&
        _activePhase != Phase.gameOver;
  }

  /// Offer draw is only wired up for humanVsAi (the AI decides for itself)
  /// and local humanVsHuman (the other player decides on the same device).
  /// LAN draw offers would need a new bilateral request/response network
  /// message -- unlike resignation, a draw cannot be unilaterally declared
  /// -- and are intentionally out of scope for now; resign remains
  /// available there instead.
  bool get _canOfferDrawFromBottomBar {
    return _usesLichessHumanAiToolbar &&
        GameController().gameRecorder.currentPath.length >= 2 &&
        _activePhase != Phase.ready &&
        _activePhase != Phase.gameOver &&
        !GameController().isEngineRunning &&
        !GameController().isEngineInDelay;
  }

  bool get _canOfferDrawFromRegularBottomBar {
    return GameController().gameInstance.gameMode == GameMode.humanVsHuman &&
        GameController().gameRecorder.currentPath.length >= 2 &&
        _activePhase != Phase.ready &&
        _activePhase != Phase.gameOver;
  }

  bool get _canTakeBackFromBottomBar {
    return _usesLichessHumanAiToolbar &&
        GameController().gameRecorder.currentPath.isNotEmpty &&
        !GameController().isEngineRunning &&
        !GameController().isEngineInDelay &&
        _humanAiTakeBackStepCountOrNull != null;
  }

  int? get _humanAiTakeBackStepCountOrNull {
    assert(_usesLichessHumanAiToolbar);
    return _takeBackStepCountForRequesterOrNull(_humanAiTakeBackRequesterSide);
  }

  int? get _remoteTakeBackStepCountOrNull {
    assert(GameController().isRemoteGameMode);
    final PieceColor requesterSide = GameController().getLocalColor();
    assert(
      requesterSide == PieceColor.white || requesterSide == PieceColor.black,
      'Remote takeback requires a playable local requester side.',
    );
    return _takeBackStepCountForRequesterOrNull(requesterSide);
  }

  PieceColor get _humanAiTakeBackRequesterSide {
    assert(_usesLichessHumanAiToolbar);
    final List<Player> humanPlayers = GameController().gameInstance.players
        .where((Player player) => !player.isAi)
        .toList(growable: false);
    assert(
      humanPlayers.length == 1,
      'Human vs AI takeback requires exactly one human requester.',
    );
    return humanPlayers.single.color;
  }

  int? _takeBackStepCountForRequesterOrNull(PieceColor requesterSide) {
    assert(
      requesterSide == PieceColor.white || requesterSide == PieceColor.black,
    );
    final List<ExtMove> path = GameController().gameRecorder.currentPath;
    if (path.isEmpty) {
      return null;
    }

    final NativeMillRulesPort? preview = _takeBackPreviewPortOrNull(path);
    if (preview == null) {
      return null;
    }
    try {
      // Undo until the requester is truly the side to act. This keeps capture
      // actions attached to the requester: if White made a mill and captured,
      // then Black replied, a Black request removes only Black's move, while a
      // White request removes Black's move and White's capture.
      for (int steps = 1; steps <= path.length; steps++) {
        preview.undo();
        final PieceColor sideAfterUndo = _pieceColorFromSeat(
          preview.snapshot.activeSeat,
        );
        if (sideAfterUndo == requesterSide) {
          return steps;
        }
      }
    } finally {
      preview.dispose();
    }

    return null;
  }

  NativeMillRulesPort? _takeBackPreviewPortOrNull(List<ExtMove> path) {
    final NativeMillRulesPort port = NativeMillRulesPort(
      ruleSettings:
          GameController().activeNativeMillSession?.activeRuleSettings ??
          DB().ruleSettings,
      generalSettings: DB().generalSettings,
    );

    try {
      final String? setupPosition = GameController().gameRecorder.setupPosition;
      if (setupPosition != null) {
        port.setFromFen(setupPosition);
      }

      for (final ExtMove move in path) {
        final GameAction? action = _legalActionForMove(port, move.move);
        if (action == null) {
          port.dispose();
          return null;
        }
        port.apply(action);
      }
      return port;
    } on Object {
      port.dispose();
      rethrow;
    }
  }

  GameAction? _legalActionForMove(NativeMillRulesPort port, String move) {
    for (final GameAction action in port.legalActions) {
      if (MillActionCodec.moveStringFrom(action) == move) {
        return action;
      }
    }
    return null;
  }

  PieceColor _pieceColorFromSeat(PlayerSeat seat) {
    assert(
      seat == PlayerSeat.first || seat == PlayerSeat.second,
      'Requester takeback requires a playable side, got $seat.',
    );
    return seat == PlayerSeat.first ? PieceColor.white : PieceColor.black;
  }

  Future<void> _takeBackFromRegularBottomBar(BuildContext context) async {
    if (GameController().isRemoteGameMode) {
      await _takeBackForRequesterFromRegularBottomBar(
        context,
        requesterSide: GameController().getLocalColor(),
      );
      return;
    }

    if (GameController().gameInstance.gameMode == GameMode.humanVsHuman) {
      final int? steps = _offlineBoardTakeBackStepCountOrNull;
      if (steps == null) {
        GameController().headerTipNotifier.showTip(S.of(context).noMove);
        return;
      }
      await HistoryNavigator.takeBackN(
        context,
        steps,
        pop: false,
        toolbar: true,
      );
      _syncOfflineBoardClockToPosition();
      return;
    }

    await HistoryNavigator.takeBack(context, pop: false, toolbar: true);
  }

  /// Returns the number of recorder actions that form the latest Mill turn.
  ///
  /// A chess move is atomic, but a Mill turn can be represented by a placing
  /// or moving action followed by one or more captures by the same side.  The
  /// Offline Board undo button therefore removes the complete trailing
  /// same-side group so it never leaves the game halfway through a capture
  /// sequence.
  int? get _offlineBoardTakeBackStepCountOrNull {
    assert(_isOfflineBoardMode);
    final List<ExtMove> path = GameController().gameRecorder.currentPath;
    return OfflineBoardHistory.takeBackStepCount(
      path.map((ExtMove move) => move.side).toList(growable: false),
    );
  }

  Future<void> _stepBackFromRegularBottomBar(BuildContext context) async {
    if (GameController().isRemoteGameMode) {
      return;
    }
    if (_isAnalysisMode) {
      await _runAnalysisPositionChange<void>(() async {
        await HistoryNavigator.takeBack(context, pop: false, toolbar: true);
      });
    } else {
      await HistoryNavigator.takeBack(context, pop: false, toolbar: true);
    }
    _syncOfflineBoardClockToPosition();
  }

  Future<void> _stepForwardFromRegularBottomBar(BuildContext context) async {
    if (GameController().isRemoteGameMode) {
      return;
    }
    if (_isAnalysisMode) {
      await _runAnalysisPositionChange<void>(() async {
        await HistoryNavigator.stepForward(context, pop: false, toolbar: true);
      });
    } else {
      await HistoryNavigator.stepForward(context, pop: false, toolbar: true);
    }
    _syncOfflineBoardClockToPosition();
  }

  void _syncOfflineBoardClockToPosition() {
    if (!_isOfflineBoardMode) {
      return;
    }
    final PieceColor side = GameController().activeBoardView.sideToMove;
    if (side == PieceColor.white || side == PieceColor.black) {
      OfflineBoardClock().syncActiveSide(side);
    }
  }

  Future<void> _takeBackForRequesterFromRegularBottomBar(
    BuildContext context, {
    required PieceColor requesterSide,
  }) async {
    final int? steps = _takeBackStepCountForRequesterOrNull(requesterSide);
    if (steps == null) {
      GameController().headerTipNotifier.showTip(S.of(context).noMove);
      return;
    }
    RecordingService()
        .recordEvent(RecordingEventType.toolbarAction, <String, dynamic>{
          'toolbar': 'regularBottom',
          'action': 'takeBack',
          'requester': requesterSide.name,
          'steps': steps,
        });
    await HistoryNavigator.takeBackN(context, steps, pop: false, toolbar: true);
  }

  bool get _canShowHintFromBottomBar {
    if (!_usesLichessHumanAiToolbar || _activePhase == Phase.gameOver) {
      return false;
    }
    if (AnalysisService.isBestMoveHintSearching || AnalysisMode.isHint) {
      return true;
    }
    final PieceColor sideToMove = GameController().activeBoardView.sideToMove;
    return (sideToMove == PieceColor.white || sideToMove == PieceColor.black) &&
        GameController().gameInstance.isHumanToMove &&
        !GameController().isEngineRunning &&
        !GameController().isEngineInDelay &&
        !AnalysisMode.isAnalyzing;
  }

  bool get _canResignFromRegularBottomBar {
    return !_usesLichessHumanAiToolbar &&
        !_isAiVsAiMode &&
        !_isAnalysisMode &&
        GameController().gameRecorder.currentPath.length >= 2 &&
        _activePhase != Phase.ready &&
        _activePhase != Phase.gameOver;
  }

  bool get _isRegularGameOver {
    return !_usesLichessHumanAiToolbar &&
        !_isAnalysisMode &&
        _activePhase == Phase.gameOver;
  }

  bool get _isHumanAiGameOver {
    return _usesLichessHumanAiToolbar && _activePhase == Phase.gameOver;
  }

  bool get _canStepBackFromRegularBottomBar {
    return !_usesLichessHumanAiToolbar &&
        !GameController().isRemoteGameMode &&
        GameController().gameRecorder.activeNode?.parent != null &&
        !GameController().isEngineRunning &&
        !GameController().isEngineInDelay;
  }

  bool get _canTakeBackFromRegularBottomBar {
    if (_usesLichessHumanAiToolbar || _isAnalysisMode) {
      return false;
    }
    if (GameController().gameRecorder.activeNode?.parent == null ||
        GameController().isEngineRunning ||
        GameController().isEngineInDelay) {
      return false;
    }
    if (GameController().isRemoteGameMode) {
      return _remoteTakeBackStepCountOrNull != null;
    }
    return true;
  }

  bool get _canStepForwardFromRegularBottomBar {
    return !_usesLichessHumanAiToolbar &&
        !GameController().isRemoteGameMode &&
        (GameController().gameRecorder.activeNode ??
                GameController().gameRecorder.pgnRoot)
            .children
            .isNotEmpty &&
        !GameController().isEngineRunning &&
        !GameController().isEngineInDelay;
  }

  Future<void> _transformActiveBoard(
    MillBoardTransformAction action, {
    required S strings,
    GameSession? session,
  }) async {
    final bool refreshAnalysis = _isAnalysisMode;
    if (refreshAnalysis) {
      await AnalysisService.stopActiveEngineAnalysisAndWait();
      AnalysisMode.disable();
      if (!mounted) {
        return;
      }
    }
    final bool transformed = GameController().transformActiveLocalGame(
      action.type,
    );
    if (transformed) {
      if (mounted) {
        setState(() {
          _isBoardFlipped = false;
        });
      }
      if (_usesLichessHumanAiToolbar &&
          GameController().gameInstance.isAiSideToMove) {
        unawaited(
          GameController().engineToGo(
            context,
            isMoveNow: false,
            session: session,
          ),
        );
      }
    }
    if (refreshAnalysis) {
      await AnalysisService.refresh(context);
      if (!mounted) {
        return;
      }
    }
    assert(
      rootScaffoldMessengerKey.currentState != null,
      'Board transform feedback requires the root scaffold messenger.',
    );
    rootScaffoldMessengerKey.currentState!.showSnackBarClear(
      transformed ? strings.transformed : strings.cannotTransform,
    );
  }

  void _replaceMenuWithBoardTransformPicker(
    NavigatorState navigator, {
    required Key sheetKey,
    required String keyPrefix,
    required S strings,
    required String title,
    required String currentBoardLayout,
    GameSession? session,
  }) {
    assert(
      navigator.mounted,
      'Board transform picker requires a mounted navigator.',
    );
    navigator.pushReplacement<void, void>(
      DialogRoute<void>(
        context: navigator.context,
        builder: (BuildContext dialogContext) => _BoardTransformPickerDialog(
          sheetKey: sheetKey,
          keyPrefix: keyPrefix,
          title: title,
          currentBoardLayout: currentBoardLayout,
          backgroundColor: _actionSheetBackground(dialogContext),
          foregroundColor: _actionSheetForeground(dialogContext),
          onSelected: (MillBoardTransformAction action) => unawaited(
            _transformActiveBoard(action, strings: strings, session: session),
          ),
        ),
      ),
    );
  }

  String _activeBoardLayoutForTransformPreview() {
    final String? fen =
        GameController().activeNativeMillSession?.getFen() ??
        GameController().activeFen;
    if (fen != null && fen.length >= 26) {
      return fen.substring(0, 26);
    }

    return _boardLayoutFromBoardView(GameController().activeBoardView);
  }

  String _boardLayoutFromBoardView(MillBoardView view) {
    final StringBuffer buffer = StringBuffer();
    for (int square = 8; square <= 31; square++) {
      if (square == 16 || square == 24) {
        buffer.write('/');
      }
      final int? gridIndex = MillBoardCoordinateMaps.squareToGridIndex[square];
      assert(gridIndex != null, 'Mill square must map to a grid index.');
      final PieceColor piece = view.markedGridIndices.contains(gridIndex)
          ? PieceColor.marked
          : view.pieceOnGrid(gridIndex!);
      buffer.write(piece.string);
    }
    return buffer.toString();
  }

  Future<void> _moveNowFromGameMenu(
    BuildContext context, {
    required String toolbar,
    required MoveNowMessages messages,
    GameSession? session,
  }) async {
    RecordingService().recordEvent(
      RecordingEventType.toolbarAction,
      <String, dynamic>{'toolbar': toolbar, 'action': 'moveNow'},
    );
    await AnalysisService.stopBestMoveHintAndWait();
    if (!context.mounted) {
      return;
    }
    await GameController().moveNow(
      context,
      messages: messages,
      session: session,
    );
  }

  bool get _shouldShowMoveNowMenuAction {
    final GameMode mode = GameController().gameInstance.gameMode;
    return mode == GameMode.humanVsAi || mode == GameMode.aiVsAi;
  }

  /// Whether "Make computer play another move" can currently act:
  /// humanVsAi, no search in flight, and the most recent ply was actually
  /// played by the computer (i.e. it is now the human's turn, mirroring the
  /// precondition of the take-back button so both features stay consistent
  /// about "whose turn is it").
  bool get _canForceAiRedo {
    if (GameController().gameInstance.gameMode != GameMode.humanVsAi) {
      return false;
    }
    if (GameController().isEngineRunning || GameController().isEngineInDelay) {
      return false;
    }
    if (GameController().gameRecorder.currentPath.isEmpty) {
      return false;
    }
    if (GameController().gameInstance.isAiSideToMove) {
      // It is still the AI's turn (or the human hasn't moved yet); there is
      // no AI move to reconsider.
      return false;
    }
    return _takeBackStepCountForRequesterOrNull(
          _humanAiTakeBackRequesterSide.opponent,
        ) !=
        null;
  }

  /// Undoes the AI's last turn (place/move, plus any trailing capture it
  /// made) and lets it search again, excluding the move it just played, so
  /// it commits to a genuinely different choice. If no distinct legal
  /// alternative exists, the original move is restored unchanged and the
  /// user is told there was nothing else to try.
  ///
  /// This is a practice/study aid, not a fairness mechanic: it deliberately
  /// bypasses the opening book / human database lookups that a normal AI
  /// turn consults first, since "try a different move" only makes sense
  /// against the engine's own search.
  Future<void> _forceAiRedoFromGameMenu(BuildContext context) async {
    assert(_usesLichessHumanAiToolbar);
    if (!_canForceAiRedo) {
      return;
    }
    final PieceColor aiColor = _humanAiTakeBackRequesterSide.opponent;
    final int? steps = _takeBackStepCountForRequesterOrNull(aiColor);
    if (steps == null) {
      return;
    }
    final String? originalMove =
        GameController().gameRecorder.currentPath.lastOrNull?.move;
    assert(
      originalMove != null,
      'Force AI redo requires a most-recent move to reconsider.',
    );

    RecordingService().recordEvent(
      RecordingEventType.toolbarAction,
      <String, dynamic>{'toolbar': 'lichessBottom', 'action': 'forceAiRedo'},
    );

    await AnalysisService.stopBestMoveHintAndWait();
    if (!context.mounted) {
      return;
    }
    await LiveEvaluationService.stopAndWait();
    if (!context.mounted) {
      return;
    }
    await HistoryNavigator.takeBackN(context, steps, pop: false, toolbar: true);
    if (!context.mounted) {
      return;
    }

    final NativeMillGameSession? session =
        GameController().activeNativeMillSession;
    if (session == null) {
      return;
    }

    final List<NativeMillPrincipalVariation> variations = await session
        .searchPrincipalVariations(
          depth: 24,
          moveLimitMs: 2000,
          multiPv: 4,
          engineSettings: DB().generalSettings,
        );
    if (!context.mounted) {
      return;
    }
    final NativeMillPrincipalVariation? alternative = variations
        .cast<NativeMillPrincipalVariation?>()
        .firstWhere(
          (NativeMillPrincipalVariation? v) => v!.move != originalMove,
          orElse: () => null,
        );

    if (alternative == null) {
      GameController().headerTipNotifier.showTip(
        S.of(context).aiNoAlternativeMove,
      );
      // Restore exactly what was there before, since we already took the
      // original move back above.
      final NativeMillAiTurnController restoreController =
          NativeMillAiTurnController(
            generalSettings: DB().generalSettings,
            onRootEvaluation: LiveEvaluationService.publishAiRootEvaluation,
            openingBook: MillOpeningBookProvider(
              ruleSettings: DB().ruleSettings,
              generalSettings: DB().generalSettings,
              placementHistory: openingBookPlacementHistory,
            ),
            humanDatabase: MillHumanDatabaseProvider(
              ruleSettings: DB().ruleSettings,
              generalSettings: DB().generalSettings,
            ),
          );
      await restoreController.playIfAiTurn(session);
      unawaited(LiveEvaluationService.requestCurrentPosition());
      return;
    }

    GameAction? action;
    for (final GameAction candidate in session.legalActions) {
      if (MillActionCodec.moveStringFrom(candidate) == alternative.move) {
        action = candidate;
        break;
      }
    }
    assert(action != null, 'Alternative move must still be legal.');
    if (action == null) {
      return;
    }
    await session.apply(action);
    if (session.outcome.isTerminal) {
      LiveEvaluationService.publishTerminalPosition(session);
      return;
    }
    // Consume any trailing removal from the alternative move the same way a
    // normal AI turn would; the removal choice itself does not need to be
    // "forced different" -- only the move that triggered this action does.
    final NativeMillAiTurnController continuation = NativeMillAiTurnController(
      generalSettings: DB().generalSettings,
      onRootEvaluation: LiveEvaluationService.publishAiRootEvaluation,
    );
    await continuation.playIfAiTurn(session);
    unawaited(LiveEvaluationService.requestCurrentPosition());
  }

  Future<void> _showResignConfirmation(BuildContext context) async {
    assert(_usesLichessHumanAiToolbar);
    final bool? confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text(S.of(dialogContext).confirmResignation),
          content: Text(S.of(dialogContext).areYouSureYouWantToResignThisGame),
          actions: <Widget>[
            TextButton(
              key: const Key('play_area_resign_cancel_button'),
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(S.of(dialogContext).cancel),
            ),
            TextButton(
              key: const Key('play_area_resign_confirm_button'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(S.of(dialogContext).resign),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) {
      return;
    }
    RecordingService().recordEvent(
      RecordingEventType.toolbarAction,
      <String, dynamic>{'toolbar': 'lichessBottom', 'action': 'resign'},
    );
    await AnalysisService.stopBestMoveHintAndWait();
    if (!mounted) {
      return;
    }
    GameController().requestResignation();
  }

  /// Score margin (same scale as [NativeMillPrincipalVariation.score]) below
  /// which the AI is willing to accept a draw offer, evaluated from the
  /// AI's own perspective. A small positive tolerance is used rather than
  /// requiring dead equality, since a genuinely balanced position rarely
  /// evaluates to exactly zero.
  static const int _drawOfferAiAcceptThreshold = 10;

  Future<void> _showOfferDrawConfirmation(BuildContext context) async {
    assert(_usesLichessHumanAiToolbar);
    final bool? confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text(S.of(dialogContext).confirmOfferDraw),
          content: Text(S.of(dialogContext).areYouSureYouWantToOfferADraw),
          actions: <Widget>[
            TextButton(
              key: const Key('play_area_offer_draw_cancel_button'),
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(S.of(dialogContext).cancel),
            ),
            TextButton(
              key: const Key('play_area_offer_draw_confirm_button'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(S.of(dialogContext).offerDraw),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !context.mounted) {
      return;
    }
    RecordingService().recordEvent(
      RecordingEventType.toolbarAction,
      <String, dynamic>{'toolbar': 'lichessBottom', 'action': 'offerDraw'},
    );
    await AnalysisService.stopBestMoveHintAndWait();
    if (!context.mounted) {
      return;
    }
    await _resolveDrawOfferVsAi(context);
  }

  Future<void> _resolveDrawOfferVsAi(BuildContext context) async {
    final NativeMillGameSession? session =
        GameController().activeNativeMillSession;
    if (session == null) {
      return;
    }
    await LiveEvaluationService.stopAndWait();
    if (!context.mounted) {
      return;
    }
    final List<NativeMillPrincipalVariation> variations = await session
        .searchPrincipalVariations(
          depth: 18,
          moveLimitMs: 1200,
          multiPv: 1,
          engineSettings: DB().generalSettings,
        );
    if (!context.mounted) {
      return;
    }
    final int sideToMoveScore = variations.isEmpty ? 0 : variations.first.score;
    final PlayerSeat activeSeat = session.state.value.activeSeat;
    if (activeSeat != PlayerSeat.none) {
      LiveEvaluationService.publishAiRootEvaluation(
        session,
        LiveEvaluationService.whitePerspectiveScore(
          activeSeat,
          sideToMoveScore,
        ),
      );
    }
    // `score` is relative to whoever is currently to move, which may be
    // either player depending on when the offer happens; normalise to the
    // AI's own perspective before comparing against the acceptance
    // threshold so the sign is correct regardless of whose turn it is.
    final PieceColor aiColor = _humanAiTakeBackRequesterSide.opponent;
    final PieceColor mover = GameController().activeBoardView.sideToMove;
    final int aiPerspectiveScore = mover == aiColor
        ? sideToMoveScore
        : -sideToMoveScore;
    final bool aiAccepts = aiPerspectiveScore <= _drawOfferAiAcceptThreshold;

    if (!aiAccepts) {
      GameController().headerTipNotifier.showTip(S.of(context).aiDeclinedDraw);
      return;
    }
    GameController().forceGameOver(
      PieceColor.draw,
      GameOverReason.drawAgreement,
    );
    LiveEvaluationService.publishTerminalPosition(session);
    GameController().gameResultNotifier.showResult();
  }

  Future<void> _showOfferDrawConfirmationRegular(BuildContext context) async {
    assert(!_usesLichessHumanAiToolbar);
    final bool? accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text(S.of(dialogContext).offerDraw),
          content: Text(S.of(dialogContext).opponentAcceptDrawPrompt),
          actions: <Widget>[
            TextButton(
              key: const Key('play_area_regular_offer_draw_decline_button'),
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(S.of(dialogContext).decline),
            ),
            TextButton(
              key: const Key('play_area_regular_offer_draw_accept_button'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(S.of(dialogContext).accept),
            ),
          ],
        );
      },
    );
    if (accepted != true || !context.mounted) {
      return;
    }
    RecordingService().recordEvent(
      RecordingEventType.toolbarAction,
      <String, dynamic>{'toolbar': 'regularBottom', 'action': 'offerDraw'},
    );
    GameController().forceGameOver(
      PieceColor.draw,
      GameOverReason.drawAgreement,
    );
    GameController().gameResultNotifier.showResult();
  }

  Future<void> _takeBackFromBottomBar(BuildContext context) async {
    assert(_usesLichessHumanAiToolbar);
    final int? steps = _humanAiTakeBackStepCountOrNull;
    if (steps == null) {
      GameController().headerTipNotifier.showTip(S.of(context).noMove);
      return;
    }
    RecordingService().recordEvent(
      RecordingEventType.toolbarAction,
      <String, dynamic>{
        'toolbar': 'lichessBottom',
        'action': 'takeBack',
        'steps': steps,
      },
    );
    await AnalysisService.stopBestMoveHintAndWait();
    if (!context.mounted) {
      return;
    }
    await HistoryNavigator.takeBackN(context, steps, pop: false, toolbar: true);
  }

  Future<void> _showHintFromBottomBar(BuildContext context) async {
    assert(_usesLichessHumanAiToolbar);
    if (AnalysisService.isBestMoveHintSearching || AnalysisMode.isHint) {
      RecordingService().recordEvent(
        RecordingEventType.toolbarAction,
        <String, dynamic>{'toolbar': 'lichessBottom', 'action': 'hintStop'},
      );
      AnalysisService.stopBestMoveHint();
      return;
    }
    RecordingService().recordEvent(
      RecordingEventType.toolbarAction,
      <String, dynamic>{'toolbar': 'lichessBottom', 'action': 'hint'},
    );
    await AnalysisService.showBestMoveHint(context);
  }

  Future<void> _requestNewGameFromBottomBar(NavigatorState navigator) async {
    assert(_usesLichessHumanAiToolbar);
    RecordingService().recordEvent(
      RecordingEventType.toolbarAction,
      <String, dynamic>{'toolbar': 'lichessBottom', 'action': 'newGame'},
    );
    await AnalysisService.stopBestMoveHintAndWait();
    if (!navigator.mounted) {
      return;
    }
    await GameOptionsModal.showHumanAiNewGameSheet(navigator.context);
  }

  Future<void> _showRegularResignConfirmation(BuildContext context) async {
    assert(!_usesLichessHumanAiToolbar);
    final bool? confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text(S.of(dialogContext).confirmResignation),
          content: Text(S.of(dialogContext).areYouSureYouWantToResignThisGame),
          actions: <Widget>[
            TextButton(
              key: const Key('play_area_regular_resign_cancel_button'),
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(S.of(dialogContext).cancel),
            ),
            TextButton(
              key: const Key('play_area_regular_resign_confirm_button'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(S.of(dialogContext).resign),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) {
      return;
    }
    RecordingService().recordEvent(
      RecordingEventType.toolbarAction,
      <String, dynamic>{'toolbar': 'regularBottom', 'action': 'resign'},
    );
    GameController().requestResignation();
  }

  void _showRegularGameResult() {
    assert(_isRegularGameOver);
    RecordingService().recordEvent(
      RecordingEventType.toolbarAction,
      <String, dynamic>{'toolbar': 'regularBottom', 'action': 'showResult'},
    );
    GameController().gameResultNotifier.showResult(force: true);
  }

  void _showHumanAiGameResult() {
    assert(_isHumanAiGameOver);
    RecordingService().recordEvent(
      RecordingEventType.toolbarAction,
      <String, dynamic>{'toolbar': 'lichessBottom', 'action': 'showResult'},
    );
    GameController().gameResultNotifier.showResult(force: true);
  }

  Future<void> _showAnalysisSettingsSheet(
    BuildContext context, {
    required S strings,
  }) {
    assert(_isAnalysisMode, 'Analysis settings are analysis-mode only.');
    return showAnalysisSettingsSheet(
      _stableActionContext(context),
      strings: strings,
    );
  }

  void _showAnalysisEngineSheet(BuildContext context, {required S strings}) {
    assert(_isAnalysisMode, 'Engine popup is analysis-mode only.');
    final BuildContext sheetContext = _stableActionContext(context);
    final int? depth = _currentAnalysisEngineDepth();
    final int? nodes = _analysisEngineNodes();
    final int? nodesPerSecond = _analysisEngineNodesPerSecond();
    final GameSession? sheetSession =
        GameSessionScope.sessionOf(sheetContext) ??
        GameController().activeNativeMillSession;
    final NativeMillGameSession? nativeSheetSession =
        sheetSession is NativeMillGameSession
        ? sheetSession
        : GameController().activeNativeMillSession;
    final bool canShowThreat =
        nativeSheetSession != null &&
        AnalysisService.canShowThreat(nativeSheetSession);
    showLichessActionSheet<void>(
      context: sheetContext,
      sheetKey: const Key('play_area_analysis_engine_sheet'),
      content: _AnalysisEngineSheetStatus(
        sourceLabel: _analysisSourceLabel(strings),
        depth: depth,
        nodes: nodes,
        nodesPerSecond: nodesPerSecond,
        isAnalyzing: AnalysisMode.isAnalyzing,
        isDeepSearch: AnalysisMode.isEngineAnalysisDeep,
        isThreatMode: AnalysisMode.isThreatMode,
        canGoDeeper:
            !AnalysisMode.isAnalyzing && !AnalysisMode.isEngineAnalysisDeep,
        onGoDeeper: () =>
            unawaited(_goDeeperFromAnalysisEngineSheet(sheetContext)),
      ),
      backgroundColor: _actionSheetBackground(sheetContext),
      foregroundColor: _actionSheetForeground(sheetContext),
      actions: <LichessActionSheetAction>[
        LichessActionSheetAction(
          key: const Key('play_area_analysis_engine_toggle_engine_lines'),
          leading: Icon(
            AnalysisMode.showEngineLines
                ? Icons.subtitles_outlined
                : Icons.subtitles_off_outlined,
          ),
          makeLabel: (BuildContext context) => Text(
            AnalysisMode.showEngineLines
                ? strings.hideEngineLines
                : strings.showEngineLines,
          ),
          onPressed: () =>
              _toggleEngineLinesFromAnalysis(toolbar: 'analysisEngine'),
        ),
        if (canShowThreat)
          LichessActionSheetAction(
            key: const Key('play_area_analysis_engine_show_threat'),
            leading: Icon(
              AnalysisMode.isThreatMode
                  ? Icons.visibility_off_outlined
                  : Icons.online_prediction_outlined,
            ),
            makeLabel: (BuildContext context) =>
                Text(_analysisThreatActionLabel(strings)),
            onPressed: () => unawaited(
              _toggleAnalysisThreatFromAnalysis(
                sheetContext,
                toolbar: 'analysisEngine',
              ),
            ),
          ),
        LichessActionSheetAction(
          key: const Key('play_area_analysis_engine_settings'),
          leading: const Icon(Icons.tune_outlined),
          trailing: const Icon(Icons.chevron_right),
          makeLabel: (BuildContext context) => Text(strings.settings),
          onPressed: () =>
              _showAnalysisSettingsSheet(sheetContext, strings: strings),
        ),
      ],
    );
  }

  Future<void> _goDeeperFromAnalysisEngineSheet(BuildContext context) async {
    assert(_isAnalysisMode, 'Go deeper is analysis-mode only.');
    RecordingService().recordEvent(
      RecordingEventType.toolbarAction,
      <String, dynamic>{'toolbar': 'analysisEngine', 'action': 'goDeeper'},
    );
    await AnalysisService.goDeeper(context);
  }

  void _toggleEngineLinesFromAnalysis({required String toolbar}) {
    assert(_isAnalysisMode, 'Engine line visibility is analysis-mode only.');
    RecordingService()
        .recordEvent(RecordingEventType.toolbarAction, <String, dynamic>{
          'toolbar': toolbar,
          'action': 'toggleEngineLines',
          'visible': !AnalysisMode.showEngineLines,
        });
    AnalysisMode.toggleEngineLines(persist: true);
  }

  int? _currentAnalysisEngineDepth() {
    return _analysisEngineDepth();
  }

  bool get _supportsGameTips {
    return switch (GameController().gameInstance.gameMode) {
      GameMode.humanVsAi ||
      GameMode.humanVsHuman ||
      GameMode.aiVsAi ||
      GameMode.humanVsCloud ||
      GameMode.humanVsLAN ||
      GameMode.humanVsBluetooth ||
      GameMode.testViaLAN => true,
      GameMode.setupPosition || GameMode.puzzle || GameMode.analysis => false,
    };
  }

  bool _toggleGameTips({required String toolbar}) {
    assert(_supportsGameTips, 'Game tips require a playable game mode.');
    final GeneralSettings current = DB().generalSettings;
    final bool enabled = !current.showGameTips;
    DB().generalSettings = current.copyWith(showGameTips: enabled);
    final GameController controller = GameController();
    controller.headerIconsNotifier.showIcons();
    RecordingService().recordEvent(
      RecordingEventType.toolbarAction,
      <String, dynamic>{
        'toolbar': toolbar,
        'action': 'toggleGameTips',
        'enabled': enabled,
      },
    );

    if (!enabled) {
      final HeaderTipNotifier notifier = controller.headerTipNotifier;
      notifier.showTip(notifier.message, snackBar: false, kind: notifier.kind);
      return enabled;
    }
    final NativeMillGameSession? session = controller.activeNativeMillSession;
    final BuildContext? refreshContext = mounted
        ? context
        : rootScaffoldMessengerKey.currentContext;
    if (session != null && refreshContext != null && refreshContext.mounted) {
      controller.refreshNativeSessionHeader(refreshContext, session);
    }
    return enabled;
  }

  LichessActionSheetAction _gameTipsMenuAction({
    required Key key,
    required String toolbar,
  }) {
    assert(_supportsGameTips, 'Game tips require a playable game mode.');
    final ValueNotifier<bool> enabled = ValueNotifier<bool>(
      DB().generalSettings.showGameTips,
    );
    return LichessActionSheetAction(
      key: key,
      dismissOnPress: false,
      makeLabel: (BuildContext context) => _GameTipsActionLabel(enabled),
      onPressed: () {
        enabled.value = _toggleGameTips(toolbar: toolbar);
      },
    );
  }

  void _showOfflineBoardGameMenu() {
    assert(_isOfflineBoardMode);
    final BuildContext hostContext = context;
    final BuildContext actionContext = _stableActionContext(hostContext);
    final S strings = S.of(hostContext);
    final NavigatorState navigator = Navigator.of(hostContext);
    final GameSession? hostSession =
        GameSessionScope.sessionOf(hostContext) ??
        GameController().activeNativeMillSession;
    final bool hasMoveHistory =
        GameController().gameRecorder.moveCountNotifier.value > 0;
    final String boardTransformLayout = _activeBoardLayoutForTransformPreview();
    showLichessActionSheet<void>(
      context: hostContext,
      sheetKey: const Key('play_area_offline_board_menu_sheet'),
      backgroundColor: _actionSheetBackground(hostContext),
      foregroundColor: _actionSheetForeground(hostContext),
      actions: <LichessActionSheetAction>[
        LichessActionSheetAction(
          key: const Key('play_area_offline_board_menu_new_game'),
          leading: const Icon(Icons.add_circle_outline),
          makeLabel: (BuildContext context) =>
              Text(strings.offlineBoardNewGame),
          onPressed: () => _requestRegularNewGame(navigator),
        ),
        LichessActionSheetAction(
          key: const Key('play_area_offline_board_menu_flip_board'),
          leading: const Icon(Icons.flip_camera_android_outlined),
          trailing: const Icon(Icons.chevron_right),
          dismissOnPress: false,
          makeLabel: (BuildContext context) =>
              Text(strings.offlineBoardFlipBoard),
          onPressed: () {},
          onPressedWithContext: (BuildContext menuActionContext) =>
              _replaceMenuWithBoardTransformPicker(
                Navigator.of(menuActionContext),
                sheetKey: const Key('play_area_offline_board_transform_sheet'),
                keyPrefix: 'play_area_offline_board_transform',
                strings: strings,
                title: strings.offlineBoardFlipBoard,
                currentBoardLayout: boardTransformLayout,
                session: hostSession,
              ),
        ),
        if (hasMoveHistory)
          LichessActionSheetAction(
            key: const Key('play_area_offline_board_menu_share_export'),
            leading: const Icon(Icons.ios_share_outlined),
            trailing: const Icon(Icons.chevron_right),
            makeLabel: (BuildContext context) => Text(strings.shareAndExport),
            onPressed: () => _showCurrentGameShareExportMenu(
              actionContext,
              toolbar: 'offlineBoardMenu',
            ),
          ),
        _gameTipsMenuAction(
          key: const Key('play_area_offline_board_menu_game_tips'),
          toolbar: 'offlineBoardMenu',
        ),
        LichessActionSheetAction(
          key: const Key('play_area_offline_board_menu_marker_guide'),
          leading: const Icon(Icons.help_outline),
          makeLabel: (BuildContext context) => Text(strings.boardMarkerGuide),
          onPressed: () => showBoardMarkerGuide(actionContext),
        ),
        if (_isRegularGameOver)
          LichessActionSheetAction(
            key: const Key('play_area_offline_board_menu_result'),
            leading: const Icon(Icons.info_outline),
            makeLabel: (BuildContext context) => Text(strings.results),
            onPressed: _showRegularGameResult,
          )
        else ...<LichessActionSheetAction>[
          if (_canOfferDrawFromRegularBottomBar)
            LichessActionSheetAction(
              key: const Key('play_area_offline_board_menu_offer_draw'),
              leading: const Icon(Icons.handshake_outlined),
              makeLabel: (BuildContext context) => Text(strings.offerDraw),
              onPressed: () =>
                  unawaited(_showOfferDrawConfirmationRegular(actionContext)),
            ),
          if (_canResignFromRegularBottomBar)
            LichessActionSheetAction(
              key: const Key('play_area_offline_board_menu_resign'),
              leading: const Icon(CupertinoIcons.flag),
              makeLabel: (BuildContext context) => Text(strings.resign),
              onPressed: () =>
                  unawaited(_showRegularResignConfirmation(actionContext)),
            ),
        ],
      ],
    );
  }

  void _showRegularGameMenu() {
    assert(!_usesLichessHumanAiToolbar);
    if (_isOfflineBoardMode) {
      _showOfflineBoardGameMenu();
      return;
    }
    if (_isAnalysisMode) {
      _showAnalysisMenu();
      return;
    }
    final BuildContext hostContext = context;
    final BuildContext actionContext = _stableActionContext(hostContext);
    final S strings = S.of(hostContext);
    final MoveNowMessages moveNowMessages = MoveNowMessages.of(hostContext);
    final NavigatorState hostNavigator = Navigator.of(hostContext);
    final GameSession? hostSession =
        GameSessionScope.sessionOf(hostContext) ??
        GameController().activeNativeMillSession;
    final NativeMillGameSession? nativeHostSession =
        hostSession is NativeMillGameSession
        ? hostSession
        : GameController().activeNativeMillSession;
    assert(
      !_isAnalysisMode || nativeHostSession != null,
      'Analysis menu requires a native Mill session.',
    );
    final String boardTransformLayout = _activeBoardLayoutForTransformPreview();
    showLichessActionSheet<void>(
      context: hostContext,
      sheetKey: const Key('play_area_regular_game_menu_sheet'),
      backgroundColor: _actionSheetBackground(hostContext),
      foregroundColor: _actionSheetForeground(hostContext),
      actions: <LichessActionSheetAction>[
        if (_isAnalysisMode &&
            nativeHostSession != null &&
            AnalysisService.canShowThreat(nativeHostSession))
          LichessActionSheetAction(
            key: const Key('play_area_regular_game_menu_show_threat'),
            leading: Icon(
              AnalysisMode.isThreatMode
                  ? Icons.visibility_off_outlined
                  : Icons.online_prediction_outlined,
            ),
            makeLabel: (BuildContext context) =>
                Text(_analysisThreatActionLabel(strings)),
            onPressed: () => unawaited(
              _toggleAnalysisThreatFromAnalysis(
                actionContext,
                toolbar: 'analysisMenu',
              ),
            ),
          ),
        LichessActionSheetAction(
          key: const Key('play_area_regular_game_menu_flip_board'),
          leading: const Icon(Icons.flip_camera_android_outlined),
          trailing: const Icon(Icons.chevron_right),
          dismissOnPress: false,
          makeLabel: (BuildContext context) => Text(S.of(context).flipBoard),
          onPressed: () {},
          onPressedWithContext: (BuildContext menuActionContext) =>
              _replaceMenuWithBoardTransformPicker(
                Navigator.of(menuActionContext),
                sheetKey: const Key('play_area_regular_board_transform_sheet'),
                keyPrefix: 'play_area_regular_board_transform',
                strings: strings,
                title: strings.flipBoard,
                currentBoardLayout: boardTransformLayout,
                session: hostSession,
              ),
        ),
        if (!_isAnalysisMode && _supportsGameTips)
          _gameTipsMenuAction(
            key: const Key('play_area_regular_game_menu_game_tips'),
            toolbar: 'regularGameMenu',
          ),
        if (!_isAnalysisMode)
          LichessActionSheetAction(
            key: const Key('play_area_toolbar_item_game'),
            leading: const Icon(Icons.add_circle_outline),
            makeLabel: (BuildContext context) => Text(S.of(context).newGame),
            onPressed: () => _requestRegularNewGame(hostNavigator),
          ),
        if (!_isAnalysisMode)
          LichessActionSheetAction(
            key: const Key('play_area_toolbar_item_move'),
            leading: const Icon(Icons.format_list_numbered),
            makeLabel: (BuildContext context) => Text(S.of(context).moveList),
            onPressed: () => _openMovesWithNavigator(hostNavigator),
          ),
        if (_isAnalysisMode)
          LichessActionSheetAction(
            key: const Key('play_area_analysis_game_menu_move_list'),
            leading: const Icon(Icons.format_list_numbered),
            makeLabel: (BuildContext context) => Text(S.of(context).moveList),
            onPressed: () => _openMovesWithNavigator(hostNavigator),
          ),
        if (_isAnalysisMode)
          LichessActionSheetAction(
            key: const Key('play_area_regular_game_menu_board_editor'),
            leading: const Icon(Icons.dashboard_customize_outlined),
            makeLabel: (BuildContext context) =>
                Text(S.of(context).boardEditor),
            onPressed: _openBoardEditorFromAnalysis,
          ),
        if (_isAnalysisMode && nativeHostSession != null)
          LichessActionSheetAction(
            key: const Key('play_area_regular_game_menu_continue_from_here'),
            leading: const Icon(Icons.play_circle_outline),
            trailing: const Icon(Icons.chevron_right),
            makeLabel: (BuildContext context) =>
                Text(S.of(context).continueFromHere),
            onPressed: () => _showContinueFromHereMenu(
              actionContext,
              session: nativeHostSession,
              navigator: hostNavigator,
              strings: strings,
            ),
          ),
        if (_isAnalysisMode)
          LichessActionSheetAction(
            key: const Key('play_area_regular_game_menu_share_export'),
            leading: const Icon(Icons.ios_share_outlined),
            trailing: const Icon(Icons.chevron_right),
            makeLabel: (BuildContext context) => Text(strings.shareAndExport),
            onPressed: () =>
                _showAnalysisShareExportMenu(actionContext, strings: strings),
          ),
        LichessActionSheetAction(
          key: const Key('play_area_regular_game_menu_marker_guide'),
          leading: const Icon(Icons.help_outline),
          makeLabel: (BuildContext context) => Text(strings.boardMarkerGuide),
          onPressed: () => showBoardMarkerGuide(actionContext),
        ),
        if (_shouldShowMoveNowMenuAction)
          LichessActionSheetAction(
            key: const Key('play_area_regular_game_menu_move_now'),
            leading: const Icon(FluentIcons.play_24_regular),
            makeLabel: (BuildContext context) => Text(S.of(context).moveNow),
            onPressed: () => unawaited(
              _moveNowFromGameMenu(
                actionContext,
                toolbar: 'regularBottom',
                messages: moveNowMessages,
                session: hostSession,
              ),
            ),
          ),
        if (_shouldShowAiChatMenuAction)
          LichessActionSheetAction(
            key: const Key('play_area_regular_game_menu_ai_chat'),
            leading: const Icon(Icons.auto_graph),
            makeLabel: (BuildContext context) =>
                Text(S.of(context).aiAnalysisTitle),
            onPressed: () => _showAiChatDialog(actionContext),
          ),
        if (_canTakeBackFromRegularBottomBar)
          LichessActionSheetAction(
            key: const Key('play_area_regular_game_menu_take_back'),
            leading: const Icon(CupertinoIcons.arrow_uturn_left),
            makeLabel: (BuildContext context) => Text(S.of(context).takeBack),
            onPressed: () =>
                unawaited(_takeBackFromRegularBottomBar(actionContext)),
          ),
        if (_isRegularGameOver)
          LichessActionSheetAction(
            key: const Key('play_area_regular_game_menu_result'),
            leading: const Icon(Icons.info_outline),
            makeLabel: (BuildContext context) => Text(S.of(context).results),
            onPressed: _showRegularGameResult,
          )
        else ...<LichessActionSheetAction>[
          if (_canOfferDrawFromRegularBottomBar)
            LichessActionSheetAction(
              key: const Key('play_area_regular_game_menu_offer_draw'),
              leading: const Icon(Icons.handshake_outlined),
              makeLabel: (BuildContext context) =>
                  Text(S.of(context).offerDraw),
              onPressed: () =>
                  unawaited(_showOfferDrawConfirmationRegular(actionContext)),
            ),
          if (_canResignFromRegularBottomBar)
            LichessActionSheetAction(
              key: const Key('play_area_regular_game_menu_resign'),
              leading: const Icon(CupertinoIcons.flag),
              makeLabel: (BuildContext context) => Text(S.of(context).resign),
              onPressed: () =>
                  unawaited(_showRegularResignConfirmation(actionContext)),
            ),
        ],
        LichessActionSheetAction(
          key: const Key('play_area_toolbar_item_info'),
          leading: const Icon(Icons.info_outline),
          makeLabel: (BuildContext context) => Text(S.of(context).info),
          onPressed: () => _openDialog(actionContext, const InfoDialog()),
        ),
        LichessActionSheetAction(
          key: const Key('play_area_toolbar_item_options'),
          leading: const Icon(Icons.settings_outlined),
          makeLabel: (BuildContext context) => Text(
            _isAnalysisMode ? S.of(context).settings : S.of(context).options,
          ),
          onPressed: () => _navigateToSettings(actionContext),
        ),
      ],
    );
  }

  void _showAnalysisMenu() {
    assert(_isAnalysisMode, 'Analysis menu is analysis-mode only.');
    final BuildContext hostContext = context;
    final BuildContext actionContext = _stableActionContext(hostContext);
    final S strings = S.of(hostContext);
    final NavigatorState hostNavigator = Navigator.of(hostContext);
    final GameSession? scopedSession = GameSessionScope.sessionOf(hostContext);
    final NativeMillGameSession? session =
        scopedSession is NativeMillGameSession
        ? scopedSession
        : GameController().activeNativeMillSession;
    assert(session != null, 'Analysis menu requires a native Mill session.');
    if (session == null) {
      return;
    }
    final String boardTransformLayout = _activeBoardLayoutForTransformPreview();

    showLichessActionSheet<void>(
      context: hostContext,
      sheetKey: const Key('play_area_analysis_menu_sheet'),
      backgroundColor: _actionSheetBackground(hostContext),
      foregroundColor: _actionSheetForeground(hostContext),
      actions: <LichessActionSheetAction>[
        LichessActionSheetAction(
          key: const Key('play_area_analysis_menu_clear_moves'),
          makeLabel: (BuildContext context) => Text(strings.clearAnalysisMoves),
          onPressed: () => unawaited(_clearAnalysisMoves(session)),
        ),
        LichessActionSheetAction(
          key: const Key('play_area_analysis_menu_variant'),
          makeLabel: (BuildContext context) => Text(strings.variant),
          onPressed: () => unawaited(_showAnalysisVariantPicker(session)),
        ),
        if (AnalysisService.canShowThreat(session))
          LichessActionSheetAction(
            key: const Key('play_area_analysis_menu_show_threat'),
            makeLabel: (BuildContext context) =>
                Text(_analysisThreatActionLabel(strings)),
            onPressed: () => unawaited(
              _toggleAnalysisThreatFromAnalysis(
                actionContext,
                toolbar: 'analysisMenu',
              ),
            ),
          ),
        LichessActionSheetAction(
          key: const Key('play_area_analysis_menu_flip_board'),
          trailing: const Icon(Icons.chevron_right),
          dismissOnPress: false,
          makeLabel: (BuildContext context) => Text(strings.flipBoard),
          onPressed: () {},
          onPressedWithContext: (BuildContext menuActionContext) =>
              _replaceMenuWithBoardTransformPicker(
                Navigator.of(menuActionContext),
                sheetKey: const Key('play_area_regular_board_transform_sheet'),
                keyPrefix: 'play_area_regular_board_transform',
                strings: strings,
                title: strings.flipBoard,
                currentBoardLayout: boardTransformLayout,
                session: session,
              ),
        ),
        LichessActionSheetAction(
          key: const Key('play_area_analysis_game_menu_move_list'),
          makeLabel: (BuildContext context) => Text(strings.moveList),
          onPressed: () => _openMovesWithNavigator(hostNavigator),
        ),
        LichessActionSheetAction(
          key: const Key('play_area_analysis_menu_board_editor'),
          makeLabel: (BuildContext context) => Text(strings.boardEditor),
          onPressed: () => unawaited(_openBoardEditorFromAnalysis()),
        ),
        LichessActionSheetAction(
          key: const Key('play_area_analysis_menu_continue_from_here'),
          makeLabel: (BuildContext context) => Text(strings.continueFromHere),
          onPressed: () => _showContinueFromHereMenu(
            actionContext,
            session: session,
            navigator: hostNavigator,
            strings: strings,
          ),
        ),
        LichessActionSheetAction(
          key: const Key('play_area_analysis_menu_share_export'),
          makeLabel: (BuildContext context) => Text(strings.shareAndExport),
          onPressed: () =>
              _showAnalysisShareExportMenu(actionContext, strings: strings),
        ),
      ],
    );
  }

  Future<void> _clearAnalysisMoves(NativeMillGameSession session) async {
    assert(_isAnalysisMode, 'Clearing moves is analysis-mode only.');
    RecordingService().recordEvent(
      RecordingEventType.toolbarAction,
      <String, dynamic>{'toolbar': 'analysisMenu', 'action': 'clearMoves'},
    );
    await AnalysisService.stopActiveEngineAnalysisAndWait();
    if (!mounted) {
      return;
    }
    GameController().annotationManager.clear();
    GameController().startNewAnalysis(session: session);
    _lastAnalysisRefreshNode = null;
    await AnalysisService.refresh(context);
    if (!mounted) {
      return;
    }
    rootScaffoldMessengerKey.currentState?.showSnackBarClear(
      S.of(context).analysisMovesCleared,
    );
  }

  Future<void> _showAnalysisVariantPicker(NativeMillGameSession session) async {
    assert(_isAnalysisMode, 'Variant picker is analysis-mode only.');
    final String? currentId = RuleVariant.exactCanonicalIdFor(
      DB().ruleSettings,
    );
    final String? selectedId = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      builder: (BuildContext sheetContext) {
        final S strings = S.of(sheetContext);
        return SafeArea(
          top: false,
          child: ListView(
            shrinkWrap: true,
            children: <Widget>[
              for (final String id in RuleVariant.canonicalSettings.keys)
                ListTile(
                  key: Key('play_area_analysis_variant_$id'),
                  selected: id == currentId,
                  title: Text(localizedMillVariantNameById(strings, id)),
                  trailing: id == currentId
                      ? const Icon(Icons.check_rounded)
                      : null,
                  onTap: () => Navigator.of(sheetContext).pop(id),
                ),
            ],
          ),
        );
      },
    );
    if (selectedId == null || selectedId == currentId || !mounted) {
      return;
    }

    RecordingService().recordEvent(
      RecordingEventType.toolbarAction,
      <String, dynamic>{
        'toolbar': 'analysisMenu',
        'action': 'setVariant',
        'variant': selectedId,
      },
    );
    await AnalysisService.stopActiveEngineAnalysisAndWait();
    if (!mounted) {
      return;
    }
    DB().ruleSettings = RuleVariant.canonicalSettings[selectedId]!;
    GameController().annotationManager.clear();
    GameController().startNewAnalysis(session: session);
    _lastAnalysisRefreshNode = null;
    await AnalysisService.refresh(context);
  }

  void _showHumanAiGameMenu() {
    assert(_usesLichessHumanAiToolbar);
    final BuildContext hostContext = context;
    final BuildContext actionContext = _stableActionContext(hostContext);
    final S strings = S.of(hostContext);
    final MoveNowMessages moveNowMessages = MoveNowMessages.of(hostContext);
    final NavigatorState hostNavigator = Navigator.of(hostContext);
    final GameSession? hostSession =
        GameSessionScope.sessionOf(hostContext) ??
        GameController().activeNativeMillSession;
    final bool canOpenCurrentPositionInExplorer =
        hostSession is NativeMillGameSession &&
        RuleVariant.openingBookVariantIdFor(
              GameController().ruleSettingsForActiveBoard,
            ) !=
            null;
    final bool hasMoveHistory =
        GameController().gameRecorder.moveCountNotifier.value > 0;
    final String boardTransformLayout = _activeBoardLayoutForTransformPreview();
    showLichessActionSheet<void>(
      context: hostContext,
      sheetKey: const Key('play_area_game_menu_sheet'),
      backgroundColor: _actionSheetBackground(hostContext),
      foregroundColor: _actionSheetForeground(hostContext),
      actions: <LichessActionSheetAction>[
        LichessActionSheetAction(
          key: const Key('play_area_game_menu_flip_board'),
          leading: const Icon(Icons.flip_camera_android_outlined),
          trailing: const Icon(Icons.chevron_right),
          dismissOnPress: false,
          makeLabel: (BuildContext context) => Text(S.of(context).flipBoard),
          onPressed: () {},
          onPressedWithContext: (BuildContext menuActionContext) =>
              _replaceMenuWithBoardTransformPicker(
                Navigator.of(menuActionContext),
                sheetKey: const Key('play_area_board_transform_sheet'),
                keyPrefix: 'play_area_board_transform',
                strings: strings,
                title: strings.flipBoard,
                currentBoardLayout: boardTransformLayout,
                session: hostSession,
              ),
        ),
        LichessActionSheetAction(
          key: const Key('play_area_game_menu_move_list'),
          leading: const Icon(Icons.format_list_numbered),
          makeLabel: (BuildContext context) => Text(S.of(context).moveList),
          onPressed: () => _openMovesWithNavigator(hostNavigator),
        ),
        if (canOpenCurrentPositionInExplorer)
          LichessActionSheetAction(
            key: const Key('play_area_game_menu_opening_explorer'),
            leading: const Icon(Icons.explore_outlined),
            makeLabel: (BuildContext context) =>
                Text(S.of(context).openingExplorer),
            onPressed: () => _openCurrentPositionInExplorer(
              navigator: hostNavigator,
              session: hostSession,
            ),
          ),
        if (hasMoveHistory)
          LichessActionSheetAction(
            key: const Key('play_area_game_menu_share_export'),
            leading: const Icon(Icons.ios_share_outlined),
            trailing: const Icon(Icons.chevron_right),
            makeLabel: (BuildContext context) =>
                Text(S.of(context).shareAndExport),
            onPressed: () => _showCurrentGameShareExportMenu(
              actionContext,
              toolbar: 'humanAiGameMenu',
            ),
          ),
        _gameTipsMenuAction(
          key: const Key('play_area_game_menu_game_tips'),
          toolbar: 'humanAiGameMenu',
        ),
        LichessActionSheetAction(
          key: const Key('play_area_game_menu_marker_guide'),
          leading: const Icon(Icons.help_outline),
          makeLabel: (BuildContext context) => Text(strings.boardMarkerGuide),
          onPressed: () => showBoardMarkerGuide(actionContext),
        ),
        if (_shouldShowMoveNowMenuAction)
          LichessActionSheetAction(
            key: const Key('play_area_game_menu_move_now'),
            leading: const Icon(FluentIcons.play_24_regular),
            makeLabel: (BuildContext context) => Text(S.of(context).moveNow),
            onPressed: () => unawaited(
              _moveNowFromGameMenu(
                actionContext,
                toolbar: 'lichessBottom',
                messages: moveNowMessages,
                session: hostSession,
              ),
            ),
          ),
        if (_canForceAiRedo)
          LichessActionSheetAction(
            key: const Key('play_area_game_menu_force_ai_redo'),
            leading: const Icon(Icons.refresh_rounded),
            makeLabel: (BuildContext context) =>
                Text(S.of(context).forceAiRedo),
            onPressed: () => unawaited(_forceAiRedoFromGameMenu(actionContext)),
          ),
        if (_shouldShowAiChatMenuAction)
          LichessActionSheetAction(
            key: const Key('play_area_game_menu_ai_chat'),
            leading: const Icon(Icons.auto_graph),
            makeLabel: (BuildContext context) =>
                Text(S.of(context).aiAnalysisTitle),
            onPressed: () => _showAiChatDialog(actionContext),
          ),
        if (_isHumanAiGameOver)
          LichessActionSheetAction(
            key: const Key('play_area_game_menu_result'),
            leading: const Icon(Icons.info_outline),
            makeLabel: (BuildContext context) => Text(S.of(context).results),
            onPressed: _showHumanAiGameResult,
          )
        else ...<LichessActionSheetAction>[
          if (_canOfferDrawFromBottomBar)
            LichessActionSheetAction(
              key: const Key('play_area_game_menu_offer_draw'),
              leading: const Icon(Icons.handshake_outlined),
              makeLabel: (BuildContext context) =>
                  Text(S.of(context).offerDraw),
              onPressed: () =>
                  unawaited(_showOfferDrawConfirmation(actionContext)),
            ),
          if (_canResignFromBottomBar)
            LichessActionSheetAction(
              key: const Key('play_area_game_menu_resign'),
              leading: const Icon(CupertinoIcons.flag),
              makeLabel: (BuildContext context) => Text(S.of(context).resign),
              onPressed: () =>
                  unawaited(_showResignConfirmation(actionContext)),
            ),
        ],
        LichessActionSheetAction(
          key: const Key('play_area_game_menu_new_game'),
          leading: const Icon(Icons.add_circle_outline),
          makeLabel: (BuildContext context) => Text(S.of(context).newGame),
          onPressed: () =>
              unawaited(_requestNewGameFromBottomBar(hostNavigator)),
        ),
      ],
    );
  }

  void _openCurrentPositionInExplorer({
    required NavigatorState navigator,
    required GameSession session,
  }) {
    assert(
      session is NativeMillGameSession,
      'Opening explorer requires a native Mill game session.',
    );
    assert(
      RuleVariant.openingBookVariantIdFor(
            GameController().ruleSettingsForActiveBoard,
          ) !=
          null,
      'Opening explorer requires a supported canonical rule set.',
    );
    RecordingService().recordEvent(
      RecordingEventType.toolbarAction,
      <String, dynamic>{
        'toolbar': 'humanAiGameMenu',
        'action': 'openingExplorer',
      },
    );
    navigator.push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: '/currentPositionExplorer'),
        builder: (BuildContext context) =>
            OpeningExplorerPage(session: session, startFromSession: true),
      ),
    );
  }

  void _showCurrentGameShareExportMenu(
    BuildContext context, {
    required String toolbar,
  }) {
    assert(!_isAnalysisMode, 'Live-game sharing is unavailable in analysis.');
    final BuildContext actionContext = _stableActionContext(context);
    final S strings = S.of(actionContext);
    final GameRecorder recorder = GameController().gameRecorder;
    assert(
      recorder.moveCountNotifier.value > 0,
      'Live-game sharing requires at least one recorded move.',
    );
    if (recorder.moveCountNotifier.value <= 0) {
      return;
    }

    showLichessActionSheet<void>(
      context: actionContext,
      sheetKey: const Key('play_area_game_share_export_sheet'),
      title: Text(strings.shareAndExport),
      backgroundColor: _actionSheetBackground(actionContext),
      foregroundColor: _actionSheetForeground(actionContext),
      actions: <LichessActionSheetAction>[
        LichessActionSheetAction(
          key: const Key('play_area_game_share_export_save'),
          leading: const Icon(FluentIcons.save_24_regular),
          makeLabel: (BuildContext context) => Text(strings.saveGame),
          onPressed: () =>
              unawaited(GameController.save(actionContext, shouldPop: false)),
        ),
        LichessActionSheetAction(
          key: const Key('play_area_game_share_export_copy'),
          leading: const Icon(Icons.content_copy_outlined),
          makeLabel: (BuildContext context) =>
              Text(strings.copyGameToClipboard),
          onPressed: () =>
              unawaited(GameController.export(actionContext, shouldPop: false)),
        ),
        LichessActionSheetAction(
          key: const Key('play_area_game_share_export_share'),
          leading: const Icon(Icons.ios_share_outlined),
          makeLabel: (BuildContext context) => Text(strings.sharePgn),
          onPressed: () => unawaited(_shareCurrentGamePgn(toolbar: toolbar)),
        ),
      ],
    );
  }

  Future<void> _shareCurrentGamePgn({required String toolbar}) async {
    assert(!_isAnalysisMode, 'Live-game sharing is unavailable in analysis.');
    final GameRecorder recorder = GameController().gameRecorder;
    final String moveText = recorder.hasVariations()
        ? recorder.moveHistoryText
        : recorder.moveHistoryTextWithoutVariations;
    assert(
      moveText.trim().isNotEmpty,
      'Live-game sharing requires at least one recorded move.',
    );
    if (moveText.trim().isEmpty) {
      return;
    }

    DiagnosticReplayGuard.requireAllowed('Game sharing');
    RecordingService().recordEvent(
      RecordingEventType.toolbarAction,
      <String, dynamic>{'toolbar': toolbar, 'action': 'sharePgn'},
    );
    final String originalPgn = ImportService.addTagPairs(moveText);
    final String pgn =
        ExportService.reviewedPgnForExport(originalPgn) ?? originalPgn;
    await SharePlus.instance.share(ShareParams(text: pgn, subject: 'Game PGN'));
  }

  /// Builds the move modal bottom sheet.
  Widget _buildMoveModal(BuildContext context) {
    return MoveOptionsModal(mainContext: context);
  }

  /// Returns a string of '●' characters based on [count].
  String _getPiecesText(int count) {
    return "●" * count;
  }

  Color _boardPieceColor(PieceColor side) {
    return side == PieceColor.white
        ? DB().colorSettings.whitePieceColor
        : DB().colorSettings.blackPieceColor;
  }

  /// Builds Black's piece-status row for the unflipped board.
  ///
  /// The layouts swap the two fixed-color rows when the board is flipped. This
  /// keeps every reserve and captured-piece group next to its matching player
  /// instead of tying the display to human/computer preferences that do not
  /// apply to over-the-board, network, analysis, or puzzle positions.
  Widget _buildPieceCountRow() {
    final MillBoardView view = GameController().activeBoardView;
    final int blackInHand = view.pieceInHandCountFor(PieceColor.black);
    final int whiteOnBoard = view.pieceOnBoardCountFor(PieceColor.white);
    final int whiteInHand = view.pieceInHandCountFor(PieceColor.white);
    final int whiteRemoved =
        GameController().ruleSettingsForActiveBoard.piecesCount -
        whiteInHand -
        whiteOnBoard;
    return Row(
      key: const Key('play_area_piece_count_row'),
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        Semantics(
          label: S.of(context).inHand(S.of(context).player2, blackInHand),
          excludeSemantics: true,
          child: Text(
            _getPiecesText(blackInHand),
            key: const Key('play_area_piece_count_text_hand'),
            style: TextStyle(
              color: _boardPieceColor(PieceColor.black),
              shadows: const <Shadow>[
                Shadow(
                  offset: Offset(1.0, 1.0),
                  blurRadius: 3.0,
                  color: Color.fromARGB(255, 128, 128, 128),
                ),
              ],
            ),
          ),
        ),
        Semantics(
          label: S
              .of(context)
              .piecesRemoved(S.of(context).player1, whiteRemoved),
          excludeSemantics: true,
          child: Text(
            _getPiecesText(whiteRemoved),
            key: const Key('play_area_piece_count_text_remaining'),
            style: TextStyle(
              color: _boardPieceColor(PieceColor.white).withValues(alpha: 0.8),
              shadows: const <Shadow>[
                Shadow(
                  offset: Offset(1.0, 1.0),
                  blurRadius: 3.0,
                  color: Color.fromARGB(255, 128, 128, 128),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Builds the row displaying the removed piece count (if enabled).
  Widget _buildRemovedPieceCountRow() {
    final MillBoardView view = GameController().activeBoardView;
    final int blackOnBoard = view.pieceOnBoardCountFor(PieceColor.black);
    final int blackInHand = view.pieceInHandCountFor(PieceColor.black);
    final int whiteInHand = view.pieceInHandCountFor(PieceColor.white);
    final int blackRemoved =
        GameController().ruleSettingsForActiveBoard.piecesCount -
        blackInHand -
        blackOnBoard;
    return Row(
      key: const Key('play_area_removed_piece_count_row'),
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        Semantics(
          label: S
              .of(context)
              .piecesRemoved(S.of(context).player2, blackRemoved),
          excludeSemantics: true,
          child: Text(
            _getPiecesText(blackRemoved),
            key: const Key('play_area_removed_piece_count_text_remaining'),
            style: TextStyle(
              color: _boardPieceColor(PieceColor.black).withValues(alpha: 0.8),
              shadows: const <Shadow>[
                Shadow(
                  offset: Offset(1.0, 1.0),
                  blurRadius: 3.0,
                  color: Color.fromARGB(255, 128, 128, 128),
                ),
              ],
            ),
          ),
        ),
        Semantics(
          label: S.of(context).inHand(S.of(context).player1, whiteInHand),
          excludeSemantics: true,
          child: Text(
            _getPiecesText(whiteInHand),
            key: const Key('play_area_removed_piece_count_text_hand'),
            style: TextStyle(
              color: _boardPieceColor(PieceColor.white),
              shadows: const <Shadow>[
                Shadow(
                  offset: Offset(1.0, 1.0),
                  blurRadius: 3.0,
                  color: Color.fromARGB(255, 128, 128, 128),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBoardScreenshot({bool includeAdvantageIndicator = true}) {
    final GameMode mode = GameController().gameInstance.gameMode;
    final bool isGameSurface =
        mode != GameMode.setupPosition && mode != GameMode.puzzle;
    final bool showAdvantageIndicator =
        includeAdvantageIndicator &&
        isGameSurface &&
        DB().displaySettings.isPositionalAdvantageIndicatorShown;
    final int advantageValue = advantageData.isEmpty
        ? _getCurrentAdvantageValue()
        : advantageData.last;
    return NativeScreenshot(
      key: const Key('play_area_native_screenshot'),
      controller: ScreenshotService.screenshotController,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          assert(
            constraints.hasBoundedWidth && constraints.hasBoundedHeight,
            'The game board requires bounded screenshot dimensions.',
          );
          final double reserve = showAdvantageIndicator
              ? _kAdvantageIndicatorReserve
              : 0;
          final double boardSize = math.min(
            constraints.maxHeight,
            math.max(0, constraints.maxWidth - reserve),
          );
          final Widget board = SizedBox.square(
            dimension: boardSize,
            child: Container(
              key: const Key('play_area_game_board_container'),
              alignment: Alignment.center,
              child: RotatedBox(
                key: const Key('play_area_board_orientation'),
                quarterTurns: _isBoardFlipped ? 2 : 0,
                child: widget.child,
              ),
            ),
          );
          if (!showAdvantageIndicator) {
            return Center(child: board);
          }
          return Center(
            child: SizedBox(
              width: boardSize + reserve,
              height: boardSize,
              child: Row(
                children: <Widget>[
                  SizedBox(
                    key: const Key('play_area_advantage_indicator_positioned'),
                    width: _kAdvantageIndicatorWidth,
                    height: boardSize,
                    child: _PositionalAdvantageIndicator(
                      value: advantageValue,
                      whiteAtBottom: !_isBoardFlipped,
                      appliedAiMoveEvaluation:
                          LiveEvaluationService.state.appliedAiMoveEvaluation,
                    ),
                  ),
                  const SizedBox(width: _kAdvantageIndicatorGap),
                  board,
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildMoveListForHumanAi(BuildContext context) {
    return _withMoveListTopInset(
      context,
      const _InlineMoveList(
        key: Key('play_area_human_ai_move_list'),
        wrapKey: Key('play_area_human_ai_move_list_wrap'),
        roundKeyPrefix: 'play_area_human_ai_round_',
        moveKeyPrefix: 'play_area_human_ai_move_',
        layout: _InlineMoveListLayout.stacked,
        groupByRound: true,
        announceCompletedMove: true,
        fixedHeight: _kWrappedMoveListMaxHeight,
      ),
    );
  }

  Widget _buildMoveListForRegularGame(BuildContext context) {
    final Widget moveList = _InlineMoveList(
      key: const Key('play_area_regular_move_list'),
      wrapKey: const Key('play_area_regular_move_list_wrap'),
      roundKeyPrefix: 'play_area_regular_round_',
      moveKeyPrefix: 'play_area_regular_move_',
      onMoveTap: (BuildContext context, PgnNode<ExtMove> node) async {
        await HistoryNavigator.gotoNode(context, node, pop: false);
        _syncOfflineBoardClockToPosition();
      },
      showMovePreview: true,
      layout: _InlineMoveListLayout.stacked,
      groupByRound: true,
      announceCompletedMove: true,
      fixedHeight: _kWrappedMoveListMaxHeight,
    );
    return _isOfflineBoardMode
        ? moveList
        : _withMoveListTopInset(context, moveList);
  }

  Widget _buildHumanAiMainContent({
    required BuildContext context,
    required bool showPieceCountRows,
    bool showMoveList = true,
    bool showPlayerPanels = true,
  }) {
    final bool showAdvantageGraph =
        showPlayerPanels && _shouldShowAdvantageGraph(isGameSurface: true);

    return SizedBox(
      key: const Key('play_area_human_ai_main_content'),
      child: SafeArea(
        top: MediaQuery.of(context).orientation == Orientation.portrait,
        bottom: false,
        right: false,
        left: false,
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final Widget moveList = showMoveList
                ? _buildMoveListForHumanAi(context)
                : const SizedBox.shrink(
                    key: Key('play_area_human_ai_move_list_hidden'),
                  );
            final Widget topTable = showPlayerPanels
                ? const _HumanAiPlayerPanel(
                    key: Key('play_area_human_ai_robot_panel'),
                    isRobot: true,
                  )
                : const SizedBox.shrink(
                    key: Key('play_area_puzzle_top_player_hidden'),
                  );
            final bool showGameTip =
                showPlayerPanels && DB().generalSettings.showGameTips;
            final Widget gameTip = showGameTip
                ? const _HumanAiGameTipPanel(
                    key: Key('play_area_human_ai_tip_panel'),
                  )
                : const SizedBox.shrink(
                    key: Key('play_area_human_ai_tip_panel_hidden'),
                  );

            final double moveListHeight = showMoveList
                ? _wrappedMoveListReservedHeightForRoute(context)
                : 0;
            final double gameTipHeight = showGameTip
                ? _gameTipPanelHeightForLayout(context)
                : 0;
            final double boardRowsHeight = showPieceCountRows
                ? _pieceRowsHeightForLayout(context)
                : 0;
            final double topPanelHeight = showPlayerPanels
                ? _humanAiPlayerPanelHeightForLayout(context)
                : 0;
            final double bottomPanelHeight =
                (showPlayerPanels
                    ? _humanAiPlayerPanelHeightForLayout(context)
                    : 0) +
                (showAdvantageGraph ? 112 : 0);
            final double nonBoardHeight =
                moveListHeight +
                gameTipHeight +
                boardRowsHeight +
                topPanelHeight +
                bottomPanelHeight;

            // Shrink the board when the available height can't fit a
            // full-width board so it stays fully visible without scrolling.
            final double boardSize = _boardSizeForConstraints(
              constraints,
              nonBoardHeight,
            );

            final List<Widget> boardChildren = <Widget>[
              if (showPieceCountRows)
                _isBoardFlipped
                    ? _buildRemovedPieceCountRow()
                    : _buildPieceCountRow(),
              SizedBox.square(
                dimension: boardSize,
                child: _buildBoardScreenshot(),
              ),
              if (showPieceCountRows)
                _isBoardFlipped
                    ? _buildPieceCountRow()
                    : _buildRemovedPieceCountRow(),
            ];
            final List<Widget> bottomChildren = <Widget>[
              if (showPlayerPanels)
                const _HumanAiPlayerPanel(
                  key: Key('play_area_human_ai_player_panel'),
                  isRobot: false,
                ),
              if (showAdvantageGraph)
                SizedBox(
                  key: const Key('play_area_advantage_graph'),
                  height: 112,
                  width: double.infinity,
                  child: CustomPaint(
                    key: const Key('play_area_custom_paint_advantage_graph'),
                    painter: AdvantageGraphPainter(advantageData),
                  ),
                ),
            ];

            final double boardBlockHeight =
                constraints.maxWidth + boardRowsHeight;
            final double estimatedRequiredHeight =
                moveListHeight +
                gameTipHeight +
                boardBlockHeight +
                topPanelHeight +
                bottomPanelHeight;
            final bool canBalance =
                constraints.maxWidth >= _kBalancedLayoutMinWidth &&
                constraints.hasBoundedHeight &&
                constraints.maxHeight >=
                    estimatedRequiredHeight + _kBalancedLayoutSafetyMargin;

            if (canBalance) {
              final double freeHeight = math.max(
                0,
                constraints.maxHeight - estimatedRequiredHeight,
              );
              final double topSpacerHeight = freeHeight * 0.42;
              final double bottomSpacerHeight = freeHeight - topSpacerHeight;
              return SizedBox(
                height: constraints.maxHeight,
                child: Column(
                  key: const Key('play_area_human_ai_column'),
                  children: <Widget>[
                    moveList,
                    SizedBox(height: gameTipHeight, child: gameTip),
                    SizedBox(
                      height: topPanelHeight + topSpacerHeight,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: topTable,
                        ),
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: boardChildren,
                    ),
                    SizedBox(
                      height: bottomPanelHeight + bottomSpacerHeight,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: bottomChildren,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }

            final Widget tightColumn = Column(
              key: const Key('play_area_human_ai_column'),
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                moveList,
                SizedBox(height: gameTipHeight, child: gameTip),
                topTable,
                ...boardChildren,
                ...bottomChildren,
              ],
            );

            if (!constraints.hasBoundedHeight) {
              return SingleChildScrollView(
                key: const Key('play_area_human_ai_scroll_view'),
                child: tightColumn,
              );
            }

            return SizedBox(height: constraints.maxHeight, child: tightColumn);
          },
        ),
      ),
    );
  }

  Widget _buildHumanAiBottomBar(BuildContext context) {
    return ValueListenableBuilder<bool>(
      key: const Key('play_area_lichess_bottom_bar_builder'),
      valueListenable: AnalysisMode.stateNotifier,
      builder: (BuildContext context, _, _) {
        return _LichessGameBottomBar(
          onMenuPressed: _showHumanAiGameMenu,
          onResignOrResultPressed: _isHumanAiGameOver
              ? _showHumanAiGameResult
              : _canResignFromBottomBar
              ? () => _showResignConfirmation(context)
              : null,
          onTakeBackPressed: _canTakeBackFromBottomBar
              ? () => _takeBackFromBottomBar(context)
              : null,
          onHintPressed: _canShowHintFromBottomBar
              ? () => _showHintFromBottomBar(context)
              : null,
          isShowingResult: _isHumanAiGameOver,
          isHintHighlighted:
              AnalysisMode.isHint || AnalysisService.isBestMoveHintSearching,
        );
      },
    );
  }

  Widget _buildRegularBottomBar(BuildContext context) {
    return ValueListenableBuilder<int>(
      key: const Key('play_area_regular_bottom_bar_builder'),
      valueListenable: GameController().gameRecorder.moveCountNotifier,
      builder: (BuildContext context, _, _) {
        return ValueListenableBuilder<bool>(
          valueListenable: AnalysisMode.stateNotifier,
          builder: (BuildContext context, _, _) {
            if (_isAiVsAiMode) {
              final GameController controller = GameController();
              return ValueListenableBuilder<AiVsAiPlaybackState>(
                valueListenable: controller.aiVsAiPlaybackStateNotifier,
                builder: (BuildContext context, playbackState, _) {
                  return ValueListenableBuilder<bool>(
                    valueListenable: controller.engineActivityNotifier,
                    builder: (BuildContext context, isEngineActive, _) {
                      return _AiVsAiBottomBar(
                        playbackState: playbackState,
                        isEngineActive: isEngineActive,
                        isShowingResult: _isRegularGameOver,
                        onMenuPressed: _showRegularGameMenu,
                        onNewGamePressed: () =>
                            _requestAiVsAiNewGame(Navigator.of(context)),
                        onPlaybackPressed: _isRegularGameOver
                            ? _showRegularGameResult
                            : playbackState == AiVsAiPlaybackState.playing
                            ? _pauseAiVsAiPlayback
                            : playbackState == AiVsAiPlaybackState.paused
                            ? () => unawaited(_resumeAiVsAiPlayback(context))
                            : null,
                        onStepPressed:
                            !_isRegularGameOver &&
                                playbackState == AiVsAiPlaybackState.paused &&
                                !isEngineActive
                            ? () => unawaited(_stepAiVsAiPlayback(context))
                            : null,
                        onMoveListPressed: () =>
                            _openAiVsAiMoves(Navigator.of(context)),
                      );
                    },
                  );
                },
              );
            }
            if (_isOfflineBoardMode) {
              return _OfflineBoardBottomBar(
                onMenuPressed: _showRegularGameMenu,
                onTakeBackPressed: _canTakeBackFromRegularBottomBar
                    ? () => unawaited(_takeBackFromRegularBottomBar(context))
                    : null,
                onPreviousPressed: _canStepBackFromRegularBottomBar
                    ? () => unawaited(_stepBackFromRegularBottomBar(context))
                    : null,
                onNextPressed: _canStepForwardFromRegularBottomBar
                    ? () => unawaited(_stepForwardFromRegularBottomBar(context))
                    : null,
              );
            }
            if (_isAnalysisMode) {
              return _AnalysisBottomBar(
                onMenuPressed: _showRegularGameMenu,
                onEnginePressed: () =>
                    unawaited(AnalysisService.toggle(context)),
                onEngineLongPressed: () =>
                    _showAnalysisEngineSheet(context, strings: S.of(context)),
                isEngineHighlighted: AnalysisMode.isFullAnalysis,
                onPreviousPressed: _canStepBackFromRegularBottomBar
                    ? () => unawaited(_stepBackFromRegularBottomBar(context))
                    : null,
                onNextPressed: _canStepForwardFromRegularBottomBar
                    ? () => unawaited(_stepForwardFromRegularBottomBar(context))
                    : null,
              );
            }

            return _RegularGameBottomBar(
              onMenuPressed: _showRegularGameMenu,
              onResignOrResultPressed: _isRegularGameOver
                  ? _showRegularGameResult
                  : _canResignFromRegularBottomBar
                  ? () => _showRegularResignConfirmation(context)
                  : null,
              isShowingResult: _isRegularGameOver,
              onTakeBackPressed: _canTakeBackFromRegularBottomBar
                  ? () => _takeBackFromRegularBottomBar(context)
                  : null,
              onPreviousPressed: _canStepBackFromRegularBottomBar
                  ? () => unawaited(_stepBackFromRegularBottomBar(context))
                  : null,
              onNextPressed: _canStepForwardFromRegularBottomBar
                  ? () => unawaited(_stepForwardFromRegularBottomBar(context))
                  : null,
            );
          },
        );
      },
    );
  }

  Widget _buildAnalysisMainContent({
    required BuildContext context,
    required bool showPieceCountRows,
  }) {
    return ValueListenableBuilder<bool>(
      valueListenable: AnalysisMode.stateNotifier,
      builder: (BuildContext context, _, _) {
        final bool hasEngineLinesSlot =
            AnalysisMode.showEngineLines && AnalysisMode.engineLineCount > 0;

        return SafeArea(
          top: MediaQuery.of(context).orientation == Orientation.portrait,
          bottom: false,
          right: false,
          left: false,
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final double maxHeight = constraints.hasBoundedHeight
                  ? constraints.maxHeight
                  : MediaQuery.sizeOf(context).height;
              final double engineLinesReserve = hasEngineLinesSlot
                  ? _kAnalysisEngineLinesReserveHeight
                  : 0;
              final EvaluationGaugePosition gaugePosition =
                  AnalysisMode.evaluationGaugePosition;
              final double evaluationGaugeHorizontalReserve =
                  AnalysisMode.showEvaluationGauge &&
                      !gaugePosition.isHorizontal
                  ? _kAdvantageIndicatorReserve
                  : 0;
              final double evaluationGaugeVerticalReserve =
                  AnalysisMode.showEvaluationGauge && gaugePosition.isHorizontal
                  ? _kAdvantageIndicatorReserve
                  : 0;
              const double tabPanelMinHeight = 174;
              final double pieceRowsHeight = showPieceCountRows
                  ? _pieceRowsHeightForLayout(context)
                  : AppTheme.boardMargin * 2;
              final double boardHeightBudget =
                  maxHeight -
                  engineLinesReserve -
                  tabPanelMinHeight -
                  pieceRowsHeight -
                  evaluationGaugeVerticalReserve -
                  _kBalancedLayoutSafetyMargin;
              final double boardWidthBudget = math.max(
                0,
                constraints.maxWidth *
                        (AnalysisMode.smallBoard
                            ? _kAnalysisSmallBoardScale
                            : 1) -
                    evaluationGaugeHorizontalReserve,
              );
              final double boardSize = math.max(
                0,
                math.min(boardWidthBudget, boardHeightBudget),
              );

              return Column(
                key: const Key('play_area_analysis_column'),
                children: <Widget>[
                  _buildAnalysisEngineLines(context),
                  if (showPieceCountRows)
                    _isBoardFlipped
                        ? _buildRemovedPieceCountRow()
                        : _buildPieceCountRow()
                  else
                    const SizedBox(height: AppTheme.boardMargin),
                  _buildAnalysisBoardWithEvaluationGauge(boardSize: boardSize),
                  if (showPieceCountRows)
                    _isBoardFlipped
                        ? _buildPieceCountRow()
                        : _buildRemovedPieceCountRow()
                  else
                    const SizedBox(height: AppTheme.boardMargin),
                  Expanded(child: _buildAnalysisTabs(context)),
                ],
              );
            },
          ),
        );
      },
    );
  }

  int _analysisEvaluationGaugeValue() {
    if (AnalysisMode.isFullAnalysis &&
        AnalysisMode.analysisLineResults.isNotEmpty) {
      return _analysisOutcomeGaugeValue(
        AnalysisMode.analysisLineResults.first.outcome,
      );
    }
    return _getCurrentAdvantageValue();
  }

  Widget _buildAnalysisBoardWithEvaluationGauge({
    required double boardSize,
    Key containerKey = const Key('play_area_analysis_board_with_gauge'),
    Key boardKey = const Key('play_area_analysis_board'),
    Key gaugeKey = const Key('play_area_analysis_evaluation_gauge'),
  }) {
    final Widget board = SizedBox.square(
      key: boardKey,
      dimension: boardSize,
      child: _buildBoardScreenshot(includeAdvantageIndicator: false),
    );
    if (!AnalysisMode.showEvaluationGauge) {
      return Center(child: board);
    }
    final EvaluationGaugePosition position =
        AnalysisMode.evaluationGaugePosition;
    final Axis gaugeAxis = position.isHorizontal
        ? Axis.horizontal
        : Axis.vertical;
    final Widget gauge = SizedBox(
      key: gaugeKey,
      width: position.isHorizontal ? boardSize : _kAdvantageIndicatorWidth,
      height: position.isHorizontal ? _kAdvantageIndicatorWidth : boardSize,
      child: _PositionalAdvantageIndicator(
        value: _analysisEvaluationGaugeValue(),
        whiteAtBottom: !_isBoardFlipped,
        axis: gaugeAxis,
      ),
    );
    final Widget gap = position.isHorizontal
        ? const SizedBox(height: _kAdvantageIndicatorGap)
        : const SizedBox(width: _kAdvantageIndicatorGap);
    final Widget content = switch (position) {
      EvaluationGaugePosition.left => Row(
        textDirection: TextDirection.ltr,
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[gauge, gap, board],
      ),
      EvaluationGaugePosition.top => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[gauge, gap, board],
      ),
      EvaluationGaugePosition.right => Row(
        textDirection: TextDirection.ltr,
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[board, gap, gauge],
      ),
      EvaluationGaugePosition.bottom => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[board, gap, gauge],
      ),
    };
    return Center(
      child: SizedBox(
        key: containerKey,
        width:
            boardSize +
            (position.isHorizontal ? 0 : _kAdvantageIndicatorReserve),
        height:
            boardSize +
            (position.isHorizontal ? _kAdvantageIndicatorReserve : 0),
        child: content,
      ),
    );
  }

  Widget _buildAnalysisTabs(BuildContext context, {bool framed = false}) {
    return ValueListenableBuilder<bool>(
      valueListenable: AnalysisMode.stateNotifier,
      builder: (BuildContext context, _, _) {
        final GameSession? session = GameSessionScope.sessionOf(context);
        return _AnalysisPanel(
          framed: framed,
          explorer: OpeningExplorerPage(
            session: session,
            startFromSession: true,
            embedded: true,
            showBoard: false,
            onMoveSelected: (GameAction action) =>
                _applyAnalysisExplorerMove(context, action),
          ),
          moves: Column(
            children: <Widget>[
              Expanded(
                child: _InlineMoveList(
                  key: const Key('play_area_analysis_moves'),
                  wrapKey: const Key('play_area_analysis_moves_wrap'),
                  roundKeyPrefix: 'play_area_analysis_round_',
                  moveKeyPrefix: 'play_area_analysis_move_',
                  onMoveTap: (BuildContext context, PgnNode<ExtMove> node) {
                    return _navigateAnalysisNode(context, node);
                  },
                  showMainlineContinuation: true,
                  showMovePreview: true,
                  showMoveActions: true,
                  showMoveAnnotations: AnalysisMode.showMoveAnnotations,
                  showMoveComments: AnalysisMode.showMoveComments,
                  showRootComments: true,
                  usesGameSurfaceColors: false,
                  showVariations: true,
                  showEvaluations: AnalysisMode.isFullAnalysis,
                  showMiniBoards: AnalysisMode.showMoveMiniBoards,
                  layout: AnalysisMode.inlineNotation
                      ? _InlineMoveListLayout.stacked
                      : _InlineMoveListLayout.twoColumn,
                  groupByRound: true,
                ),
              ),
              _AnalysisVariationsBar(
                key: const Key('play_area_analysis_variations_bar'),
                showAnnotations: AnalysisMode.showMoveAnnotations,
                onMoveTap: _navigateAnalysisNode,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAnalysisEngineLines(BuildContext context) {
    return ValueListenableBuilder<bool>(
      key: const Key('play_area_analysis_engine_lines_builder'),
      valueListenable: AnalysisMode.stateNotifier,
      builder: (BuildContext context, _, _) {
        if (!AnalysisMode.showEngineLines) {
          return const SizedBox.shrink(
            key: Key('play_area_analysis_engine_lines_hidden'),
          );
        }
        if (AnalysisMode.engineLineCount == 0) {
          return const SizedBox.shrink(
            key: Key('play_area_analysis_engine_lines_disabled'),
          );
        }

        return _AnalysisEngineLines(
          key: const Key('play_area_analysis_engine_lines'),
          results: AnalysisMode.isFullAnalysis
              ? AnalysisMode.analysisLineResults
              : const <MoveAnalysisResult>[],
          onMoveTap: (String move) async {
            await _applyAnalysisMove(context, move);
          },
        );
      },
    );
  }

  Widget _buildOfflineBoardMainContent({
    required BuildContext context,
    required bool showPieceCountRows,
  }) {
    final PieceColor bottomSide = _isBoardFlipped
        ? PieceColor.black
        : PieceColor.white;
    final PieceColor topSide = bottomSide.opponent;
    final ({bool bottomUpsideDown, bool topUpsideDown}) playerOrientation =
        _offlineBoardPlayerOrientation(bottomSide);

    return SafeArea(
      top: false,
      bottom: false,
      right: false,
      left: false,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final bool showContextualTip =
              _supportsGameTips && DB().generalSettings.showGameTips;
          final double pieceRowsHeight = showPieceCountRows
              ? _pieceRowsHeightForLayout(context)
              : AppTheme.boardMargin * 2;
          final double nonBoardHeight =
              _kWrappedMoveListMaxHeight +
              (showContextualTip ? GameHeader.contextualHeight : 0) +
              _kOfflineBoardPlayerPanelHeight * 2 +
              pieceRowsHeight +
              _kOfflineBoardLayoutSafetyMargin;
          final double boardSize = _boardSizeForConstraints(
            constraints,
            nonBoardHeight,
          );
          final Widget column = Column(
            key: const Key('play_area_offline_board_column'),
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              _buildMoveListForRegularGame(context),
              if (showContextualTip)
                const GameHeader(
                  key: Key('play_area_offline_board_game_header'),
                ),
              SizedBox(
                height: _kOfflineBoardPlayerPanelHeight,
                child: _OfflineBoardPlayerPanel(
                  key: const Key('play_area_offline_board_top_player'),
                  side: topSide,
                  upsideDown: playerOrientation.topUpsideDown,
                ),
              ),
              if (showPieceCountRows)
                _isBoardFlipped
                    ? _buildRemovedPieceCountRow()
                    : _buildPieceCountRow()
              else
                const SizedBox(height: AppTheme.boardMargin),
              SizedBox.square(
                key: const Key('play_area_offline_board_board'),
                dimension: boardSize,
                child: _buildBoardScreenshot(),
              ),
              if (showPieceCountRows)
                _isBoardFlipped
                    ? _buildPieceCountRow()
                    : _buildRemovedPieceCountRow()
              else
                const SizedBox(height: AppTheme.boardMargin),
              SizedBox(
                height: _kOfflineBoardPlayerPanelHeight,
                child: _OfflineBoardPlayerPanel(
                  key: const Key('play_area_offline_board_bottom_player'),
                  side: bottomSide,
                  upsideDown: playerOrientation.bottomUpsideDown,
                ),
              ),
            ],
          );
          if (!constraints.hasBoundedHeight) {
            return SingleChildScrollView(child: column);
          }
          return SizedBox(height: constraints.maxHeight, child: column);
        },
      ),
    );
  }

  Widget _buildRegularMainContent({
    required BuildContext context,
    required bool isSetupPosition,
    required bool isPuzzle,
    required bool showPieceCountRows,
  }) {
    final bool isPlayableGame = !isSetupPosition && !isPuzzle;
    final bool showAdvantageGraph = _shouldShowAdvantageGraph(
      isGameSurface: isPlayableGame,
    );

    return SafeArea(
      top: MediaQuery.of(context).orientation == Orientation.portrait,
      bottom: false,
      right: false,
      left: false,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final Widget moveList = _buildMoveListForRegularGame(context);
          final bool showContextualTip =
              isPlayableGame &&
              _supportsGameTips &&
              DB().generalSettings.showGameTips;
          final Widget topTable = showContextualTip
              ? const GameHeader(key: Key('play_area_game_header'))
              : const SizedBox.shrink(key: Key('play_area_game_header_hidden'));
          final double topPanelHeight = showContextualTip
              ? GameHeader.contextualHeight
              : 0;
          final double moveListReserve = isPlayableGame
              ? _wrappedMoveListReservedHeightForRoute(context)
              : 0;
          final double pieceRowsHeight = showPieceCountRows
              ? _pieceRowsHeightForLayout(context)
              : AppTheme.boardMargin * 2;
          final double advantageGraphHeight = showAdvantageGraph ? 150 : 0;
          final double nonBoardHeight =
              moveListReserve +
              topPanelHeight +
              pieceRowsHeight +
              advantageGraphHeight +
              AppTheme.boardMargin;

          // Shrink the board when the available height can't fit a
          // full-width board so it stays fully visible without scrolling.
          final double boardSize = _boardSizeForConstraints(
            constraints,
            nonBoardHeight,
          );

          final List<Widget> boardChildren = <Widget>[
            if (showPieceCountRows)
              _isBoardFlipped
                  ? _buildRemovedPieceCountRow()
                  : _buildPieceCountRow()
            else
              const SizedBox(height: AppTheme.boardMargin),
            SizedBox.square(
              dimension: boardSize,
              child: _buildBoardScreenshot(),
            ),
            if (showPieceCountRows)
              _isBoardFlipped
                  ? _buildPieceCountRow()
                  : _buildRemovedPieceCountRow()
            else
              const SizedBox(height: AppTheme.boardMargin),
          ];
          final List<Widget> bottomChildren = <Widget>[
            if (showAdvantageGraph)
              SizedBox(
                key: const Key('play_area_advantage_graph'),
                height: 150,
                width: double.infinity,
                child: CustomPaint(
                  key: const Key('play_area_custom_paint_advantage_graph'),
                  painter: AdvantageGraphPainter(advantageData),
                ),
              ),
            const SizedBox(height: AppTheme.boardMargin),
          ];

          final double estimatedRequiredHeight =
              constraints.maxWidth + nonBoardHeight;
          final double balancedSidePanelHeight = math.max(
            topPanelHeight,
            advantageGraphHeight + AppTheme.boardMargin,
          );
          final double balancedFixedHeight =
              moveListReserve + pieceRowsHeight + boardSize;
          final double balancedFlexibleHeight = constraints.hasBoundedHeight
              ? math.max(0, constraints.maxHeight - balancedFixedHeight)
              : 0;
          final bool canBalance =
              isPlayableGame &&
              constraints.maxWidth >= _kBalancedLayoutMinWidth &&
              constraints.hasBoundedHeight &&
              constraints.maxHeight >=
                  estimatedRequiredHeight + _kBalancedLayoutSafetyMargin &&
              balancedFlexibleHeight >= balancedSidePanelHeight * 2;

          if (canBalance) {
            return SizedBox(
              height: constraints.maxHeight,
              child: Column(
                key: const Key('play_area_column'),
                children: <Widget>[
                  moveList,
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: topTable,
                      ),
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: boardChildren,
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: bottomChildren,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }

          final Widget tightColumn = Column(
            key: const Key('play_area_column'),
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              if (isPlayableGame) moveList,
              topTable,
              ...boardChildren,
              ...bottomChildren,
            ],
          );

          if (!constraints.hasBoundedHeight) {
            return SingleChildScrollView(
              key: const Key('play_area_single_child_scroll_view'),
              child: tightColumn,
            );
          }

          return SizedBox(height: constraints.maxHeight, child: tightColumn);
        },
      ),
    );
  }

  Widget _buildAnalysisLandscapeContent({
    required BuildContext context,
    required BoxConstraints constraints,
    required bool showPieceCountRows,
  }) {
    assert(
      constraints.hasBoundedHeight,
      'Analysis landscape layout requires bounded height.',
    );
    final Size viewport = constraints.biggest;
    const double horizontalPadding = AppStyles.bodyPadding;
    const double verticalPadding = 8;
    const double gap = AppStyles.bodyPadding;
    const double pieceRowHeight = 24;
    final double availableWidth = math.max(
      0,
      viewport.width - horizontalPadding * 2,
    );
    final double availableHeight = math.max(
      0,
      viewport.height - kLichessBottomBarHeight - verticalPadding * 2,
    );
    final EvaluationGaugePosition gaugePosition =
        AnalysisMode.evaluationGaugePosition;
    final double evaluationGaugeHorizontalReserve =
        AnalysisMode.showEvaluationGauge && !gaugePosition.isHorizontal
        ? _kAdvantageIndicatorReserve
        : 0;
    final double evaluationGaugeVerticalReserve =
        AnalysisMode.showEvaluationGauge && gaugePosition.isHorizontal
        ? _kAdvantageIndicatorReserve
        : 0;
    final double boardHeightAllowance = math.max(
      0,
      availableHeight -
          (showPieceCountRows ? pieceRowHeight * 2 : 0) -
          evaluationGaugeVerticalReserve,
    );
    final double boardSize = math.min(
      boardHeightAllowance,
      math.max(0, availableWidth * 0.52 - evaluationGaugeHorizontalReserve),
    );
    final double boardPaneWidth = boardSize + evaluationGaugeHorizontalReserve;

    return SizedBox(
      key: const Key('play_area_analysis_landscape_content'),
      width: viewport.width,
      height: viewport.height,
      child: SafeArea(
        bottom: false,
        right: false,
        left: false,
        child: Column(
          children: <Widget>[
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: horizontalPadding,
                  vertical: verticalPadding,
                ),
                child: Row(
                  children: <Widget>[
                    SizedBox(
                      key: const Key('play_area_analysis_landscape_board_pane'),
                      width: boardPaneWidth,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          if (showPieceCountRows)
                            SizedBox(
                              height: pieceRowHeight,
                              child: _isBoardFlipped
                                  ? _buildRemovedPieceCountRow()
                                  : _buildPieceCountRow(),
                            ),
                          _buildAnalysisBoardWithEvaluationGauge(
                            boardSize: boardSize,
                            containerKey: const Key(
                              'play_area_analysis_landscape_board_with_gauge',
                            ),
                            boardKey: const Key(
                              'play_area_analysis_landscape_board',
                            ),
                            gaugeKey: const Key(
                              'play_area_analysis_landscape_evaluation_gauge',
                            ),
                          ),
                          if (showPieceCountRows)
                            SizedBox(
                              height: pieceRowHeight,
                              child: _isBoardFlipped
                                  ? _buildPieceCountRow()
                                  : _buildRemovedPieceCountRow(),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: gap),
                    Expanded(
                      child: Column(
                        key: const Key(
                          'play_area_analysis_landscape_side_panel',
                        ),
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          _buildAnalysisEngineLines(context),
                          Expanded(
                            child: _buildAnalysisTabs(context, framed: true),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            _buildRegularBottomBar(context),
          ],
        ),
      ),
    );
  }

  Widget _buildHumanAiLandscapeContent({
    required BuildContext context,
    required BoxConstraints constraints,
    required bool showPieceCountRows,
    required bool showGameChrome,
  }) {
    assert(
      constraints.hasBoundedHeight,
      'Human vs AI landscape layout requires bounded height.',
    );
    final Size viewport = constraints.biggest;
    const double horizontalPadding = AppStyles.bodyPadding;
    const double verticalPadding = 8;
    const double gap = AppStyles.bodyPadding;
    const double pieceRowHeight = 24;
    final double availableWidth = math.max(
      0,
      viewport.width - horizontalPadding * 2,
    );
    final double bottomReservedHeight = showGameChrome
        ? kLichessBottomBarHeight
        : 0;
    final double availableHeight = math.max(
      0,
      viewport.height - bottomReservedHeight - verticalPadding * 2,
    );
    final double targetSidePanelWidth = showGameChrome ? 280 : 0;
    final double boardHeightAllowance = math.max(
      0,
      availableHeight - (showPieceCountRows ? pieceRowHeight * 2 : 0),
    );
    final double boardWidthWithPanel = math.max(
      0,
      availableWidth - targetSidePanelWidth - (showGameChrome ? gap : 0),
    );
    final double boardSize = math.min(
      boardHeightAllowance,
      boardWidthWithPanel > 0 ? boardWidthWithPanel : availableWidth * 0.58,
    );

    return SizedBox(
      key: const Key('play_area_human_ai_landscape_content'),
      width: viewport.width,
      height: viewport.height,
      child: SafeArea(
        bottom: false,
        right: false,
        left: false,
        child: Column(
          children: <Widget>[
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: horizontalPadding,
                  vertical: verticalPadding,
                ),
                child: Row(
                  children: <Widget>[
                    SizedBox(
                      key: const Key('play_area_human_ai_landscape_board_pane'),
                      width: boardSize,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          if (showPieceCountRows)
                            SizedBox(
                              height: pieceRowHeight,
                              child: _isBoardFlipped
                                  ? _buildRemovedPieceCountRow()
                                  : _buildPieceCountRow(),
                            ),
                          SizedBox.square(
                            key: const Key(
                              'play_area_human_ai_landscape_board',
                            ),
                            dimension: boardSize,
                            child: _buildBoardScreenshot(),
                          ),
                          if (showPieceCountRows)
                            SizedBox(
                              height: pieceRowHeight,
                              child: _isBoardFlipped
                                  ? _buildPieceCountRow()
                                  : _buildRemovedPieceCountRow(),
                            ),
                        ],
                      ),
                    ),
                    if (showGameChrome) ...<Widget>[
                      const SizedBox(width: gap),
                      Expanded(
                        child: Column(
                          key: const Key(
                            'play_area_human_ai_landscape_side_panel',
                          ),
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            const Expanded(
                              child: _InlineMoveList(
                                key: Key(
                                  'play_area_human_ai_landscape_move_list',
                                ),
                                wrapKey: Key(
                                  'play_area_human_ai_landscape_move_list_wrap',
                                ),
                                roundKeyPrefix:
                                    'play_area_human_ai_landscape_round_',
                                moveKeyPrefix:
                                    'play_area_human_ai_landscape_move_',
                                layout: _InlineMoveListLayout.stacked,
                                groupByRound: true,
                                announceCompletedMove: true,
                              ),
                            ),
                            if (DB().generalSettings.showGameTips)
                              SizedBox(
                                height: _gameTipPanelHeightForLayout(context),
                                child: const _HumanAiGameTipPanel(
                                  key: Key(
                                    'play_area_human_ai_landscape_tip_panel',
                                  ),
                                ),
                              ),
                            const _HumanAiPlayerPanel(
                              key: Key(
                                'play_area_human_ai_landscape_robot_panel',
                              ),
                              isRobot: true,
                            ),
                            const _HumanAiPlayerPanel(
                              key: Key(
                                'play_area_human_ai_landscape_player_panel',
                              ),
                              isRobot: false,
                            ),
                            if (_shouldShowAdvantageGraph(isGameSurface: true))
                              SizedBox(
                                key: const Key(
                                  'play_area_human_ai_landscape_advantage_graph',
                                ),
                                height: 80,
                                width: double.infinity,
                                child: CustomPaint(
                                  key: const Key(
                                    'play_area_human_ai_landscape_advantage_paint',
                                  ),
                                  painter: AdvantageGraphPainter(advantageData),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (showGameChrome) _buildHumanAiBottomBar(context),
          ],
        ),
      ),
    );
  }

  Widget _buildRegularLandscapeContent({
    required BuildContext context,
    required BoxConstraints constraints,
    required bool showPieceCountRows,
  }) {
    assert(
      constraints.hasBoundedHeight,
      'Regular landscape layout requires bounded height.',
    );
    final Size viewport = constraints.biggest;
    const double horizontalPadding = AppStyles.bodyPadding;
    const double verticalPadding = 8;
    const double gap = AppStyles.bodyPadding;
    const double pieceRowHeight = 24;
    const double targetSidePanelWidth = 300;
    final double availableWidth = math.max(
      0,
      viewport.width - horizontalPadding * 2,
    );
    const double bottomReservedHeight = kLichessBottomBarHeight;
    final double availableHeight = math.max(
      0,
      viewport.height - bottomReservedHeight - verticalPadding * 2,
    );
    final double boardHeightAllowance = math.max(
      0,
      availableHeight - (showPieceCountRows ? pieceRowHeight * 2 : 0),
    );
    final double boardWidthWithPanel = math.max(
      0,
      availableWidth - targetSidePanelWidth - gap,
    );
    final double boardSize = math.min(
      boardHeightAllowance,
      boardWidthWithPanel > 0 ? boardWidthWithPanel : availableWidth * 0.58,
    );

    return SizedBox(
      key: const Key('play_area_regular_landscape_content'),
      width: viewport.width,
      height: viewport.height,
      child: SafeArea(
        bottom: false,
        right: false,
        left: false,
        child: Column(
          children: <Widget>[
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: horizontalPadding,
                  vertical: verticalPadding,
                ),
                child: Row(
                  children: <Widget>[
                    SizedBox(
                      key: const Key('play_area_regular_landscape_board_pane'),
                      width: boardSize,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          if (showPieceCountRows)
                            SizedBox(
                              height: pieceRowHeight,
                              child: _isBoardFlipped
                                  ? _buildRemovedPieceCountRow()
                                  : _buildPieceCountRow(),
                            ),
                          SizedBox.square(
                            key: const Key('play_area_regular_landscape_board'),
                            dimension: boardSize,
                            child: _buildBoardScreenshot(),
                          ),
                          if (showPieceCountRows)
                            SizedBox(
                              height: pieceRowHeight,
                              child: _isBoardFlipped
                                  ? _buildPieceCountRow()
                                  : _buildRemovedPieceCountRow(),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: gap),
                    Expanded(
                      child: Column(
                        key: const Key(
                          'play_area_regular_landscape_side_panel',
                        ),
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          Expanded(
                            child: _InlineMoveList(
                              key: const Key(
                                'play_area_regular_landscape_move_list',
                              ),
                              wrapKey: const Key(
                                'play_area_regular_landscape_move_list_wrap',
                              ),
                              roundKeyPrefix:
                                  'play_area_regular_landscape_round_',
                              moveKeyPrefix:
                                  'play_area_regular_landscape_move_',
                              onMoveTap:
                                  (
                                    BuildContext context,
                                    PgnNode<ExtMove> node,
                                  ) {
                                    return HistoryNavigator.gotoNode(
                                      context,
                                      node,
                                      pop: false,
                                    );
                                  },
                              showMovePreview: true,
                              layout: _InlineMoveListLayout.stacked,
                              groupByRound: true,
                              announceCompletedMove: true,
                            ),
                          ),
                          if (_supportsGameTips &&
                              DB().generalSettings.showGameTips)
                            const GameHeader(
                              key: Key('play_area_regular_landscape_header'),
                            ),
                          if (_shouldShowAdvantageGraph(isGameSurface: true))
                            SizedBox(
                              key: const Key(
                                'play_area_regular_landscape_advantage_graph',
                              ),
                              height: 80,
                              width: double.infinity,
                              child: CustomPaint(
                                key: const Key(
                                  'play_area_regular_landscape_advantage_paint',
                                ),
                                painter: AdvantageGraphPainter(advantageData),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            _buildRegularBottomBar(context),
          ],
        ),
      ),
    );
  }

  Widget _buildOfflineBoardLandscapeContent({
    required BuildContext context,
    required BoxConstraints constraints,
    required bool showPieceCountRows,
  }) {
    assert(
      constraints.hasBoundedHeight,
      'Offline Board landscape layout requires bounded height.',
    );
    final Size viewport = constraints.biggest;
    const double horizontalPadding = AppStyles.bodyPadding;
    const double verticalPadding = 8;
    const double gap = AppStyles.bodyPadding;
    const double pieceRowHeight = 24;
    const double targetSidePanelWidth = 320;
    final double availableWidth = math.max(
      0,
      viewport.width - horizontalPadding * 2,
    );
    final double availableHeight = math.max(
      0,
      viewport.height - kLichessBottomBarHeight - verticalPadding * 2,
    );
    final double boardHeightAllowance = math.max(
      0,
      availableHeight - (showPieceCountRows ? pieceRowHeight * 2 : 0),
    );
    final double boardSize = math.min(
      boardHeightAllowance,
      math.max(0, availableWidth - targetSidePanelWidth - gap),
    );
    final PieceColor bottomSide = _isBoardFlipped
        ? PieceColor.black
        : PieceColor.white;
    final PieceColor topSide = bottomSide.opponent;
    final ({bool bottomUpsideDown, bool topUpsideDown}) playerOrientation =
        _offlineBoardPlayerOrientation(bottomSide);

    return SizedBox(
      key: const Key('play_area_offline_board_landscape_content'),
      width: viewport.width,
      height: viewport.height,
      child: SafeArea(
        top: false,
        bottom: false,
        right: false,
        left: false,
        child: Column(
          children: <Widget>[
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: horizontalPadding,
                  vertical: verticalPadding,
                ),
                child: Row(
                  children: <Widget>[
                    SizedBox(
                      width: boardSize,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          if (showPieceCountRows)
                            SizedBox(
                              height: pieceRowHeight,
                              child: _isBoardFlipped
                                  ? _buildRemovedPieceCountRow()
                                  : _buildPieceCountRow(),
                            ),
                          SizedBox.square(
                            key: const Key(
                              'play_area_offline_board_landscape_board',
                            ),
                            dimension: boardSize,
                            child: _buildBoardScreenshot(),
                          ),
                          if (showPieceCountRows)
                            SizedBox(
                              height: pieceRowHeight,
                              child: _isBoardFlipped
                                  ? _buildPieceCountRow()
                                  : _buildRemovedPieceCountRow(),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: gap),
                    Expanded(
                      child: Column(
                        key: const Key(
                          'play_area_offline_board_landscape_side_panel',
                        ),
                        children: <Widget>[
                          Expanded(
                            child: _InlineMoveList(
                              key: const Key(
                                'play_area_offline_board_landscape_move_list',
                              ),
                              wrapKey: const Key(
                                'play_area_offline_board_landscape_move_wrap',
                              ),
                              roundKeyPrefix:
                                  'play_area_offline_board_landscape_round_',
                              moveKeyPrefix:
                                  'play_area_offline_board_landscape_move_',
                              onMoveTap:
                                  (
                                    BuildContext context,
                                    PgnNode<ExtMove> node,
                                  ) async {
                                    await HistoryNavigator.gotoNode(
                                      context,
                                      node,
                                      pop: false,
                                    );
                                    _syncOfflineBoardClockToPosition();
                                  },
                              showMovePreview: true,
                              layout: _InlineMoveListLayout.stacked,
                              groupByRound: true,
                              announceCompletedMove: true,
                            ),
                          ),
                          if (_supportsGameTips &&
                              DB().generalSettings.showGameTips)
                            const GameHeader(
                              key: Key(
                                'play_area_offline_board_landscape_header',
                              ),
                            ),
                          SizedBox(
                            height: _kOfflineBoardPlayerPanelHeight,
                            child: _OfflineBoardPlayerPanel(
                              key: const Key(
                                'play_area_offline_board_landscape_top_player',
                              ),
                              side: topSide,
                              upsideDown: playerOrientation.topUpsideDown,
                            ),
                          ),
                          SizedBox(
                            height: _kOfflineBoardPlayerPanelHeight,
                            child: _OfflineBoardPlayerPanel(
                              key: const Key(
                                'play_area_offline_board_landscape_bottom_player',
                              ),
                              side: bottomSide,
                              upsideDown: playerOrientation.bottomUpsideDown,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            _buildRegularBottomBar(context),
          ],
        ),
      ),
    );
  }

  ({bool bottomUpsideDown, bool topUpsideDown}) _offlineBoardPlayerOrientation(
    PieceColor bottomSide,
  ) {
    assert(bottomSide == PieceColor.white || bottomSide == PieceColor.black);
    if (!DB().generalSettings.offlineBoardFlipAfterMove) {
      return (bottomUpsideDown: false, topUpsideDown: true);
    }

    final PieceColor sideToMove =
        GameController().activeSessionSideToMove ??
        GameController().activeBoardView.sideToMove;
    final bool activePlayerFacesFromTop =
        (sideToMove == PieceColor.white || sideToMove == PieceColor.black) &&
        sideToMove != bottomSide;
    return (
      bottomUpsideDown: activePlayerFacesFromTop,
      topUpsideDown: activePlayerFacesFromTop,
    );
  }

  @override
  Widget build(BuildContext context) {
    _syncAnalysisMoveListener();
    return LayoutBuilder(
      key: const Key('play_area_layout_builder'),
      builder: (BuildContext context, BoxConstraints constraints) {
        final double dimension =
            (constraints.maxWidth) *
            (MediaQuery.of(context).orientation == Orientation.portrait
                ? 1.0
                : 0.65);

        // While editing a setup position the regular history / analysis /
        // main toolbars are replaced by the dedicated setup toolbar.
        final bool isSetupPosition =
            GameController().gameInstance.gameMode == GameMode.setupPosition;

        // Hide the regular history / main toolbars in puzzle mode to keep the
        // interface clean; the PuzzlePage provides its own puzzle controls.
        final bool isPuzzle =
            GameController().gameInstance.gameMode == GameMode.puzzle;
        final bool isAnalysisMode = _isAnalysisMode;
        final bool isOfflineBoardMode = _isOfflineBoardMode;
        final bool usesLichessHumanAiToolbar =
            _usesLichessHumanAiToolbar && !isSetupPosition && !isPuzzle;
        final bool usesHumanAiBoardLayout =
            usesLichessHumanAiToolbar || isPuzzle;
        final bool showPieceCountRows =
            DB().displaySettings.isUnplacedAndRemovedPiecesShown;

        // Human vs AI mirrors the Lichess offline-computer screen: one
        // bottom bar with menu, takeback, resign, and hint. Other game modes
        // also keep their toolbars at the bottom for a consistent shell.
        final bool useHumanAiLandscapeLayout =
            usesHumanAiBoardLayout &&
            constraints.hasBoundedHeight &&
            constraints.maxWidth > constraints.maxHeight;

        if (useHumanAiLandscapeLayout) {
          return _buildHumanAiLandscapeContent(
            context: context,
            constraints: constraints,
            showPieceCountRows: showPieceCountRows,
            showGameChrome: !isPuzzle,
          );
        }
        final bool useAnalysisLandscapeLayout =
            isAnalysisMode &&
            constraints.hasBoundedHeight &&
            constraints.maxWidth > constraints.maxHeight;

        if (useAnalysisLandscapeLayout) {
          return _buildAnalysisLandscapeContent(
            context: context,
            constraints: constraints,
            showPieceCountRows: showPieceCountRows,
          );
        }
        final bool useRegularLandscapeLayout =
            !usesLichessHumanAiToolbar &&
            !isAnalysisMode &&
            !isSetupPosition &&
            !isPuzzle &&
            constraints.hasBoundedHeight &&
            constraints.maxWidth > constraints.maxHeight;

        if (useRegularLandscapeLayout) {
          if (isOfflineBoardMode) {
            return _buildOfflineBoardLandscapeContent(
              context: context,
              constraints: constraints,
              showPieceCountRows: showPieceCountRows,
            );
          }
          return _buildRegularLandscapeContent(
            context: context,
            constraints: constraints,
            showPieceCountRows: showPieceCountRows,
          );
        }

        // Main content without bottom toolbars:
        final Widget mainContent = SizedBox(
          key: const Key('play_area_main_content'),
          width: dimension,
          child: isOfflineBoardMode
              ? _buildOfflineBoardMainContent(
                  context: context,
                  showPieceCountRows: showPieceCountRows,
                )
              : usesHumanAiBoardLayout
              ? _buildHumanAiMainContent(
                  context: context,
                  showPieceCountRows: showPieceCountRows,
                  showMoveList: !isPuzzle,
                  showPlayerPanels: !isPuzzle,
                )
              : isAnalysisMode
              ? _buildAnalysisMainContent(
                  context: context,
                  showPieceCountRows: showPieceCountRows,
                )
              : _buildRegularMainContent(
                  context: context,
                  isSetupPosition: isSetupPosition,
                  isPuzzle: isPuzzle,
                  showPieceCountRows: showPieceCountRows,
                ),
        );

        return SizedBox(
          key: const Key('play_area_sized_box_toolbar_bottom'),
          width: dimension,
          child: SafeArea(
            top: false,
            right: false,
            left: false,
            minimum: EdgeInsets.only(
              bottom: ScreenInsets.navigationBarInset(context),
            ),
            child: Column(
              key: const Key('play_area_column_toolbar_bottom'),
              children: <Widget>[
                Expanded(child: mainContent),

                // Main toolbar (or setup-position toolbar)
                if (usesLichessHumanAiToolbar)
                  _buildHumanAiBottomBar(context)
                else if (isSetupPosition)
                  const SetupPositionToolbar(
                    key: Key('play_area_setup_position_toolbar_bottom'),
                  )
                else if (!isPuzzle)
                  _buildRegularBottomBar(context),

                if (!usesLichessHumanAiToolbar)
                  const SizedBox(height: AppTheme.boardMargin),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _GameTipsActionLabel extends StatelessWidget {
  const _GameTipsActionLabel(this.enabled);

  final ValueNotifier<bool> enabled;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: enabled,
      builder: (BuildContext context, bool isEnabled, _) {
        final String label = S.of(context).showGameTips;
        return Semantics(
          label: label,
          button: true,
          toggled: isEnabled,
          child: ExcludeSemantics(
            child: Row(
              children: <Widget>[
                const Icon(Icons.tips_and_updates_outlined),
                const SizedBox(width: 15),
                Expanded(child: Text(label, textAlign: TextAlign.start)),
                const SizedBox(width: 10),
                IgnorePointer(
                  child: Switch.adaptive(
                    key: const Key('play_area_game_tips_switch'),
                    value: isEnabled,
                    onChanged: (_) {},
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _InlineMoveList extends StatefulWidget {
  const _InlineMoveList({
    super.key,
    required this.wrapKey,
    required this.moveKeyPrefix,
    this.roundKeyPrefix,
    this.onMoveTap,
    this.showMovePreview = false,
    this.showMoveActions = false,
    this.showMoveAnnotations = false,
    this.showMoveComments = false,
    this.showRootComments = false,
    this.showMainlineContinuation = false,
    this.showVariations = false,
    this.showEvaluations = false,
    this.showMiniBoards = false,
    this.usesGameSurfaceColors = true,
    this.layout = _InlineMoveListLayout.wrap,
    this.groupByRound = false,
    this.announceCompletedMove = false,
    this.maxHeight,
    this.fixedHeight,
  }) : assert(
         !groupByRound || roundKeyPrefix != null,
         'Grouped inline move lists require a round key prefix.',
       ),
       assert(
         fixedHeight == null || maxHeight == null,
         'Inline move lists must use either fixedHeight or maxHeight.',
       ),
       assert(
         fixedHeight == null || fixedHeight > 0,
         'Inline move list fixedHeight must be positive.',
       );

  final Key wrapKey;
  final String moveKeyPrefix;
  final String? roundKeyPrefix;
  final Future<void> Function(BuildContext context, PgnNode<ExtMove> node)?
  onMoveTap;
  final bool showMovePreview;
  final bool showMoveActions;
  final bool showMoveAnnotations;
  final bool showMoveComments;
  final bool showRootComments;
  final bool showMainlineContinuation;
  final bool showVariations;
  final bool showEvaluations;
  final bool showMiniBoards;
  final bool usesGameSurfaceColors;
  final _InlineMoveListLayout layout;
  final bool groupByRound;
  final bool announceCompletedMove;
  final double? maxHeight;
  final double? fixedHeight;

  @override
  State<_InlineMoveList> createState() => _InlineMoveListState();
}

List<PgnNode<ExtMove>> _recorderCurrentPathNodes(GameRecorder recorder) {
  final List<PgnNode<ExtMove>> nodes = <PgnNode<ExtMove>>[];
  PgnNode<ExtMove>? node = recorder.activeNode;
  while (node != null && node.data != null) {
    nodes.insert(0, node);
    node = node.parent;
  }
  return nodes;
}

List<PgnNode<ExtMove>> _recorderPathWithMainlineContinuation(
  GameRecorder recorder,
) {
  final List<PgnNode<ExtMove>> nodes = _recorderCurrentPathNodes(recorder);
  PgnNode<ExtMove>? node = recorder.activeNode ?? recorder.pgnRoot;
  while (node != null && node.children.isNotEmpty) {
    final PgnNode<ExtMove> next = node.children.first;
    if (nodes.contains(next)) {
      break;
    }
    nodes.add(next);
    node = next;
  }
  return nodes;
}

class _InlineMoveListState extends State<_InlineMoveList> {
  final GlobalKey _currentMoveKey = GlobalKey();
  PgnNode<ExtMove>? _lastAutoScrolledNode;
  int _analysisTreeNodeOrdinal = 0;
  int _analysisBranchOrdinal = 0;
  final Map<PgnNode<ExtMove>, int> _analysisPathIndices =
      <PgnNode<ExtMove>, int>{};

  List<PgnNode<ExtMove>> _currentPathNodes() {
    return _recorderCurrentPathNodes(GameController().gameRecorder);
  }

  List<PgnNode<ExtMove>> _displayPathNodes() {
    if (!widget.showMainlineContinuation) {
      return _currentPathNodes();
    }
    return _recorderPathWithMainlineContinuation(GameController().gameRecorder);
  }

  Color? _gameSurfaceForegroundColor() {
    if (!widget.usesGameSurfaceColors) {
      return null;
    }
    return readableForegroundColor(
      preferred: DB().colorSettings.messageColor,
      background: DB().colorSettings.darkBackgroundColor,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: GameController().gameRecorder.moveCountNotifier,
      builder: (BuildContext context, _, _) {
        final GameRecorder recorder = GameController().gameRecorder;
        final List<PgnNode<ExtMove>> nodes = _displayPathNodes();
        final PgnNode<ExtMove>? activeNode = recorder.activeNode;
        _scheduleCurrentMoveAutoScroll(activeNode);

        final bool hasRootComments = _hasRootComments();
        final String completedMoveAnnouncement = _completedMoveAnnouncement(
          context,
          _currentPathNodes(),
        );

        return Semantics(
          key: widget.announceCompletedMove
              ? const Key('play_area_completed_move_announcement')
              : null,
          container: true,
          explicitChildNodes: true,
          liveRegion: completedMoveAnnouncement.isNotEmpty,
          label: completedMoveAnnouncement,
          child: Container(
            key: widget.wrapKey,
            width: double.infinity,
            constraints: _containerConstraints(),
            padding: widget.layout == _InlineMoveListLayout.horizontal
                ? const EdgeInsets.only(left: 5)
                : const EdgeInsets.fromLTRB(12, 6, 12, 4),
            child: recorder.pgnRoot.children.isEmpty && !hasRootComments
                ? const SizedBox(height: 30)
                : widget.showVariations
                ? _buildAnalysisTree(context, recorder)
                : _buildMoves(context: context, nodes: nodes),
          ),
        );
      },
    );
  }

  Widget _buildAnalysisTree(BuildContext context, GameRecorder recorder) {
    _analysisTreeNodeOrdinal = 0;
    _analysisBranchOrdinal = 0;
    _analysisPathIndices
      ..clear()
      ..addEntries(
        _recorderCurrentPathNodes(recorder).asMap().entries.map(
          (MapEntry<int, PgnNode<ExtMove>> entry) =>
              MapEntry<PgnNode<ExtMove>, int>(entry.value, entry.key + 1),
        ),
      );
    final List<Widget> children = <Widget>[
      ?_buildRootCommentsBlock(context),
      ..._buildAnalysisMainlineSubtrees(context, recorder.pgnRoot),
    ];
    return SingleChildScrollView(
      key: const Key('play_area_inline_move_list_scroll_view'),
      child: KeyedSubtree(
        key: widget.layout == _InlineMoveListLayout.stacked
            ? const Key('play_area_inline_move_list_inline_notation')
            : widget.layout == _InlineMoveListLayout.twoColumn
            ? const Key('play_area_inline_move_list_two_column')
            : null,
        child: Column(
          key: const Key('play_area_analysis_move_tree'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }

  List<Widget> _buildAnalysisMainlineSubtrees(
    BuildContext context,
    PgnNode<ExtMove> root,
  ) {
    final List<Widget> widgets = <Widget>[];
    PgnNode<ExtMove> parent = root;
    int partIndex = 0;
    while (parent.children.isNotEmpty) {
      final List<PgnNode<ExtMove>> part = <PgnNode<ExtMove>>[];
      PgnNode<ExtMove> forkParent = parent;
      while (parent.children.isNotEmpty) {
        forkParent = parent;
        final PgnNode<ExtMove> mainlineMove = parent.children.first;
        part.add(mainlineMove);
        parent = mainlineMove;
        if (forkParent.children.length > 1) {
          break;
        }
      }
      partIndex++;
      widgets.add(_buildAnalysisMainlinePart(context, part, partIndex));
      if (forkParent.children.length > 1) {
        widgets.add(
          _buildAnalysisIndentedSidelines(
            context,
            forkParent.children.skip(1).toList(growable: false),
            depth: 1,
          ),
        );
      }
    }
    return widgets;
  }

  Widget _buildAnalysisMainlinePart(
    BuildContext context,
    List<PgnNode<ExtMove>> nodes,
    int partIndex,
  ) {
    assert(nodes.isNotEmpty, 'Analysis mainline parts cannot be empty.');
    final ThemeData theme = Theme.of(context);
    final List<_InlineMoveRound> rounds = _buildAnalysisMoveRounds(nodes);
    final List<_InlineMoveSegment> segments = <_InlineMoveSegment>[
      for (final _InlineMoveRound round in rounds) ...round.segments,
    ];
    return DecoratedBox(
      key: Key('play_area_analysis_mainline_part_$partIndex'),
      decoration: BoxDecoration(
        color: theme.brightness == Brightness.dark
            ? Colors.white.withValues(alpha: 0.045)
            : Colors.black.withValues(alpha: 0.025),
        border: Border(
          top: BorderSide(color: theme.dividerColor.withValues(alpha: 0.7)),
        ),
      ),
      child: widget.layout == _InlineMoveListLayout.stacked
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  return _BoundedMoveWrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: <Widget>[
                      for (int i = 0; i < segments.length; i++)
                        _buildMoveSegment(
                          context,
                          segments[i],
                          maxWidth: constraints.maxWidth,
                          allowMultiline: true,
                          isSideline: false,
                          showMoveIndex:
                              i == 0 || segments[i].side == PieceColor.white,
                          showEvaluation: true,
                        ),
                    ],
                  );
                },
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                for (final _InlineMoveRound round in rounds)
                  _buildMoveRoundTableRow(context, round),
              ],
            ),
    );
  }

  Widget _buildAnalysisIndentedSidelines(
    BuildContext context,
    List<PgnNode<ExtMove>> sidelines, {
    required int depth,
  }) {
    assert(sidelines.isNotEmpty, 'Indented sidelines cannot be empty.');
    final Color guideColor = Theme.of(
      context,
    ).colorScheme.onSurface.withValues(alpha: 0.3);
    return Padding(
      padding: EdgeInsets.only(left: depth <= 6 ? 10 : 0, right: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (int i = 0; i < sidelines.length; i++)
            CustomPaint(
              key: Key(
                'play_area_analysis_branch_gutter_${++_analysisBranchOrdinal}',
              ),
              painter: _AnalysisBranchGuidePainter(
                color: guideColor,
                isLast: i == sidelines.length - 1,
              ),
              child: Padding(
                padding: const EdgeInsets.only(left: 12),
                child: _buildAnalysisSideline(
                  context,
                  sidelines[i],
                  depth: depth,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAnalysisSideline(
    BuildContext context,
    PgnNode<ExtMove> firstNode, {
    required int depth,
  }) {
    final List<PgnNode<ExtMove>> part = <PgnNode<ExtMove>>[firstNode];
    PgnNode<ExtMove> node = firstNode;
    while (node.children.length == 1) {
      node = node.children.first;
      part.add(node);
    }
    final List<_InlineMoveRound> rounds = _buildAnalysisMoveRounds(part);
    final List<_InlineMoveSegment> segments = <_InlineMoveSegment>[
      for (final _InlineMoveRound round in rounds) ...round.segments,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              return _BoundedMoveWrap(
                spacing: 4,
                runSpacing: 4,
                children: <Widget>[
                  for (int i = 0; i < segments.length; i++)
                    _buildMoveSegment(
                      context,
                      segments[i],
                      maxWidth: constraints.maxWidth,
                      allowMultiline: true,
                      isSideline: true,
                      showMoveIndex:
                          i == 0 || segments[i].side == PieceColor.white,
                      showEvaluation: false,
                    ),
                ],
              );
            },
          ),
        ),
        if (node.children.length > 1)
          _buildAnalysisIndentedSidelines(
            context,
            node.children,
            depth: depth + 1,
          ),
      ],
    );
  }

  List<_InlineMoveRound> _buildAnalysisMoveRounds(
    List<PgnNode<ExtMove>> nodes,
  ) {
    final List<_InlineMoveRound> rounds = <_InlineMoveRound>[];
    for (final PgnNode<ExtMove> node in nodes) {
      final ExtMove move = node.data!;
      final int roundNumber = move.roundIndex ?? _analysisRoundNumber(node);
      final _InlineMoveRound round;
      if (rounds.isNotEmpty && rounds.last.number == roundNumber) {
        round = rounds.last;
      } else {
        round = _InlineMoveRound(roundNumber);
        rounds.add(round);
      }
      final _InlineMoveSegment segment;
      if (round.segments.isNotEmpty && round.segments.last.side == move.side) {
        segment = round.segments.last;
      } else {
        segment = _InlineMoveSegment(side: move.side);
        round.segments.add(segment);
      }
      _analysisTreeNodeOrdinal++;
      segment.nodes.add(
        _IndexedMoveNode(index: _analysisTreeNodeOrdinal - 1, node: node),
      );
    }
    return rounds;
  }

  int _analysisRoundNumber(PgnNode<ExtMove> node) {
    final List<PgnNode<ExtMove>> path = <PgnNode<ExtMove>>[];
    PgnNode<ExtMove>? current = node;
    while (current?.data != null) {
      path.insert(0, current!);
      current = current.parent;
    }
    int round = 1;
    PieceColor? previousSide;
    for (final PgnNode<ExtMove> pathNode in path) {
      final PieceColor side = pathNode.data!.side;
      if (previousSide == PieceColor.black && side == PieceColor.white) {
        round++;
      }
      if (identical(pathNode, node)) {
        return round;
      }
      previousSide = side;
    }
    return round;
  }

  String _completedMoveAnnouncement(
    BuildContext context,
    List<PgnNode<ExtMove>> nodes,
  ) {
    if (!widget.announceCompletedMove || nodes.isEmpty) {
      return '';
    }

    int end = nodes.length;
    if (GameController().activeBoardView.action == Act.remove) {
      final PieceColor pendingSide = nodes.last.data!.side;
      while (end > 0 && nodes[end - 1].data!.side == pendingSide) {
        end--;
      }
    }
    if (end == 0) {
      return '';
    }

    final PieceColor side = nodes[end - 1].data!.side;
    int start = end - 1;
    while (start > 0 && nodes[start - 1].data!.side == side) {
      start--;
    }

    final StringBuffer notation = StringBuffer();
    for (int i = start; i < end; i++) {
      final String part = _moveLabel(nodes[i].data!, includeComments: false);
      if (notation.isNotEmpty && !part.startsWith('x')) {
        notation.write(' ');
      }
      notation.write(part);
    }

    return '${side.playerName(context)}. '
        '${S.of(context).lastMove(notation.toString().toUpperCase())}';
  }

  BoxConstraints _containerConstraints() {
    if (widget.fixedHeight != null) {
      return BoxConstraints.tightFor(height: widget.fixedHeight);
    }

    return switch (widget.layout) {
      _InlineMoveListLayout.horizontal => const BoxConstraints.tightFor(
        height: PlayAreaState._kInlineMoveListHeight,
      ),
      _InlineMoveListLayout.wrap ||
      _InlineMoveListLayout.stacked ||
      _InlineMoveListLayout.twoColumn => BoxConstraints(
        minHeight: 40,
        maxHeight: widget.maxHeight ?? double.infinity,
      ),
    };
  }

  void _scheduleCurrentMoveAutoScroll(PgnNode<ExtMove>? activeNode) {
    if (widget.layout == _InlineMoveListLayout.wrap ||
        activeNode == null ||
        identical(_lastAutoScrolledNode, activeNode)) {
      return;
    }

    _lastAutoScrolledNode = activeNode;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final BuildContext? currentMoveContext = _currentMoveKey.currentContext;
      if (currentMoveContext == null) {
        return;
      }
      Scrollable.ensureVisible(
        currentMoveContext,
        alignment: 0.5,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeIn,
      );
    });
  }

  Widget _buildMoves({
    required BuildContext context,
    required List<PgnNode<ExtMove>> nodes,
  }) {
    if (widget.groupByRound) {
      return _buildGroupedMoves(context: context, nodes: nodes);
    }

    final Widget? rootComments = _buildRootCommentsBlock(context);
    final List<Widget> chips = <Widget>[
      ?rootComments,
      for (int i = 0; i < nodes.length; i++) _buildMoveChip(context, nodes, i),
    ];

    return switch (widget.layout) {
      _InlineMoveListLayout.wrap => Wrap(
        spacing: 4,
        runSpacing: 4,
        children: chips,
      ),
      _InlineMoveListLayout.stacked => SingleChildScrollView(
        key: const Key('play_area_inline_move_list_scroll_view'),
        child: _BoundedMoveWrap(spacing: 4, runSpacing: 4, children: chips),
      ),
      _InlineMoveListLayout.twoColumn => SingleChildScrollView(
        key: const Key('play_area_inline_move_list_scroll_view'),
        child: _BoundedMoveWrap(spacing: 4, runSpacing: 4, children: chips),
      ),
      _InlineMoveListLayout.horizontal => SingleChildScrollView(
        key: const Key('play_area_inline_move_list_scroll_view'),
        scrollDirection: Axis.horizontal,
        child: Row(children: _spaceMoveChips(chips)),
      ),
    };
  }

  Widget _buildGroupedMoves({
    required BuildContext context,
    required List<PgnNode<ExtMove>> nodes,
  }) {
    final List<_InlineMoveRound> rounds = _buildMoveRounds(nodes);
    final Widget? rootComments = _buildRootCommentsBlock(context);
    final List<Widget> roundChildren = <Widget>[
      ?rootComments,
      for (final _InlineMoveRound round in rounds)
        _buildMoveRound(context, round),
    ];
    final List<Widget> wrappedChildren = <Widget>[
      ?rootComments,
      for (final _InlineMoveRound round in rounds)
        ..._buildMoveRoundWrapChildren(context, round),
    ];

    return switch (widget.layout) {
      _InlineMoveListLayout.horizontal => SingleChildScrollView(
        key: const Key('play_area_inline_move_list_scroll_view'),
        scrollDirection: Axis.horizontal,
        child: Row(children: _spaceMoveChips(roundChildren)),
      ),
      _InlineMoveListLayout.stacked => SingleChildScrollView(
        key: const Key('play_area_inline_move_list_scroll_view'),
        child: _BoundedMoveWrap(
          key: const Key('play_area_inline_move_list_inline_notation'),
          spacing: 8,
          runSpacing: 6,
          children: wrappedChildren,
        ),
      ),
      _InlineMoveListLayout.twoColumn => SingleChildScrollView(
        key: const Key('play_area_inline_move_list_scroll_view'),
        child: Column(
          key: const Key('play_area_inline_move_list_two_column'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            ?rootComments,
            for (final _InlineMoveRound round in rounds)
              _buildMoveRoundTableRow(context, round),
          ],
        ),
      ),
      _InlineMoveListLayout.wrap => Wrap(
        spacing: 8,
        runSpacing: 6,
        children: wrappedChildren,
      ),
    };
  }

  List<_InlineMoveRound> _buildMoveRounds(List<PgnNode<ExtMove>> nodes) {
    final List<_InlineMoveRound> rounds = <_InlineMoveRound>[];
    PieceColor? firstSide;
    PieceColor? previousSide;
    int computedRound = 1;

    for (int i = 0; i < nodes.length; i++) {
      final ExtMove? move = nodes[i].data;
      assert(move != null, 'Inline move list nodes must carry move data.');
      final PieceColor side = move!.side;
      assert(
        side == PieceColor.white || side == PieceColor.black,
        'Inline move list requires a playable side, got $side.',
      );

      firstSide ??= side;
      if (previousSide != null &&
          side == firstSide &&
          previousSide != firstSide) {
        computedRound++;
      }
      previousSide = side;

      final int roundNumber = move.roundIndex ?? computedRound;
      final _InlineMoveRound round;
      if (rounds.isNotEmpty && rounds.last.number == roundNumber) {
        round = rounds.last;
      } else {
        round = _InlineMoveRound(roundNumber);
        rounds.add(round);
      }

      final _InlineMoveSegment segment;
      if (round.segments.isNotEmpty && round.segments.last.side == side) {
        segment = round.segments.last;
      } else {
        segment = _InlineMoveSegment(side: side);
        round.segments.add(segment);
      }
      segment.nodes.add(_IndexedMoveNode(index: i, node: nodes[i]));
    }

    return rounds;
  }

  bool _hasRootComments() {
    return widget.layout != _InlineMoveListLayout.horizontal &&
        _rootCommentsLabel().isNotEmpty;
  }

  Widget? _buildRootCommentsBlock(BuildContext context) {
    final String label = _rootCommentsLabel();
    if (label.isEmpty || widget.layout == _InlineMoveListLayout.horizontal) {
      return null;
    }

    final TextStyle style = _inlineMoveListTextStyle(context).copyWith(
      color:
          _gameSurfaceForegroundColor() ??
          Theme.of(context).colorScheme.onSurfaceVariant,
    );
    return LayoutBuilder(
      key: const Key('play_area_analysis_root_comments'),
      builder: (BuildContext context, BoxConstraints constraints) {
        return SizedBox(
          width: constraints.maxWidth,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(label, style: style, textDirection: TextDirection.ltr),
          ),
        );
      },
    );
  }

  String _rootCommentsLabel() {
    if (!widget.showRootComments || !widget.showMoveComments) {
      return '';
    }
    return _commentsLabel(GameController().gameRecorder.rootComments);
  }

  Widget _buildMoveRound(BuildContext context, _InlineMoveRound round) {
    final String roundKeyPrefix = widget.roundKeyPrefix!;
    return Row(
      key: Key('$roundKeyPrefix${round.number}'),
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _InlineMoveCount(
          count: round.number,
          foregroundColor: _gameSurfaceForegroundColor(),
        ),
        for (final _InlineMoveSegment segment in round.segments)
          _buildMoveSegment(context, segment),
      ],
    );
  }

  Widget _buildMoveRoundTableRow(BuildContext context, _InlineMoveRound round) {
    final ThemeData theme = Theme.of(context);
    final String roundKeyPrefix = widget.roundKeyPrefix!;
    return DecoratedBox(
      key: Key('$roundKeyPrefix${round.number}'),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: theme.dividerColor.withValues(alpha: 0.7)),
        ),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: widget.showMiniBoards ? 76 : 40),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(
              width: widget.showVariations ? 50 : 34,
              child: Padding(
                padding: const EdgeInsets.only(top: 9, left: 2),
                child: _InlineMoveCount(
                  count: round.number,
                  foregroundColor: _gameSurfaceForegroundColor(),
                  fontSize: widget.showVariations ? 16 : null,
                ),
              ),
            ),
            Expanded(
              child: _buildMoveRoundTableCell(context, round, PieceColor.white),
            ),
            Expanded(
              child: _buildMoveRoundTableCell(context, round, PieceColor.black),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMoveRoundTableCell(
    BuildContext context,
    _InlineMoveRound round,
    PieceColor side,
  ) {
    final List<_InlineMoveSegment> segments = round.segments
        .where((_InlineMoveSegment segment) => segment.side == side)
        .toList(growable: false);
    if (segments.isEmpty) {
      return SizedBox(height: widget.showMiniBoards ? 76 : 40);
    }
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              for (final _InlineMoveSegment segment in segments)
                _buildMoveSegment(
                  context,
                  segment,
                  maxWidth: constraints.maxWidth - 8,
                  allowMultiline: true,
                ),
            ],
          ),
        );
      },
    );
  }

  TextStyle _analysisTreeTextStyle(
    BuildContext context, {
    required bool isSideline,
  }) {
    final Color onSurface = Theme.of(context).colorScheme.onSurface;
    return (Theme.of(context).textTheme.bodyLarge ??
            const TextStyle(fontSize: 16))
        .copyWith(
          color: onSurface.withValues(alpha: isSideline ? 0.6 : 0.9),
          fontFamily: null,
          fontSize: isSideline ? 15 : 16,
          fontWeight: FontWeight.w600,
          height: 1.5,
          letterSpacing: 0,
        );
  }

  String? _analysisEvaluationLabel(PgnNode<ExtMove> node) {
    if (!widget.showEvaluations) {
      return null;
    }
    final int? evaluation = node.data?.analysisEvaluation;
    if (evaluation == null) {
      return null;
    }
    return evaluation > 0 ? '+$evaluation' : '$evaluation';
  }

  Widget _analysisMiniBoard(
    BuildContext context,
    PgnNode<ExtMove> node,
    double size,
  ) {
    final String boardLayout = node.data!.boardLayout!;
    return Semantics(
      image: true,
      label: S.of(context).boardPreviews,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(
          math.min(DB().displaySettings.boardCornerRadius, 4),
        ),
        child: ColoredBox(
          color: DB().colorSettings.boardBackgroundColor,
          child: SizedBox.square(
            dimension: size,
            child: CustomPaint(
              painter: MiniBoardPainter(boardLayout: boardLayout),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildMoveRoundWrapChildren(
    BuildContext context,
    _InlineMoveRound round,
  ) {
    assert(
      round.segments.isNotEmpty,
      'Inline move rounds must contain at least one move segment.',
    );
    final String roundKeyPrefix = widget.roundKeyPrefix!;
    final List<Widget> children = <Widget>[
      LayoutBuilder(
        key: Key('$roundKeyPrefix${round.number}'),
        builder: (BuildContext context, BoxConstraints constraints) {
          assert(
            constraints.hasBoundedWidth,
            'Inline move round wrapping requires a bounded width.',
          );
          final double segmentMaxWidth = math.max(0, constraints.maxWidth - 36);
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _InlineMoveCount(
                count: round.number,
                foregroundColor: _gameSurfaceForegroundColor(),
              ),
              _buildMoveSegment(
                context,
                round.segments.first,
                maxWidth: segmentMaxWidth,
                allowMultiline: true,
              ),
            ],
          );
        },
      ),
      for (final _InlineMoveSegment segment in round.segments.skip(1))
        _buildMoveSegment(context, segment, allowMultiline: true),
    ];
    return children;
  }

  Widget _buildMoveSegment(
    BuildContext context,
    _InlineMoveSegment segment, {
    double? maxWidth,
    bool allowMultiline = false,
    bool isSideline = false,
    bool showMoveIndex = false,
    bool showEvaluation = true,
  }) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final PgnNode<ExtMove>? activeNode =
        GameController().gameRecorder.activeNode;
    final bool selected = segment.nodes.any(
      (_IndexedMoveNode indexed) => indexed.node == activeNode,
    );
    final _IndexedMoveNode lastNode = segment.nodes.last;
    final StringBuffer labelBuffer = StringBuffer();
    for (final _IndexedMoveNode indexed in segment.nodes) {
      final String moveLabel = _moveLabel(
        indexed.node.data!,
        includeComments: false,
      );
      if (labelBuffer.isNotEmpty && !moveLabel.startsWith('x')) {
        labelBuffer.write(' ');
      }
      labelBuffer.write(moveLabel);
    }
    final String label = labelBuffer.toString();
    String displayLabel = _withMoveComments(label, lastNode.node.data!);
    if (showMoveIndex) {
      final int round =
          lastNode.node.data!.roundIndex ?? _analysisRoundNumber(lastNode.node);
      final String marker = segment.side == PieceColor.black ? '...' : '.';
      displayLabel = '$round$marker $displayLabel';
    }
    final PgnNode<ExtMove> targetNode = lastNode.node;
    final int? pathIndex = _analysisPathIndices[targetNode];
    final Key moveKey = widget.showVariations && pathIndex == null
        ? Key('${widget.moveKeyPrefix}tree_${lastNode.index + 1}')
        : Key('${widget.moveKeyPrefix}${pathIndex ?? lastNode.index + 1}');
    final Widget chip = _GameMoveChip(
      key: moveKey,
      label: displayLabel,
      selected: selected,
      selectedColor: colorScheme.primaryContainer,
      selectedTextColor: colorScheme.onPrimaryContainer,
      textStyle: widget.showVariations
          ? _analysisTreeTextStyle(context, isSideline: isSideline)
          : _inlineMoveListTextStyle(
              context,
            ).copyWith(color: _gameSurfaceForegroundColor()),
      style: _GameMoveChipStyle.inlineText,
      fontWeight: widget.showVariations ? FontWeight.w600 : null,
      maxLines: allowMultiline ? null : 1,
      onTap: widget.onMoveTap == null
          ? null
          : () => unawaited(widget.onMoveTap!(context, targetNode)),
      onLongPress:
          widget.showMoveActions ||
              (widget.showMovePreview && _hasPreviewBoard(targetNode))
          ? () => _handleMoveLongPress(context, targetNode, lastNode.index + 1)
          : null,
    );
    final String? evaluation = showEvaluation
        ? _analysisEvaluationLabel(targetNode)
        : null;
    final bool showMiniBoard =
        widget.showMiniBoards && _hasPreviewBoard(targetNode);
    final Widget result;
    if (!widget.showVariations || (evaluation == null && !showMiniBoard)) {
      result = maxWidth == null
          ? chip
          : ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: chip,
            );
    } else {
      result = ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth ?? double.infinity),
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final double availableWidth = constraints.hasBoundedWidth
                ? constraints.maxWidth
                : 220;
            final double boardSize = math.min(
              68,
              math.max(44, availableWidth * 0.32),
            );
            final Widget? eval = evaluation == null
                ? null
                : Text(
                    evaluation,
                    key: Key(
                      'play_area_analysis_move_evaluation_${lastNode.index + 1}',
                    ),
                    style:
                        (Theme.of(context).textTheme.bodySmall ??
                                const TextStyle())
                            .copyWith(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurface.withValues(alpha: 0.4),
                              fontFamily: null,
                              fontSize: 13,
                              fontWeight: FontWeight.w400,
                              letterSpacing: 0,
                            ),
                  );
            final Widget? board = showMiniBoard
                ? KeyedSubtree(
                    key: Key(
                      'play_area_analysis_move_mini_board_${lastNode.index + 1}',
                    ),
                    child: _analysisMiniBoard(context, targetNode, boardSize),
                  )
                : null;
            if (availableWidth >= 140) {
              return Row(
                mainAxisSize: MainAxisSize.max,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  Flexible(child: chip),
                  if (eval != null) ...<Widget>[const SizedBox(width: 4), eval],
                  if (board != null) ...<Widget>[
                    const SizedBox(width: 6),
                    board,
                  ],
                ],
              );
            }
            return Wrap(
              spacing: 4,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: availableWidth),
                  child: chip,
                ),
                ?eval,
                ?board,
              ],
            );
          },
        ),
      );
    }

    if (selected) {
      return KeyedSubtree(key: _currentMoveKey, child: result);
    }
    return result;
  }

  Widget _buildMoveChip(
    BuildContext context,
    List<PgnNode<ExtMove>> nodes,
    int index,
  ) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final PgnNode<ExtMove> node = nodes[index];
    final PgnNode<ExtMove>? activeNode =
        GameController().gameRecorder.activeNode;
    final bool selected = node == activeNode;
    final Widget chip = _GameMoveChip(
      key: Key('${widget.moveKeyPrefix}${index + 1}'),
      label: '${index + 1}. ${_moveLabel(node.data!, includeComments: true)}',
      selected: selected,
      selectedColor: colorScheme.primaryContainer,
      selectedTextColor: colorScheme.onPrimaryContainer,
      textStyle: _inlineMoveListTextStyle(
        context,
      ).copyWith(color: _gameSurfaceForegroundColor()),
      style: widget.layout == _InlineMoveListLayout.horizontal
          ? _GameMoveChipStyle.inlineText
          : _GameMoveChipStyle.filled,
      onTap: widget.onMoveTap == null
          ? null
          : () => unawaited(widget.onMoveTap!(context, node)),
      onLongPress:
          widget.showMoveActions ||
              (widget.showMovePreview && _hasPreviewBoard(node))
          ? () => _handleMoveLongPress(context, node, index + 1)
          : null,
    );

    if (widget.layout == _InlineMoveListLayout.horizontal && selected) {
      return KeyedSubtree(key: _currentMoveKey, child: chip);
    }
    return chip;
  }

  String _moveLabel(ExtMove move, {required bool includeComments}) {
    String label = widget.showMoveAnnotations
        ? _notationWithNagSymbols(move.notation, move.getAllNags())
        : move.notation;
    if (includeComments) {
      label = _withMoveComments(label, move);
    }
    return label;
  }

  String _withMoveComments(String label, ExtMove move) {
    if (!widget.showMoveComments) {
      return label;
    }

    final String startingComments = _commentsLabel(move.startingComments);
    final String comments = _commentsLabel(move.comments);
    final List<String> parts = <String>[
      if (startingComments.isNotEmpty) startingComments,
      label,
      if (comments.isNotEmpty) comments,
    ];
    return parts.join(' ');
  }

  String _commentsLabel(List<String>? comments) {
    if (comments == null || comments.isEmpty) {
      return '';
    }
    return comments
        .map((String comment) => safeComment(comment).trim())
        .where((String comment) => comment.isNotEmpty)
        .map((String comment) => '{$comment}')
        .join(' ');
  }

  List<Widget> _spaceMoveChips(List<Widget> chips) {
    final List<Widget> spaced = <Widget>[];
    for (int i = 0; i < chips.length; i++) {
      if (i > 0) {
        spaced.add(const SizedBox(width: 10));
      }
      spaced.add(chips[i]);
    }
    return spaced;
  }

  bool _hasPreviewBoard(PgnNode<ExtMove> node) {
    final String? boardLayout = node.data?.boardLayout;
    return boardLayout != null && boardLayout.isNotEmpty;
  }

  void _handleMoveLongPress(
    BuildContext context,
    PgnNode<ExtMove> node,
    int moveNumber,
  ) {
    if (widget.showMoveActions) {
      _showMoveActions(context, node, moveNumber);
      return;
    }

    if (widget.showMovePreview && _hasPreviewBoard(node)) {
      _showMovePreview(context, node, moveNumber);
    }
  }

  void _showMoveActions(
    BuildContext context,
    PgnNode<ExtMove> node,
    int moveNumber,
  ) {
    final ExtMove? move = node.data;
    assert(move != null, 'Move actions require node data.');
    final bool canPromote = _isNodeOnVariationBranch(node);
    final int? selectedQualityNag = _qualityNagForMove(move!);
    showLichessActionSheet<void>(
      context: context,
      sheetKey: const Key('play_area_analysis_move_actions_sheet'),
      title: Text(
        '$moveNumber. ${_moveLabel(move, includeComments: false)}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textDirection: TextDirection.ltr,
      ),
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
      foregroundColor: Theme.of(context).colorScheme.onSurface,
      actions: <LichessActionSheetAction>[
        LichessActionSheetAction(
          key: const Key('play_area_analysis_move_action_quality_annotation'),
          leading: const Icon(Icons.new_label_outlined),
          trailing: selectedQualityNag == null
              ? null
              : Text(
                  qualityNagSymbol(selectedQualityNag),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
          makeLabel: (BuildContext context) =>
              Text(S.of(context).qualityAnnotation),
          onPressed: () => unawaited(
            _showMoveQualityAnnotation(context, node, selectedQualityNag),
          ),
        ),
        if (_hasPreviewBoard(node))
          LichessActionSheetAction(
            key: const Key('play_area_analysis_move_action_preview_board'),
            leading: const Icon(Icons.grid_view_rounded),
            makeLabel: (BuildContext context) => Text(S.of(context).board),
            onPressed: () =>
                unawaited(_showMovePreview(context, node, moveNumber)),
          ),
        if (canPromote)
          LichessActionSheetAction(
            key: const Key(
              'play_area_analysis_move_action_make_primary_variation',
            ),
            leading: const Icon(Icons.vertical_align_top_rounded),
            makeLabel: (BuildContext context) =>
                Text(S.of(context).makeThisPrimaryVariation),
            onPressed: () => unawaited(_promoteNearestVariation(context, node)),
          ),
        if (canPromote)
          LichessActionSheetAction(
            key: const Key('play_area_analysis_move_action_set_main_line'),
            leading: const Icon(Icons.check),
            makeLabel: (BuildContext context) =>
                Text(S.of(context).setAsMainLine),
            onPressed: () =>
                unawaited(_promoteMovePathToMainline(context, node)),
          ),
        LichessActionSheetAction(
          key: const Key('play_area_analysis_move_action_delete_from_here'),
          leading: const Icon(Icons.delete_outline),
          isDestructiveAction: true,
          makeLabel: (BuildContext context) =>
              Text(S.of(context).deleteCurrentBranch),
          onPressed: () => unawaited(_deleteMoveFromHere(context, node)),
        ),
      ],
    );
  }

  Future<void> _showMoveQualityAnnotation(
    BuildContext context,
    PgnNode<ExtMove> node,
    int? selectedNag,
  ) {
    return showQualityAnnotationSheet(
      context: context,
      selectedNag: selectedNag,
      keyPrefix: 'analysis_nag',
      onChanged: (int? nag) {
        GameController().gameRecorder.setMoveQualityNag(node, nag);
      },
    );
  }

  Future<void> _navigateToMoveNode(
    BuildContext context,
    PgnNode<ExtMove> node,
  ) {
    final Future<void> Function(BuildContext, PgnNode<ExtMove>)? onMoveTap =
        widget.onMoveTap;
    if (onMoveTap != null) {
      return onMoveTap(context, node);
    }
    return HistoryNavigator.gotoNode(context, node, pop: false);
  }

  int? _qualityNagForMove(ExtMove move) {
    for (final int nag in move.getAllNags()) {
      if (nag >= 1 && nag <= 6) {
        return nag;
      }
    }
    return null;
  }

  Future<void> _promoteNearestVariation(
    BuildContext context,
    PgnNode<ExtMove> node,
  ) async {
    final PgnNode<ExtMove>? variationNode = _nearestVariationNode(node);
    assert(
      variationNode != null,
      'Only variation paths can promote a primary variation.',
    );
    if (variationNode == null) {
      return;
    }

    final bool promoted = GameController().gameRecorder
        .promoteVariationToMainline(variationNode);
    assert(promoted, 'Variation promotion must update the recorder tree.');
    if (!promoted || !context.mounted) {
      return;
    }
    await _navigateToMoveNode(context, node);
  }

  Future<void> _promoteMovePathToMainline(
    BuildContext context,
    PgnNode<ExtMove> node,
  ) async {
    assert(
      _isNodeOnVariationBranch(node),
      'Only variation paths can be promoted to mainline.',
    );
    final GameRecorder recorder = GameController().gameRecorder;
    bool changed = false;
    for (final PgnNode<ExtMove> pathNode in _pathNodesFromRoot(node)) {
      final PgnNode<ExtMove>? nullableParent = pathNode.parent;
      assert(nullableParent != null, 'Move path nodes must have a parent.');
      if (nullableParent == null) {
        return;
      }
      final PgnNode<ExtMove> parent = nullableParent;
      assert(
        parent.children.contains(pathNode),
        'Move path nodes must be attached to their parent.',
      );
      if (parent.children.isNotEmpty &&
          !identical(parent.children.first, pathNode)) {
        final bool promoted = recorder.promoteVariationToMainline(pathNode);
        assert(promoted, 'Variation promotion must update the recorder tree.');
        if (!promoted) {
          return;
        }
        changed = true;
      }
    }

    assert(
      changed,
      'Promoting a variation path must update at least one node.',
    );
    if (!changed || !context.mounted) {
      return;
    }
    await _navigateToMoveNode(context, node);
  }

  Future<void> _deleteMoveFromHere(
    BuildContext context,
    PgnNode<ExtMove> node,
  ) async {
    final PgnNode<ExtMove>? parent = node.parent;
    assert(parent != null, 'Cannot delete from the root move list node.');
    if (parent == null) {
      return;
    }

    final GameRecorder recorder = GameController().gameRecorder;
    final bool activeWasDeleted = _isNodeOrDescendant(
      node,
      recorder.activeNode,
    );
    final bool deleted = recorder.deleteBranch(node);
    assert(deleted, 'Move deletion must update the recorder tree.');
    if (!deleted || !activeWasDeleted || !context.mounted) {
      return;
    }
    await _navigateToMoveNode(context, parent);
  }

  List<PgnNode<ExtMove>> _pathNodesFromRoot(PgnNode<ExtMove> node) {
    final List<PgnNode<ExtMove>> nodes = <PgnNode<ExtMove>>[];
    PgnNode<ExtMove>? current = node;
    while (current != null && current.data != null) {
      nodes.insert(0, current);
      current = current.parent;
    }
    return nodes;
  }

  bool _isNodeOnVariationBranch(PgnNode<ExtMove> node) {
    PgnNode<ExtMove>? current = node;
    while (current != null && current.parent != null) {
      final PgnNode<ExtMove> parent = current.parent!;
      assert(
        parent.children.contains(current),
        'Move node must be attached to its parent.',
      );
      if (parent.children.isNotEmpty &&
          !identical(parent.children.first, current)) {
        return true;
      }
      current = parent;
    }
    return false;
  }

  PgnNode<ExtMove>? _nearestVariationNode(PgnNode<ExtMove> node) {
    PgnNode<ExtMove>? current = node;
    while (current != null && current.parent != null) {
      final PgnNode<ExtMove> parent = current.parent!;
      assert(
        parent.children.contains(current),
        'Move node must be attached to its parent.',
      );
      if (parent.children.isNotEmpty &&
          !identical(parent.children.first, current)) {
        return current;
      }
      current = parent;
    }
    return null;
  }

  bool _isNodeOrDescendant(
    PgnNode<ExtMove> node,
    PgnNode<ExtMove>? targetNode,
  ) {
    PgnNode<ExtMove>? current = targetNode;
    while (current != null) {
      if (identical(current, node)) {
        return true;
      }
      current = current.parent;
    }
    return false;
  }

  Future<void> _showMovePreview(
    BuildContext context,
    PgnNode<ExtMove> node,
    int moveNumber,
  ) {
    final ExtMove? move = node.data;
    assert(move != null, 'Move preview requires node data.');
    final String? boardLayout = move?.boardLayout;
    assert(
      boardLayout != null && boardLayout.isNotEmpty,
      'Move preview requires a board layout.',
    );

    return showDialog<void>(
      context: context,
      useRootNavigator: false,
      builder: (BuildContext dialogContext) {
        final ThemeData theme = Theme.of(dialogContext);
        final ColorScheme colorScheme = theme.colorScheme;
        final String label = '$moveNumber. ${move!.notation}';

        return Dialog(
          key: const Key('play_area_move_preview_dialog'),
          child: Padding(
            padding: const EdgeInsets.all(AppStyles.bodyPadding),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textDirection: TextDirection.ltr,
                        style: AppStyles.sectionTitle.copyWith(
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ),
                    IconButton.filledTonal(
                      key: const Key('play_area_move_preview_go_button'),
                      tooltip: S.of(dialogContext).moveList,
                      icon: const Icon(Icons.my_location_rounded),
                      onPressed: () {
                        Navigator.of(dialogContext).pop();
                        unawaited(_navigateToMoveNode(context, node));
                      },
                    ),
                    IconButton(
                      key: const Key('play_area_move_preview_close_button'),
                      tooltip: S.of(dialogContext).close,
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.of(dialogContext).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: 300,
                    maxHeight: 300,
                  ),
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: MiniBoard(
                      key: const Key('play_area_move_preview_board'),
                      boardLayout: boardLayout!,
                      extMove: move,
                      node: node,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PositionalAdvantageIndicator extends StatelessWidget {
  const _PositionalAdvantageIndicator({
    required this.value,
    required this.whiteAtBottom,
    this.axis = Axis.vertical,
    this.appliedAiMoveEvaluation,
  }) : assert(value >= -100 && value <= 100);

  final int value;
  final bool whiteAtBottom;
  final Axis axis;
  final AppliedAiMoveEvaluation? appliedAiMoveEvaluation;

  @override
  Widget build(BuildContext context) {
    final Color whiteColor = DB().colorSettings.whitePieceColor;
    final Color blackColor = DB().colorSettings.blackPieceColor;
    final double whiteFraction = ((value + 100) / 200).clamp(0.0, 1.0);
    final HumanDatabaseMoveStats? humanStats =
        appliedAiMoveEvaluation?.source == AiMoveType.humanDatabase
        ? appliedAiMoveEvaluation!.humanDatabaseStats
        : null;
    final bool? moverWasWhite =
        appliedAiMoveEvaluation?.humanDatabaseMoverWasWhite;
    final String semanticsValue = humanStats == null
        ? value.toString()
        : S
              .of(context)
              .humanGameDatabaseStatsSemantics(
                humanStats.notation,
                humanStats.winPercent.toStringAsFixed(1),
                humanStats.drawPercent.toStringAsFixed(1),
                humanStats.lossPercent.toStringAsFixed(1),
                humanStats.total,
              );

    return Semantics(
      key: const Key('play_area_advantage_indicator'),
      label: S.of(context).showPositionalAdvantageIndicator,
      value: semanticsValue,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            color: Theme.of(
              context,
            ).colorScheme.surface.withValues(alpha: 0.74),
            border: Border.all(
              color: DB().colorSettings.messageColor.withValues(alpha: 0.78),
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.22),
                blurRadius: 3,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final double primaryExtent = axis == Axis.vertical
                    ? constraints.maxHeight
                    : constraints.maxWidth;
                final bool firstIsWhite = axis == Axis.vertical
                    ? !whiteAtBottom
                    : whiteAtBottom;
                final double humanWhiteFraction = humanStats == null
                    ? whiteFraction
                    : (moverWasWhite! ? humanStats.wins : humanStats.losses) /
                          humanStats.total;
                final double humanBlackFraction = humanStats == null
                    ? 1 - whiteFraction
                    : (moverWasWhite! ? humanStats.losses : humanStats.wins) /
                          humanStats.total;
                final double drawFraction = humanStats == null
                    ? 0
                    : humanStats.draws / humanStats.total;
                final List<({Key key, double fraction, Color color})> sections =
                    <({Key key, double fraction, Color color})>[
                      (
                        key: firstIsWhite
                            ? const Key('play_area_advantage_white_section')
                            : const Key('play_area_advantage_black_section'),
                        fraction: firstIsWhite
                            ? humanWhiteFraction
                            : humanBlackFraction,
                        color: firstIsWhite ? whiteColor : blackColor,
                      ),
                      if (humanStats != null)
                        (
                          key: const Key('play_area_advantage_draw_section'),
                          fraction: drawFraction,
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                      (
                        key: firstIsWhite
                            ? const Key('play_area_advantage_black_section')
                            : const Key('play_area_advantage_white_section'),
                        fraction: firstIsWhite
                            ? humanBlackFraction
                            : humanWhiteFraction,
                        color: firstIsWhite ? blackColor : whiteColor,
                      ),
                    ];
                final double separatorExtent = sections.length - 1;
                final double contentExtent = math.max(
                  0,
                  primaryExtent - separatorExtent,
                );
                double usedExtent = 0;
                Widget section({
                  required Key key,
                  required double sectionExtent,
                  required Color color,
                }) {
                  return SizedBox(
                    key: key,
                    width: axis == Axis.horizontal
                        ? sectionExtent
                        : double.infinity,
                    height: axis == Axis.vertical
                        ? sectionExtent
                        : double.infinity,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.88),
                      ),
                    ),
                  );
                }

                Widget separator() => SizedBox(
                  width: axis == Axis.horizontal ? 1 : double.infinity,
                  height: axis == Axis.vertical ? 1 : double.infinity,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: DB().colorSettings.messageColor.withValues(
                        alpha: 0.65,
                      ),
                    ),
                  ),
                );

                final List<Widget> children = <Widget>[];
                for (int index = 0; index < sections.length; index++) {
                  final ({Key key, double fraction, Color color}) item =
                      sections[index];
                  final double sectionExtent = index == sections.length - 1
                      ? math.max(0, contentExtent - usedExtent)
                      : contentExtent * item.fraction.clamp(0.0, 1.0);
                  usedExtent += sectionExtent;
                  children.add(
                    section(
                      key: item.key,
                      sectionExtent: sectionExtent,
                      color: item.color,
                    ),
                  );
                  if (index != sections.length - 1) {
                    children.add(separator());
                  }
                }

                return axis == Axis.vertical
                    ? Column(children: children)
                    : Row(textDirection: TextDirection.ltr, children: children);
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _InlineMoveRound {
  _InlineMoveRound(this.number);

  final int number;
  final List<_InlineMoveSegment> segments = <_InlineMoveSegment>[];
}

class _InlineMoveSegment {
  _InlineMoveSegment({required this.side});

  final PieceColor side;
  final List<_IndexedMoveNode> nodes = <_IndexedMoveNode>[];
}

class _IndexedMoveNode {
  const _IndexedMoveNode({required this.index, required this.node});

  final int index;
  final PgnNode<ExtMove> node;
}

enum _InlineMoveListLayout { wrap, horizontal, stacked, twoColumn }

enum _GameMoveChipStyle { filled, inlineText }

class _BoundedMoveWrap extends StatelessWidget {
  const _BoundedMoveWrap({
    super.key,
    required this.spacing,
    required this.runSpacing,
    required this.children,
  });

  final double spacing;
  final double runSpacing;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        assert(
          constraints.hasBoundedWidth,
          'Inline move list wrapping requires a bounded width.',
        );
        return SizedBox(
          width: constraints.maxWidth,
          child: Wrap(
            spacing: spacing,
            runSpacing: runSpacing,
            children: <Widget>[
              for (final Widget child in children)
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: constraints.maxWidth),
                  child: child,
                ),
            ],
          ),
        );
      },
    );
  }
}

class _AnalysisBranchGuidePainter extends CustomPainter {
  const _AnalysisBranchGuidePainter({
    required this.color,
    required this.isLast,
  });

  final Color color;
  final bool isLast;

  @override
  void paint(Canvas canvas, Size size) {
    const double elbowY = 18;
    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final Path path = Path()
      ..moveTo(0, 0)
      ..lineTo(0, isLast ? elbowY : size.height)
      ..moveTo(0, elbowY)
      ..lineTo(8, elbowY);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_AnalysisBranchGuidePainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.isLast != isLast;
  }
}

class _InlineMoveCount extends StatelessWidget {
  const _InlineMoveCount({
    required this.count,
    this.foregroundColor,
    this.fontSize,
  });

  final int count;
  final Color? foregroundColor;
  final double? fontSize;

  @override
  Widget build(BuildContext context) {
    final Color color =
        foregroundColor ?? Theme.of(context).colorScheme.onSurfaceVariant;
    final TextStyle baseStyle = fontSize == null
        ? _inlineMoveListTextStyle(context)
        : Theme.of(context).textTheme.bodyLarge ??
              const TextStyle(fontSize: 16);
    return Padding(
      padding: const EdgeInsets.only(right: 3),
      child: Text(
        '$count.',
        style: baseStyle.copyWith(
          color: color,
          fontSize: fontSize,
          fontWeight: FontWeight.w400,
          fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

TextStyle _inlineMoveListTextStyle(BuildContext context) {
  final TextStyle baseStyle =
      Theme.of(context).textTheme.bodyMedium ?? const TextStyle(fontSize: 14);
  return baseStyle.copyWith(fontFamily: 'monospace', letterSpacing: 0);
}

class _GameMoveChip extends StatelessWidget {
  const _GameMoveChip({
    super.key,
    required this.label,
    required this.selected,
    required this.selectedColor,
    required this.selectedTextColor,
    required this.textStyle,
    this.style = _GameMoveChipStyle.filled,
    this.fontWeight,
    this.maxLines = 1,
    this.onTap,
    this.onLongPress,
  });

  final String label;
  final bool selected;
  final Color selectedColor;
  final Color selectedTextColor;
  final TextStyle? textStyle;
  final _GameMoveChipStyle style;
  final FontWeight? fontWeight;
  final int? maxLines;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final BorderRadius borderRadius = BorderRadius.circular(
      AppStyles.compactRadius,
    );
    final TextStyle moveTextStyle =
        textStyle?.copyWith(
          color: switch (style) {
            _GameMoveChipStyle.filled =>
              selected ? selectedTextColor : colorScheme.onSurfaceVariant,
            _GameMoveChipStyle.inlineText =>
              selected
                  ? colorScheme.onPrimaryContainer
                  : textStyle?.color ?? colorScheme.onSurface,
          },
          fontWeight:
              fontWeight ?? (selected ? FontWeight.w600 : FontWeight.w500),
        ) ??
        TextStyle(
          color: selected
              ? colorScheme.onPrimaryContainer
              : colorScheme.onSurface,
          fontWeight:
              fontWeight ?? (selected ? FontWeight.w600 : FontWeight.w500),
        );
    final Widget labelText = Text(
      label,
      maxLines: maxLines,
      overflow: maxLines == 1 ? TextOverflow.ellipsis : TextOverflow.visible,
      softWrap: maxLines != 1,
      style: moveTextStyle,
    );

    final Widget content = switch (style) {
      _GameMoveChipStyle.filled => DecoratedBox(
        decoration: BoxDecoration(
          color: selected ? selectedColor : colorScheme.surfaceContainerHighest,
          borderRadius: borderRadius,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          child: labelText,
        ),
      ),
      _GameMoveChipStyle.inlineText => DecoratedBox(
        decoration: BoxDecoration(
          color: selected ? colorScheme.primaryContainer : Colors.transparent,
          borderRadius: borderRadius,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
          child: labelText,
        ),
      ),
    };
    return Semantics(
      selected: selected,
      button: onTap != null || onLongPress != null,
      child: onTap == null && onLongPress == null
          ? content
          : Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: borderRadius,
                onTap: onTap,
                onLongPress: onLongPress,
                child: content,
              ),
            ),
    );
  }
}

class _ComputerMoveSource {
  const _ComputerMoveSource({required this.icon, required this.label});

  final IconData icon;
  final String label;
}

_ComputerMoveSource? _computerMoveSourceFor(
  BuildContext context,
  AiMoveType? moveType,
) {
  return switch (moveType) {
    AiMoveType.openingBook => _ComputerMoveSource(
      icon: FluentIcons.book_24_filled,
      label: S.of(context).openingBookSettings,
    ),
    AiMoveType.humanDatabase => _ComputerMoveSource(
      icon: FluentIcons.book_database_24_filled,
      label: S.of(context).humanGameDatabaseSettings,
    ),
    AiMoveType.perfect => _ComputerMoveSource(
      icon: FluentIcons.database_24_filled,
      label: S.of(context).perfectDatabaseSettings,
    ),
    _ => null,
  };
}

/// A compact provenance badge for a completed computer move.
///
/// It complements, rather than replaces, the robot avatar so an automated
/// opponent remains recognisable even when a move came from a data source.
class _ComputerMoveSourceBadge extends StatelessWidget {
  const _ComputerMoveSourceBadge({
    super.key,
    required this.source,
    required this.color,
  });

  final _ComputerMoveSource source;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      image: true,
      label: source.label,
      child: Tooltip(
        message: source.label,
        child: ExcludeSemantics(
          child: Icon(source.icon, size: 16, color: color),
        ),
      ),
    );
  }
}

class _HumanAiPlayerPanel extends StatelessWidget {
  const _HumanAiPlayerPanel({super.key, required this.isRobot});

  final bool isRobot;

  @override
  Widget build(BuildContext context) {
    final GameController controller = GameController();
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[
        controller.headerIconsNotifier,
        if (isRobot) controller.engineActivityNotifier,
      ]),
      builder: (BuildContext context, Widget? child) {
        return _buildPanel(
          context,
          isThinking: isRobot && controller.engineActivityNotifier.value,
        );
      },
    );
  }

  Widget _buildPanel(BuildContext context, {required bool isThinking}) {
    final ThemeData theme = Theme.of(context);
    final Color messageColor = DB().colorSettings.messageColor;
    final GameController controller = GameController();
    final int level = DB().generalSettings.skillLevel;
    final int rating = isRobot
        ? EloRatingService.getFixedAiEloRating(level)
        : DB().statsSettings.humanStats.rating;
    final String title = isRobot
        ? S.of(context).humanAiRobotLevel(level)
        : S.of(context).humanAiPlayer;
    final PieceColor sideToMove = controller.activeBoardView.sideToMove;
    final bool isActivePlayer =
        (sideToMove == PieceColor.white || sideToMove == PieceColor.black) &&
        controller.gameInstance.getPlayerByColor(sideToMove).isAi == isRobot;
    // A source is known only after the computer has completed its turn. Do
    // not show the previous source while it is thinking about a new move.
    final _ComputerMoveSource? completedMoveSource =
        isRobot && !isThinking && !isActivePlayer
        ? _computerMoveSourceFor(context, controller.aiMoveType)
        : null;
    final Widget playerDetails = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Flexible(
              child: Text(
                title,
                key: Key(
                  isRobot
                      ? 'play_area_human_ai_robot_title'
                      : 'play_area_human_ai_player_title',
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: messageColor,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0,
                ),
              ),
            ),
            if (completedMoveSource != null) ...<Widget>[
              const SizedBox(width: 4),
              _ComputerMoveSourceBadge(
                key: const Key('play_area_human_ai_robot_move_source'),
                source: completedMoveSource,
                color: messageColor.withValues(alpha: 0.72),
              ),
            ],
            if (isThinking) ...<Widget>[
              const SizedBox(width: 8),
              Icon(
                Icons.hourglass_top,
                key: const Key('play_area_human_ai_robot_thinking_icon'),
                size: 16,
                color: messageColor.withValues(alpha: 0.72),
              ),
            ],
          ],
        ),
        Text(
          S.of(context).eloRating(rating),
          key: Key(
            isRobot
                ? 'play_area_human_ai_robot_elo'
                : 'play_area_human_ai_player_elo',
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            color: messageColor.withValues(alpha: 0.72),
            letterSpacing: 0,
          ),
        ),
      ],
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        key: Key(
          isRobot
              ? 'play_area_human_ai_robot_row'
              : 'play_area_human_ai_player_row',
        ),
        children: <Widget>[
          SizedBox.square(
            dimension: 44,
            child: Icon(
              isRobot ? Icons.smart_toy_outlined : Icons.person_outline,
              size: 32,
              color: messageColor.withValues(alpha: 0.82),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: playerDetails),
        ],
      ),
    );
  }
}

class _HumanAiGameTipPanel extends StatelessWidget {
  const _HumanAiGameTipPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final GameController controller = GameController();
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[
        controller.headerTipNotifier,
        controller.headerIconsNotifier,
      ]),
      builder: (BuildContext context, Widget? child) {
        if (!DB().generalSettings.showGameTips) {
          return const SizedBox.shrink(
            key: Key('play_area_human_ai_tip_hidden'),
          );
        }

        final NativeMillGameSession? session =
            controller.activeNativeMillSession;
        final String message = controller.headerTipNotifier.message.isEmpty
            ? session == null
                  ? S.of(context).welcome
                  : controller.nativeSessionTurnTip(context, session) ??
                        S.of(context).welcome
            : controller.headerTipNotifier.message;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: GameTipBubble(
            key: const Key('play_area_human_ai_tip'),
            message: message,
          ),
        );
      },
    );
  }
}

class _AnalysisPanel extends StatelessWidget {
  const _AnalysisPanel({
    required this.framed,
    required this.explorer,
    required this.moves,
  });

  static const double _tabIconSize = 18;
  static const double _tabHeight = _tabIconSize + 8;

  final bool framed;
  final Widget explorer;
  final Widget moves;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final S strings = S.of(context);
    final Widget content = DecoratedBox(
      key: const Key('play_area_analysis_panel'),
      decoration: BoxDecoration(color: colorScheme.surfaceContainerLowest),
      child: Column(
        children: <Widget>[
          Material(
            color: colorScheme.surface,
            child: TabBar(
              key: const Key('play_area_analysis_tabs'),
              labelColor: colorScheme.primary,
              unselectedLabelColor: colorScheme.onSurfaceVariant,
              indicatorColor: colorScheme.primary,
              dividerColor: colorScheme.outlineVariant,
              tabs: <Widget>[
                Tab(
                  key: const Key('play_area_analysis_tab_explorer'),
                  height: _tabHeight,
                  icon: Icon(
                    Icons.explore_outlined,
                    size: _tabIconSize,
                    semanticLabel: strings.openingExplorer,
                  ),
                ),
                Tab(
                  key: const Key('play_area_analysis_tab_moves'),
                  height: _tabHeight,
                  icon: Icon(
                    Icons.account_tree_outlined,
                    size: _tabIconSize,
                    semanticLabel: strings.moveList,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              key: const Key('play_area_analysis_tab_view'),
              children: <Widget>[explorer, moves],
            ),
          ),
        ],
      ),
    );

    return DefaultTabController(
      length: 2,
      initialIndex: 1,
      child: framed
          ? Card(
              key: const Key('play_area_analysis_panel_card'),
              clipBehavior: Clip.hardEdge,
              semanticContainer: false,
              margin: EdgeInsets.zero,
              child: content,
            )
          : content,
    );
  }
}

class AnalysisMoveFeedbackCard extends StatelessWidget {
  const AnalysisMoveFeedbackCard({
    super.key,
    required this.state,
    required this.pvExpanded,
    required this.onTogglePv,
    required this.onApplyAnnotation,
    required this.onAddBestLine,
  });

  static const double height = 176;

  final MoveFeedbackAnalysisState state;
  final bool pvExpanded;
  final VoidCallback onTogglePv;
  final VoidCallback? onApplyAnnotation;
  final VoidCallback? onAddBestLine;

  @override
  Widget build(BuildContext context) {
    final S strings = S.of(context);
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final double accessibilityScale = MediaQuery.textScalerOf(
      context,
    ).scale(1).clamp(1.0, 1.5);
    return SizedBox(
      key: const Key('play_area_move_feedback_card_slot'),
      height: height * accessibilityScale,
      child: Card(
        margin: const EdgeInsets.fromLTRB(8, 4, 8, 4),
        color: colors.surfaceContainerHigh,
        child: Semantics(
          liveRegion: true,
          label: strings.analysisMoveFeedback,
          child: switch (state.status) {
            MoveFeedbackAnalysisStatus.loading => Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 12),
                  Text(strings.moveFeedbackLoading),
                ],
              ),
            ),
            MoveFeedbackAnalysisStatus.error => Center(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  strings.moveFeedbackInsufficientEvidence,
                  key: const Key('play_area_move_feedback_error'),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            MoveFeedbackAnalysisStatus.ready => _buildResult(
              context,
              strings,
              theme,
            ),
            MoveFeedbackAnalysisStatus.idle => const SizedBox.shrink(),
          },
        ),
      ),
    );
  }

  Widget _buildResult(BuildContext context, S strings, ThemeData theme) {
    final MoveFeedbackResult result = state.result!;
    final String glyph = result.symbol.glyph.isEmpty
        ? '•'
        : result.symbol.glyph;
    final List<String> reasonLabels = result.reasons
        .map(
          (MoveFeedbackReason reason) =>
              moveFeedbackReasonLabel(strings, reason),
        )
        .toList(growable: false);
    final List<String> visibleReasonLabels = reasonLabels.isEmpty
        ? <String>[_symbolLabel(strings, result)]
        : reasonLabels.take(2).toList(growable: false);
    final String bestMove = result.bestMove ?? strings.unknown;
    final String pv = result.principalVariation.join(' ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          ExcludeSemantics(
            child: SizedBox(
              width: 44,
              child: Text(
                glyph,
                key: const Key('play_area_move_feedback_symbol'),
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        _symbolLabel(strings, result),
                        key: const Key('play_area_move_feedback_title'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(
                      result.source == MoveFeedbackSource.perfectDatabase
                          ? strings.moveFeedbackSourceDatabase
                          : strings.moveFeedbackSourceEngine,
                      style: theme.textTheme.labelSmall,
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  strings.moveFeedbackReasonsSummary(
                    visibleReasonLabels.join(' · '),
                  ),
                  key: const Key('play_area_move_feedback_reasons'),
                  maxLines: pvExpanded ? 1 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 3),
                Text(
                  '${strings.moveFeedbackScoreDifference(result.loss)}  '
                  '${strings.moveFeedbackBestMove(bestMove)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium,
                ),
                if (pvExpanded && pv.isNotEmpty)
                  Text(
                    strings.moveFeedbackPrincipalVariation(pv),
                    key: const Key('play_area_move_feedback_pv'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                const Spacer(),
                Row(
                  children: <Widget>[
                    if (reasonLabels.isNotEmpty)
                      IconButton(
                        key: const Key('play_area_move_feedback_show_reasons'),
                        tooltip: strings.moveFeedbackShowReasons,
                        onPressed: () => unawaited(
                          showMoveFeedbackReasonsDialog(
                            context: context,
                            heading:
                                '${result.symbol.glyph} '
                                        '${_symbolLabel(strings, result)}'
                                    .trim(),
                            reasons: result.reasons,
                            reasonKeyPrefix: 'play_area_move_feedback_reason_',
                          ),
                        ),
                        icon: const Icon(Icons.info_outline),
                      ),
                    if (pv.isNotEmpty)
                      IconButton(
                        key: const Key('play_area_move_feedback_toggle_pv'),
                        tooltip: pvExpanded
                            ? strings.moveFeedbackHideLine
                            : strings.moveFeedbackShowLine,
                        onPressed: onTogglePv,
                        icon: Icon(
                          pvExpanded ? Icons.expand_less : Icons.expand_more,
                        ),
                      ),
                    const Spacer(),
                    if (onApplyAnnotation != null)
                      IconButton(
                        key: const Key(
                          'play_area_move_feedback_apply_annotation',
                        ),
                        tooltip: strings.moveFeedbackApplyAnnotation,
                        onPressed: onApplyAnnotation,
                        icon: const Icon(Icons.bookmark_add_outlined),
                      ),
                    if (onAddBestLine != null)
                      IconButton(
                        key: const Key('play_area_move_feedback_add_best_line'),
                        tooltip: strings.moveFeedbackAddBestLine,
                        onPressed: onAddBestLine,
                        icon: const Icon(Icons.alt_route),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _symbolLabel(S strings, MoveFeedbackResult result) {
    return switch (result.symbol) {
      MoveFeedbackSymbol.brilliant => strings.moveFeedbackBrilliant,
      MoveFeedbackSymbol.good => strings.moveFeedbackGood,
      MoveFeedbackSymbol.interesting => strings.moveFeedbackInteresting,
      MoveFeedbackSymbol.dubious => strings.moveFeedbackDubious,
      MoveFeedbackSymbol.mistake => strings.moveFeedbackMistake,
      MoveFeedbackSymbol.blunder => strings.moveFeedbackBlunder,
      MoveFeedbackSymbol.none =>
        result.reasons.isEmpty
            ? strings.moveFeedbackRegularBest
            : moveFeedbackReasonLabel(strings, result.reasons.first),
    };
  }
}

class _AnalysisVariationsBar extends StatelessWidget {
  const _AnalysisVariationsBar({
    super.key,
    required this.showAnnotations,
    required this.onMoveTap,
  });

  static const double _maxVariationWidth = 72;

  final bool showAnnotations;
  final Future<void> Function(BuildContext, PgnNode<ExtMove>) onMoveTap;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: GameController().gameRecorder.moveCountNotifier,
      builder: (BuildContext context, _, _) {
        final GameRecorder recorder = GameController().gameRecorder;
        final List<_AnalysisVariationGroup> variationGroups =
            _buildVariationGroups(recorder);
        if (variationGroups.isEmpty) {
          return const SizedBox.shrink(
            key: Key('play_area_analysis_variations_bar_empty'),
          );
        }

        return LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final int crossAxisCount = math.max(
              1,
              math.min(8, (constraints.maxWidth / _maxVariationWidth).floor()),
            );
            final List<Widget> rows = <Widget>[];

            for (final _AnalysisVariationGroup group in variationGroups) {
              final List<PgnNode<ExtMove>> variations = group.variations;
              for (int i = 0; i < variations.length; i += crossAxisCount) {
                final List<PgnNode<ExtMove>> rowVariations = variations
                    .skip(i)
                    .take(crossAxisCount)
                    .toList(growable: false);
                rows.add(
                  Row(
                    key: i == 0 ? group.rowKey : null,
                    children: <Widget>[
                      for (final PgnNode<ExtMove> variation in rowVariations)
                        Expanded(
                          child: _AnalysisVariationButton(
                            key: Key(
                              '${group.keyPrefix}_${variations.indexOf(variation) + 1}',
                            ),
                            node: variation,
                            isMainline: identical(variation, variations.first),
                            isSelected: identical(variation, group.selected),
                            hasSelectedVariation: group.selected != null,
                            showAnnotations: showAnnotations,
                            onMoveTap: onMoveTap,
                          ),
                        ),
                    ],
                  ),
                );
              }
            }

            return Column(
              key: const Key('play_area_analysis_variations_bar_content'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: rows,
            );
          },
        );
      },
    );
  }

  List<_AnalysisVariationGroup> _buildVariationGroups(GameRecorder recorder) {
    final PgnNode<ExtMove> currentNode =
        recorder.activeNode ?? recorder.pgnRoot;
    return currentNode.children.length > 1
        ? <_AnalysisVariationGroup>[
            _AnalysisVariationGroup(
              variations: currentNode.children,
              selected: null,
              keyPrefix: 'play_area_analysis_variation',
              rowKey: const Key('play_area_analysis_current_variation_group'),
            ),
          ]
        : const <_AnalysisVariationGroup>[];
  }
}

class _AnalysisVariationGroup {
  const _AnalysisVariationGroup({
    required this.variations,
    required this.selected,
    required this.keyPrefix,
    required this.rowKey,
  });

  final List<PgnNode<ExtMove>> variations;
  final PgnNode<ExtMove>? selected;
  final String keyPrefix;
  final Key rowKey;
}

class _AnalysisVariationButton extends StatelessWidget {
  const _AnalysisVariationButton({
    super.key,
    required this.node,
    required this.isMainline,
    required this.isSelected,
    required this.hasSelectedVariation,
    required this.showAnnotations,
    required this.onMoveTap,
  });

  final PgnNode<ExtMove> node;
  final bool isMainline;
  final bool isSelected;
  final bool hasSelectedVariation;
  final bool showAnnotations;
  final Future<void> Function(BuildContext, PgnNode<ExtMove>) onMoveTap;

  @override
  Widget build(BuildContext context) {
    final ExtMove? move = node.data;
    assert(move != null, 'Analysis variation buttons require move data.');
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final S strings = S.of(context);
    final bool usePrimaryStyle =
        isSelected || (!hasSelectedVariation && isMainline);
    final Color backgroundColor = usePrimaryStyle
        ? colorScheme.primaryContainer
        : isMainline
        ? colorScheme.tertiaryContainer
        : colorScheme.secondaryContainer;
    final Color foregroundColor = usePrimaryStyle
        ? colorScheme.onPrimaryContainer
        : isMainline
        ? colorScheme.onTertiaryContainer
        : colorScheme.onSecondaryContainer;
    final String displayText = showAnnotations
        ? _notationWithNagSymbols(move!.notation, move.getAllNags())
        : move!.notation;
    final String variationLabel = strings.variationNotation(displayText);

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(color: theme.dividerColor),
          bottom: BorderSide(color: theme.dividerColor),
        ),
      ),
      child: Tooltip(
        message: variationLabel,
        child: Semantics(
          button: true,
          selected: usePrimaryStyle,
          label: variationLabel,
          excludeSemantics: true,
          child: Material(
            color: backgroundColor,
            child: InkWell(
              onTap: () => unawaited(onMoveTap(context, node)),
              child: Container(
                alignment: Alignment.center,
                constraints: const BoxConstraints(
                  minHeight: kMinInteractiveDimension,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    displayText,
                    maxLines: 1,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: foregroundColor,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AnalysisEngineLines extends StatelessWidget {
  const _AnalysisEngineLines({
    super.key,
    required this.results,
    required this.onMoveTap,
  });

  final List<MoveAnalysisResult> results;
  final Future<void> Function(String move) onMoveTap;

  @override
  Widget build(BuildContext context) {
    final int lineCount = AnalysisMode.engineLineCount;
    final List<MoveAnalysisResult> visibleResults = results
        .take(lineCount)
        .toList(growable: false);
    final bool canApplyEngineLine =
        !AnalysisMode.isThreatMode && !AnalysisMode.isAnalyzing;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
      child: Column(
        key: const Key('play_area_analysis_engine_lines_column'),
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (int index = 0; index < lineCount; index++)
            if (index < visibleResults.length)
              _AnalysisEngineLine(
                key: Key('play_area_analysis_engine_line_$index'),
                lineRank: visibleResults[index].rank ?? index + 1,
                result: visibleResults[index],
                onTap: canApplyEngineLine
                    ? () => unawaited(onMoveTap(visibleResults[index].move))
                    : null,
              )
            else
              SizedBox(
                key: Key('play_area_analysis_engine_line_empty_$index'),
                height: _AnalysisEngineLine.height,
              ),
        ],
      ),
    );
  }
}

class _AnalysisEngineSheetStatus extends StatelessWidget {
  const _AnalysisEngineSheetStatus({
    required this.sourceLabel,
    required this.depth,
    required this.nodes,
    required this.nodesPerSecond,
    required this.isAnalyzing,
    required this.isDeepSearch,
    required this.isThreatMode,
    required this.canGoDeeper,
    required this.onGoDeeper,
  });

  final String sourceLabel;
  final int? depth;
  final int? nodes;
  final int? nodesPerSecond;
  final bool isAnalyzing;
  final bool isDeepSearch;
  final bool isThreatMode;
  final bool canGoDeeper;
  final VoidCallback onGoDeeper;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final S strings = S.of(context);
    final String? subtitle = _subtitle(strings);
    final String continueSearchLabel = _continueSearchLabel(strings);

    return ListTile(
      key: const Key('play_area_analysis_engine_status'),
      contentPadding: const EdgeInsets.only(left: 16),
      leading: Icon(
        isThreatMode ? Icons.online_prediction_outlined : Icons.memory_outlined,
        color: colorScheme.primary,
      ),
      trailing: canGoDeeper
          ? IconButton(
              key: const Key('play_area_analysis_engine_go_deeper'),
              tooltip: continueSearchLabel,
              onPressed: onGoDeeper,
              icon: const Icon(Icons.add_circle_outline),
              color: colorScheme.primary,
            )
          : null,
      title: Text(
        sourceLabel,
        key: const Key('play_area_analysis_engine_status_source'),
        style: theme.textTheme.titleMedium?.copyWith(
          color: colorScheme.onSurface,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle,
              key: const Key('play_area_analysis_engine_status_depth'),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
    );
  }

  String? _subtitle(S strings) {
    final String? depthText = depth == null ? null : 'd$depth';
    final String? nodesText = nodes == null
        ? null
        : _compactAnalysisCount(nodes!);
    final String? nodesPerSecondText = nodesPerSecond == null
        ? null
        : _compactAnalysisRate(nodesPerSecond!);
    final List<String> parts = <String>[
      if (isAnalyzing) strings.thinking,
      ?depthText,
      if (isDeepSearch)
        _analysisSearchTimeValueLabel(
          strings,
          AnalysisMode.maxEngineSearchTimeMs,
        ),
      ?nodesText,
      ?nodesPerSecondText,
      if (canGoDeeper) _continueSearchLabel(strings),
    ];
    if (parts.isEmpty) {
      return null;
    }
    return parts.join(' · ');
  }

  String _continueSearchLabel(S strings) {
    return '${strings.continueFromHere} · '
        '${_analysisSearchTimeValueLabel(strings, AnalysisMode.maxEngineSearchTimeMs)}';
  }
}

class _AnalysisEngineLine extends StatelessWidget {
  const _AnalysisEngineLine({
    super.key,
    required this.lineRank,
    required this.result,
    required this.onTap,
  });

  static const double height = 24;
  static const double evalFontSize = 11;

  final int lineRank;
  final MoveAnalysisResult result;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    assert(lineRank > 0, 'Engine line rank must be one-based.');
    final ThemeData theme = Theme.of(context);
    final Color lineColor = DB().colorSettings.messageColor;
    final S strings = S.of(context);
    final Color outcomeColor = AnalysisMode.isThreatMode
        ? Colors.red.shade600
        : AnalysisMode.getColorForOutcome(result.outcome);
    final Color chipTextColor =
        ThemeData.estimateBrightnessForColor(outcomeColor) == Brightness.dark
        ? Colors.white
        : Colors.black;
    final String lineText = _lineText(result);
    final String lineLabel = _lineLabel(strings, result, lineText);

    return Tooltip(
      message: lineLabel,
      child: Semantics(
        button: onTap != null,
        enabled: onTap != null,
        label: lineLabel,
        excludeSemantics: true,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppStyles.compactRadius),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: height),
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: Row(
                children: <Widget>[
                  Container(
                    constraints: const BoxConstraints(minWidth: 34),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: outcomeColor,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      _evalLabel(result.outcome),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: chipTextColor,
                        fontSize: evalFontSize,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      lineText,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: lineColor,
                        fontSize: 14,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _lineText(MoveAnalysisResult result) {
    return _analysisLineText(result);
  }

  String _evalLabel(AnalysisOutcome outcome) {
    return _analysisEvalLabel(outcome);
  }

  String _lineLabel(S strings, MoveAnalysisResult result, String lineText) {
    final List<String> parts = <String>[
      if (AnalysisMode.isThreatMode) _analysisThreatLabel(strings),
      strings.analysisEngineLineSemantics(lineRank),
      if (AnalysisMode.isAnalyzing) strings.thinking,
      strings.analysisEvaluationSemantics(_evalLabel(result.outcome)),
      lineText,
    ];
    return parts.join(' · ');
  }
}

String _notationWithNagSymbols(String notation, List<int> nags) {
  if (nags.isEmpty) {
    return notation;
  }

  final List<String> suffixSymbols = <String>[];
  final List<String> numericSymbols = <String>[];
  for (final int nag in nags) {
    final String symbol = _nagSymbol(nag);
    if (symbol.startsWith(r'$')) {
      numericSymbols.add(symbol);
    } else {
      suffixSymbols.add(symbol);
    }
  }

  final StringBuffer buffer = StringBuffer(notation);
  if (suffixSymbols.isNotEmpty) {
    buffer.write(suffixSymbols.join());
  }
  if (numericSymbols.isNotEmpty) {
    buffer.write(' ');
    buffer.write(numericSymbols.join(' '));
  }
  return buffer.toString();
}

String _nagSymbol(int nag) {
  return switch (nag) {
    1 => '!',
    2 => '?',
    3 => '!!',
    4 => '??',
    5 => '!?',
    6 => '?!',
    8 => '□',
    10 || 11 => '=',
    13 => '∞',
    14 => '⩲',
    15 => '⩱',
    16 => '±',
    17 => '∓',
    18 => '+-',
    19 => '-+',
    22 => '⨀',
    32 => '⟳',
    36 => '↑',
    44 => '=∞',
    132 => '⇆',
    138 => '⊕',
    140 => '∆',
    146 => 'N',
    _ => '\$$nag',
  };
}

String _analysisEvalLabel(AnalysisOutcome outcome) {
  if (outcome.stepCount != null && outcome.stepCount! > 0) {
    return '${outcome.name.substring(0, 1).toUpperCase()}${outcome.stepCount}';
  }
  if (outcome.valueStr != null && outcome.valueStr!.isNotEmpty) {
    return outcome.valueStr!;
  }
  return switch (outcome.name) {
    'win' => 'W',
    'draw' => '=',
    'loss' => 'L',
    'advantage' => '+',
    'disadvantage' => '-',
    _ => '?',
  };
}

String _analysisLineText(MoveAnalysisResult result) {
  final PgnNode<ExtMove>? activeNode = GameController().gameRecorder.activeNode;
  final ExtMove? lastMove = activeNode?.data;
  final PieceColor? sideToMove =
      GameController().activeSessionSideToMove ??
      _nextAnalysisSideToMoveAfter(lastMove);
  if (sideToMove != PieceColor.white && sideToMove != PieceColor.black) {
    return result.displayLine.join(' ');
  }

  final PieceColor playableSideToMove = sideToMove!;
  final int moveNumber = _nextAnalysisMoveNumber(
    activeNode,
    playableSideToMove,
  );
  return _numberedAnalysisLine(
    result.displayLine,
    sideToMove: playableSideToMove,
    moveNumber: moveNumber,
  );
}

String _numberedAnalysisLine(
  List<String> moves, {
  required PieceColor sideToMove,
  required int moveNumber,
}) {
  assert(
    sideToMove == PieceColor.white || sideToMove == PieceColor.black,
    'PV numbering requires a playable side.',
  );
  final StringBuffer buffer = StringBuffer();
  PieceColor side = sideToMove;
  int round = moveNumber;
  bool startsTurn = true;

  void writePart(String part) {
    if (buffer.isNotEmpty) {
      buffer.write(' ');
    }
    buffer.write(part);
  }

  for (int i = 0; i < moves.length; i++) {
    if (startsTurn) {
      if (side == PieceColor.white) {
        writePart('$round.');
      } else if (i == 0) {
        writePart('$round...');
      }
    }
    writePart(moves[i]);

    final bool sameTurnContinues =
        i + 1 < moves.length && moves[i + 1].startsWith('x');
    if (sameTurnContinues) {
      startsTurn = false;
      continue;
    }
    startsTurn = true;
    if (side == PieceColor.black) {
      side = PieceColor.white;
      round++;
    } else {
      side = PieceColor.black;
    }
  }
  return buffer.toString();
}

PieceColor? _nextAnalysisSideToMoveAfter(ExtMove? lastMove) {
  return switch (lastMove?.side) {
    PieceColor.white => PieceColor.black,
    PieceColor.black => PieceColor.white,
    _ => PieceColor.white,
  };
}

int _nextAnalysisMoveNumber(
  PgnNode<ExtMove>? activeNode,
  PieceColor sideToMove,
) {
  final ExtMove? lastMove = activeNode?.data;
  if (lastMove == null) {
    return 1;
  }
  final List<PgnNode<ExtMove>> path = <PgnNode<ExtMove>>[];
  PgnNode<ExtMove>? node = activeNode;
  while (node?.data != null) {
    path.insert(0, node!);
    node = node.parent;
  }
  int round = 1;
  PieceColor? previousSide;
  for (final PgnNode<ExtMove> pathNode in path) {
    final PieceColor side = pathNode.data!.side;
    if (previousSide == PieceColor.black && side == PieceColor.white) {
      round++;
    }
    previousSide = side;
  }
  if (path.isEmpty) {
    return round;
  }
  if (sideToMove == PieceColor.white && lastMove.side == PieceColor.black) {
    return round + 1;
  }
  return round;
}

int? _analysisEngineDepth() {
  if (!AnalysisMode.hasEngineLinesSource) {
    return null;
  }
  int? depth;
  for (final MoveAnalysisResult result in AnalysisMode.analysisLineResults) {
    final int? candidate = result.depth;
    if (candidate == null || candidate <= 0) {
      continue;
    }
    depth = depth == null ? candidate : math.max(depth, candidate);
  }
  return depth;
}

int? _analysisEngineNodes() {
  if (!AnalysisMode.hasEngineLinesSource) {
    return null;
  }
  int? nodes;
  for (final MoveAnalysisResult result in AnalysisMode.analysisLineResults) {
    final int? candidate = result.nodes;
    if (candidate == null || candidate <= 0) {
      continue;
    }
    nodes = nodes == null ? candidate : math.max(nodes, candidate);
  }
  return nodes;
}

int? _analysisEngineNodesPerSecond() {
  if (!AnalysisMode.hasEngineLinesSource) {
    return null;
  }
  int? nodesPerSecond;
  for (final MoveAnalysisResult result in AnalysisMode.analysisLineResults) {
    final int? candidate = result.nodesPerSecond;
    if (candidate == null || candidate <= 0) {
      continue;
    }
    nodesPerSecond = nodesPerSecond == null
        ? candidate
        : math.max(nodesPerSecond, candidate);
  }
  return nodesPerSecond;
}

String _analysisSourceLabel(S strings) {
  return switch (AnalysisMode.source) {
    AnalysisSource.engine =>
      AnalysisMode.isThreatMode
          ? _analysisThreatLabel(strings)
          : strings.engine,
    AnalysisSource.perfectDatabaseAndEngine =>
      '${_analysisPerfectDatabaseShortLabel(strings)} · ${strings.engine}',
    AnalysisSource.perfectDatabase => _analysisPerfectDatabaseShortLabel(
      strings,
    ),
    null => strings.engine,
  };
}

String _compactAnalysisCount(int value) {
  if (value >= 1000000) {
    return '${(value / 1000000).toStringAsFixed(value >= 10000000 ? 0 : 1)}M';
  }
  if (value >= 1000) {
    return '${(value / 1000).toStringAsFixed(value >= 10000 ? 0 : 1)}k';
  }
  return '$value';
}

String _compactAnalysisRate(int value) {
  return '${_compactAnalysisCount(value)} n/s';
}

int _analysisOutcomeGaugeValue(AnalysisOutcome outcome) {
  final String? value = outcome.valueStr;
  if (value != null && value.isNotEmpty) {
    final double? parsed = double.tryParse(value);
    if (parsed != null) {
      return parsed.clamp(-100, 100).round();
    }
  }

  return switch (outcome.name) {
    'win' => 100,
    'advantage' => 50,
    'draw' => 0,
    'disadvantage' => -50,
    'loss' => -100,
    _ => 0,
  };
}

class _ContinueFromHereGameRoute extends StatefulWidget {
  const _ContinueFromHereGameRoute({required this.mode});

  final GameMode mode;

  @override
  State<_ContinueFromHereGameRoute> createState() =>
      _ContinueFromHereGameRouteState();
}

class _ContinueFromHereGameRouteState
    extends State<_ContinueFromHereGameRoute> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.mode != GameMode.humanVsAi) {
        return;
      }
      final GameController controller = GameController();
      if (controller.gameInstance.isAiSideToMove) {
        unawaited(controller.engineToGo(context, isMoveNow: false));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return GamePage(widget.mode);
  }
}

class _AnalysisBottomBar extends StatelessWidget {
  const _AnalysisBottomBar({
    required this.onMenuPressed,
    required this.onEnginePressed,
    required this.onEngineLongPressed,
    required this.isEngineHighlighted,
    required this.onPreviousPressed,
    required this.onNextPressed,
  });

  final VoidCallback onMenuPressed;
  final VoidCallback? onEnginePressed;
  final VoidCallback? onEngineLongPressed;
  final bool isEngineHighlighted;
  final VoidCallback? onPreviousPressed;
  final VoidCallback? onNextPressed;

  @override
  Widget build(BuildContext context) {
    final Color messageColor = DB().colorSettings.messageColor;

    return LichessBottomBar(
      key: const Key('play_area_main_toolbar_bottom'),
      backgroundColor: Colors.transparent,
      foregroundColor: messageColor,
      children: <Widget>[
        LichessBottomBarButton(
          key: const Key('play_area_analysis_bottom_bar_menu'),
          icon: Icons.menu,
          label: S.of(context).menu,
          onTap: onMenuPressed,
          withShadow: true,
        ),
        _AnalysisEngineBottomBarButton(
          key: const Key('play_area_analysis_bottom_bar_engine'),
          label: S.of(context).engine,
          sourceLabel: _analysisSourceLabel(S.of(context)),
          onTap: AnalysisMode.isAnalyzing ? null : onEnginePressed,
          onLongPress: onEngineLongPressed,
          highlighted: isEngineHighlighted,
        ),
        _RepeatButton(
          onLongPress: onPreviousPressed,
          child: LichessBottomBarButton(
            key: const Key('play_area_analysis_bottom_bar_previous'),
            icon: CupertinoIcons.chevron_back,
            label: S.of(context).previous,
            onTap: onPreviousPressed,
            showTooltip: false,
            withShadow: true,
          ),
        ),
        _RepeatButton(
          onLongPress: onNextPressed,
          child: LichessBottomBarButton(
            key: const Key('play_area_analysis_bottom_bar_next'),
            icon: CupertinoIcons.chevron_forward,
            label: S.of(context).next,
            onTap: onNextPressed,
            showTooltip: false,
            withShadow: true,
          ),
        ),
      ],
    );
  }
}

class _RepeatButton extends StatefulWidget {
  const _RepeatButton({required this.onLongPress, required this.child});

  static const List<Duration> _triggerDelays = <Duration>[
    Duration(milliseconds: 200),
    Duration(milliseconds: 180),
    Duration(milliseconds: 100),
    Duration(milliseconds: 40),
  ];
  static const Duration _holdDelay = Duration(milliseconds: 30);

  final Widget child;
  final VoidCallback? onLongPress;

  @override
  State<_RepeatButton> createState() => _RepeatButtonState();
}

class _RepeatButtonState extends State<_RepeatButton> {
  Timer? _holdTimer;
  bool _isPressed = false;

  @override
  void didUpdateWidget(_RepeatButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.onLongPress != null && widget.onLongPress == null) {
      _stopPress();
    }
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    super.dispose();
  }

  Future<void> _startPress() async {
    _isPressed = true;
    HapticFeedback.selectionClick();
    widget.onLongPress?.call();

    for (final Duration delay in _RepeatButton._triggerDelays) {
      await Future<void>.delayed(delay);
      if (!_isPressed) {
        return;
      }
      widget.onLongPress?.call();
    }

    _holdTimer = Timer.periodic(_RepeatButton._holdDelay, (_) {
      if (_isPressed) {
        widget.onLongPress?.call();
      }
    });
  }

  void _stopPress() {
    _isPressed = false;
    _holdTimer?.cancel();
  }

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPress: widget.onLongPress == null ? null : _startPress,
        onLongPressCancel: widget.onLongPress == null ? null : _stopPress,
        onLongPressUp: widget.onLongPress == null ? null : _stopPress,
        child: widget.child,
      ),
    );
  }
}

class _RegularGameBottomBar extends StatelessWidget {
  const _RegularGameBottomBar({
    required this.onMenuPressed,
    required this.onResignOrResultPressed,
    required this.isShowingResult,
    required this.onTakeBackPressed,
    required this.onPreviousPressed,
    required this.onNextPressed,
  });

  final VoidCallback onMenuPressed;
  final VoidCallback? onResignOrResultPressed;
  final bool isShowingResult;
  final VoidCallback? onTakeBackPressed;
  final VoidCallback? onPreviousPressed;
  final VoidCallback? onNextPressed;

  @override
  Widget build(BuildContext context) {
    final Color messageColor = DB().colorSettings.messageColor;

    return LichessBottomBar(
      key: const Key('play_area_main_toolbar_bottom'),
      backgroundColor: Colors.transparent,
      foregroundColor: messageColor,
      children: <Widget>[
        LichessBottomBarButton(
          key: const Key('play_area_regular_bottom_bar_menu'),
          icon: Icons.menu,
          label: S.of(context).menu,
          onTap: onMenuPressed,
          withShadow: true,
        ),
        LichessBottomBarButton(
          key: const Key('play_area_regular_bottom_bar_resign_result'),
          icon: isShowingResult ? Icons.info_outline : CupertinoIcons.flag,
          label: isShowingResult ? S.of(context).results : S.of(context).resign,
          onTap: onResignOrResultPressed,
          highlighted: isShowingResult,
          withShadow: true,
        ),
        LichessBottomBarButton(
          key: const Key('play_area_regular_bottom_bar_take_back'),
          icon: CupertinoIcons.arrow_uturn_left,
          label: S.of(context).takeBack,
          onTap: onTakeBackPressed,
          withShadow: true,
        ),
        _RepeatButton(
          onLongPress: onPreviousPressed,
          child: LichessBottomBarButton(
            key: const Key('play_area_regular_bottom_bar_previous'),
            icon: CupertinoIcons.chevron_back,
            label: S.of(context).previous,
            onTap: onPreviousPressed,
            showTooltip: false,
            withShadow: true,
          ),
        ),
        _RepeatButton(
          onLongPress: onNextPressed,
          child: LichessBottomBarButton(
            key: const Key('play_area_regular_bottom_bar_next'),
            icon: CupertinoIcons.chevron_forward,
            label: S.of(context).next,
            onTap: onNextPressed,
            showTooltip: false,
            withShadow: true,
          ),
        ),
      ],
    );
  }
}

class _AiVsAiBottomBar extends StatelessWidget {
  const _AiVsAiBottomBar({
    required this.playbackState,
    required this.isEngineActive,
    required this.isShowingResult,
    required this.onMenuPressed,
    required this.onNewGamePressed,
    required this.onPlaybackPressed,
    required this.onStepPressed,
    required this.onMoveListPressed,
  });

  final AiVsAiPlaybackState playbackState;
  final bool isEngineActive;
  final bool isShowingResult;
  final VoidCallback onMenuPressed;
  final VoidCallback onNewGamePressed;
  final VoidCallback? onPlaybackPressed;
  final VoidCallback? onStepPressed;
  final VoidCallback onMoveListPressed;

  @override
  Widget build(BuildContext context) {
    final Color messageColor = DB().colorSettings.messageColor;
    final bool isPaused = playbackState == AiVsAiPlaybackState.paused;
    final bool isPausePending =
        playbackState == AiVsAiPlaybackState.pausePending;

    return LichessBottomBar(
      key: const Key('play_area_main_toolbar_bottom'),
      backgroundColor: Colors.transparent,
      foregroundColor: messageColor,
      children: <Widget>[
        LichessBottomBarButton(
          key: const Key('play_area_ai_vs_ai_bottom_bar_menu'),
          icon: Icons.menu,
          label: S.of(context).menu,
          onTap: onMenuPressed,
          withShadow: true,
        ),
        LichessBottomBarButton(
          key: const Key('play_area_ai_vs_ai_bottom_bar_new_game'),
          icon: Icons.add_circle_outline,
          label: S.of(context).newGame,
          onTap: onNewGamePressed,
          withShadow: true,
        ),
        LichessBottomBarButton(
          key: const Key('play_area_ai_vs_ai_bottom_bar_playback'),
          icon: isShowingResult
              ? Icons.info_outline
              : isPaused
              ? Icons.play_arrow
              : Icons.pause,
          label: isShowingResult
              ? S.of(context).results
              : isPaused
              ? S.of(context).resume
              : S.of(context).pause,
          onTap: onPlaybackPressed,
          highlighted: isShowingResult || isPaused || isPausePending,
          blink: isPausePending && isEngineActive,
          withShadow: true,
        ),
        LichessBottomBarButton(
          key: const Key('play_area_ai_vs_ai_bottom_bar_step'),
          icon: Icons.skip_next,
          label: S.of(context).stepForward,
          onTap: onStepPressed,
          withShadow: true,
        ),
        LichessBottomBarButton(
          key: const Key('play_area_ai_vs_ai_bottom_bar_move_list'),
          icon: Icons.format_list_numbered,
          label: S.of(context).moveList,
          onTap: onMoveListPressed,
          withShadow: true,
        ),
      ],
    );
  }
}

class _OfflineBoardBottomBar extends StatelessWidget {
  const _OfflineBoardBottomBar({
    required this.onMenuPressed,
    required this.onTakeBackPressed,
    required this.onPreviousPressed,
    required this.onNextPressed,
  });

  final VoidCallback onMenuPressed;
  final VoidCallback? onTakeBackPressed;
  final VoidCallback? onPreviousPressed;
  final VoidCallback? onNextPressed;

  @override
  Widget build(BuildContext context) {
    final Color messageColor = DB().colorSettings.messageColor;
    return KeyedSubtree(
      key: const Key('play_area_offline_board_bottom_bar'),
      child: LichessBottomBar(
        key: const Key('play_area_main_toolbar_bottom'),
        backgroundColor: Colors.transparent,
        foregroundColor: messageColor,
        children: <Widget>[
          LichessBottomBarButton(
            key: const Key('play_area_offline_board_bottom_menu'),
            icon: Icons.menu,
            label: S.of(context).menu,
            onTap: onMenuPressed,
            withShadow: true,
          ),
          _RepeatButton(
            onLongPress: onPreviousPressed,
            child: LichessBottomBarButton(
              key: const Key('play_area_offline_board_bottom_previous'),
              icon: CupertinoIcons.chevron_back,
              label: S.of(context).offlineBoardPrevious,
              onTap: onPreviousPressed,
              showTooltip: false,
              withShadow: true,
            ),
          ),
          _RepeatButton(
            onLongPress: onNextPressed,
            child: LichessBottomBarButton(
              key: const Key('play_area_offline_board_bottom_next'),
              icon: CupertinoIcons.chevron_forward,
              label: S.of(context).offlineBoardNext,
              onTap: onNextPressed,
              showTooltip: false,
              withShadow: true,
            ),
          ),
          LichessBottomBarButton(
            key: const Key('play_area_offline_board_bottom_take_back'),
            icon: CupertinoIcons.arrow_uturn_left,
            label: S.of(context).offlineBoardTakeback,
            onTap: onTakeBackPressed,
            withShadow: true,
          ),
        ],
      ),
    );
  }
}

class _OfflineBoardPlayerPanel extends StatelessWidget {
  const _OfflineBoardPlayerPanel({
    super.key,
    required this.side,
    required this.upsideDown,
  });

  final PieceColor side;
  final bool upsideDown;

  @override
  Widget build(BuildContext context) {
    assert(side == PieceColor.white || side == PieceColor.black);
    final Color contentColor = DB().colorSettings.messageColor.withValues(
      alpha: 0.78,
    );
    final String sideName = side == PieceColor.white
        ? S.of(context).offlineBoardWhite
        : S.of(context).offlineBoardBlack;
    final Widget content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 8),
      child: Row(
        children: <Widget>[
          Icon(Icons.person_outline, color: contentColor, size: 22),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              sideName,
              key: Key('offline_board_${side.name}_name'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: contentColor,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
    return Semantics(
      container: true,
      label: sideName,
      child: upsideDown ? RotatedBox(quarterTurns: 2, child: content) : content,
    );
  }
}

class _AnalysisEngineBottomBarButton extends StatelessWidget {
  const _AnalysisEngineBottomBarButton({
    super.key,
    required this.label,
    required this.sourceLabel,
    required this.onTap,
    required this.onLongPress,
    required this.highlighted,
  });

  final String label;
  final String sourceLabel;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool highlighted;

  bool get _enabled => onTap != null;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final Color foreground =
        IconTheme.of(context).color ??
        DefaultTextStyle.of(context).style.color ??
        colorScheme.onSurface;
    final bool isAnalyzing = AnalysisMode.isAnalyzing;
    final bool isActive = highlighted || isAnalyzing;
    final Color chipColor = isActive
        ? foreground
        : foreground.withValues(alpha: 0.72);
    final Color textColor = foreground;
    final String chipText = _chipText;
    final S strings = S.of(context);
    final String statusLabel = _statusLabel(strings);
    final String accessibleLabel = _accessibleLabel(statusLabel);

    return Semantics(
      container: true,
      button: true,
      enabled: _enabled,
      label: accessibleLabel,
      onTap: onTap,
      onLongPress: onLongPress,
      excludeSemantics: true,
      child: Tooltip(
        excludeFromSemantics: true,
        message: accessibleLabel,
        triggerMode: TooltipTriggerMode.longPress,
        child: InkWell(
          borderRadius: BorderRadius.zero,
          onTap: onTap,
          onLongPress: onLongPress,
          child: Opacity(
            key: const Key('play_area_analysis_bottom_bar_engine_opacity'),
            opacity: _enabled || isAnalyzing ? 1 : 0.4,
            child: Stack(
              clipBehavior: Clip.none,
              fit: StackFit.expand,
              alignment: Alignment.center,
              children: <Widget>[
                Center(
                  child: SizedBox.square(
                    key: const Key('play_area_analysis_bottom_bar_engine_chip'),
                    dimension: 28,
                    child: Stack(
                      alignment: Alignment.center,
                      children: <Widget>[
                        CustomPaint(
                          size: const Size.square(28),
                          painter: _AnalysisEngineChipPainter(chipColor),
                        ),
                        if (isAnalyzing && (_analysisEngineDepth() ?? 0) <= 0)
                          SizedBox.square(
                            key: const Key(
                              'play_area_analysis_bottom_bar_engine_progress',
                            ),
                            dimension: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              semanticsLabel: strings.analyzing,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                textColor.withValues(alpha: 0.82),
                              ),
                            ),
                          )
                        else
                          Text(
                            chipText,
                            key: const Key(
                              'play_area_analysis_bottom_bar_engine_value',
                            ),
                            style: TextStyle(
                              color: textColor,
                              fontSize: chipText.length > 2 ? 9 : 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0,
                              shadows: <Shadow>[
                                Shadow(
                                  color: textColor.computeLuminance() < 0.5
                                      ? Colors.white.withValues(alpha: 0.48)
                                      : Colors.black.withValues(alpha: 0.48),
                                  blurRadius: 2,
                                  offset: const Offset(0, 1),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  left: 4,
                  right: 4,
                  bottom: -2,
                  child: Text(
                    sourceLabel,
                    key: const Key(
                      'play_area_analysis_bottom_bar_engine_label',
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.fade,
                    softWrap: false,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: textColor.withValues(alpha: 0.82),
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  bool get _hasCompletedEngineDepth {
    final int? depth = _analysisEngineDepth();
    return depth != null && depth > 0;
  }

  String get _chipText {
    // Show the last fully completed IDS depth even while a deeper pass is
    // still running. Only fall back to a spinner/placeholder before the
    // first completed iteration arrives.
    final int? depth = _analysisEngineDepth();
    if (depth != null && depth > 0) {
      return math.min(99, depth).toString();
    }
    if (AnalysisMode.isAnalyzing) {
      return '...';
    }
    if (!AnalysisMode.isFullAnalysis) {
      return '-';
    }
    final int count = AnalysisMode.analysisResults.length;
    assert(count > 0, 'Full analysis mode must have at least one line.');
    return math.min(99, count).toString();
  }

  String _statusLabel(S strings) {
    final int? depth = _analysisEngineDepth();
    if (depth != null && depth > 0) {
      final String depthLabel = 'd${math.min(99, depth)}';
      if (AnalysisMode.isAnalyzing) {
        return '${strings.analyzing} · $depthLabel';
      }
      return depthLabel;
    }
    if (AnalysisMode.isAnalyzing) {
      return strings.analyzing;
    }
    if (!AnalysisMode.isFullAnalysis) {
      return strings.openingExplorerNoDataShort;
    }
    final int count = AnalysisMode.analysisResults.length;
    assert(count > 0, 'Full analysis mode must have at least one line.');
    return math.min(99, count).toString();
  }

  String _accessibleLabel(String statusLabel) {
    final bool sourceIncludesLabel = sourceLabel.contains(label);
    return <String>[
      if (sourceIncludesLabel) sourceLabel else label,
      if (!sourceIncludesLabel && sourceLabel != label) sourceLabel,
      statusLabel,
    ].join(' · ');
  }
}

class _AnalysisEngineChipPainter extends CustomPainter {
  const _AnalysisEngineChipPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    final Paint fill = Paint()
      ..color = color.withValues(alpha: 0.16)
      ..style = PaintingStyle.fill;

    final Rect body = Rect.fromLTWH(5, 5, size.width - 10, size.height - 10);
    final RRect outer = RRect.fromRectAndRadius(body, const Radius.circular(5));
    final RRect inner = RRect.fromRectAndRadius(
      body.deflate(4),
      const Radius.circular(2),
    );
    canvas.drawRRect(outer, fill);
    canvas.drawRRect(outer, stroke);
    canvas.drawRRect(inner, stroke..strokeWidth = 1);

    const double pinLength = 3;
    final double pinStep = body.height / 4;
    for (int i = 1; i <= 3; i++) {
      final double y = body.top + pinStep * i;
      canvas.drawLine(Offset(1, y), Offset(1 + pinLength, y), stroke);
      canvas.drawLine(
        Offset(size.width - 1 - pinLength, y),
        Offset(size.width - 1, y),
        stroke,
      );
      final double x = body.left + pinStep * i;
      canvas.drawLine(Offset(x, 1), Offset(x, 1 + pinLength), stroke);
      canvas.drawLine(
        Offset(x, size.height - 1 - pinLength),
        Offset(x, size.height - 1),
        stroke,
      );
    }
  }

  @override
  bool shouldRepaint(_AnalysisEngineChipPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class _BoardTransformPickerDialog extends StatelessWidget {
  const _BoardTransformPickerDialog({
    required this.sheetKey,
    required this.keyPrefix,
    required this.title,
    required this.currentBoardLayout,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.onSelected,
  });

  final Key sheetKey;
  final String keyPrefix;
  final String title;
  final String currentBoardLayout;
  final Color backgroundColor;
  final Color foregroundColor;
  final ValueChanged<MillBoardTransformAction> onSelected;

  @override
  Widget build(BuildContext context) {
    final List<_BoardTransformPreview> previews = _previews();
    assert(previews.isNotEmpty, 'Board transform picker must show options.');
    final int crossAxisCount = math.min(4, math.max(1, previews.length));
    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    return Dialog(
      key: sheetKey,
      backgroundColor: backgroundColor,
      surfaceTintColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: math.min(MediaQuery.sizeOf(context).width, 560),
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        child: IconTheme.merge(
          data: IconThemeData(color: foregroundColor),
          child: DefaultTextStyle.merge(
            style: TextStyle(color: foregroundColor),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Center(
                    child: Text(
                      title,
                      style: Theme.of(
                        context,
                      ).textTheme.titleMedium?.copyWith(color: foregroundColor),
                    ),
                  ),
                  const SizedBox(height: 16),
                  GridView.builder(
                    key: Key('${keyPrefix}_grid'),
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                      childAspectRatio: 0.78,
                    ),
                    itemCount: previews.length,
                    itemBuilder: (BuildContext context, int index) {
                      final _BoardTransformPreview preview = previews[index];
                      return _BoardTransformPreviewTile(
                        key: Key('${keyPrefix}_${preview.action.id}'),
                        label: preview.action.label(S.of(context)),
                        boardLayout: preview.boardLayout,
                        borderColor: colorScheme.outlineVariant,
                        onTap: () {
                          final NavigatorState navigator = Navigator.of(
                            context,
                          );
                          navigator.pop();
                          WidgetsBinding.instance.addPostFrameCallback(
                            (_) => onSelected(preview.action),
                          );
                        },
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<_BoardTransformPreview> _previews() {
    return <_BoardTransformPreview>[
      for (final MillBoardTransformAction action
          in allMillBoardTransformActions)
        _BoardTransformPreview(
          action: action,
          boardLayout: _boardLayoutAfter(action.type),
        ),
    ];
  }

  String _boardLayoutAfter(TransformationType type) {
    assert(
      currentBoardLayout.length == 26,
      'Board transform preview requires inner/middle/outer layout.',
    );
    final String boardOnly = currentBoardLayout.replaceAll('/', '');
    assert(boardOnly.length == 24, 'Board layout must contain 24 points.');
    final String transformed = transformString(boardOnly, type);
    return '${transformed.substring(0, 8)}/'
        '${transformed.substring(8, 16)}/'
        '${transformed.substring(16, 24)}';
  }
}

class _BoardTransformPreview {
  const _BoardTransformPreview({
    required this.action,
    required this.boardLayout,
  });

  final MillBoardTransformAction action;
  final String boardLayout;
}

class _BoardTransformPreviewTile extends StatelessWidget {
  const _BoardTransformPreviewTile({
    super.key,
    required this.label,
    required this.boardLayout,
    required this.borderColor,
    required this.onTap,
  });

  final String label;
  final String boardLayout;
  final Color borderColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        label: label,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(AppStyles.compactRadius),
            onTap: onTap,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppStyles.compactRadius),
                border: Border.all(color: borderColor),
              ),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Column(
                  children: <Widget>[
                    Expanded(
                      child: AspectRatio(
                        aspectRatio: 1,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(
                            AppStyles.compactRadius,
                          ),
                          child: ColoredBox(
                            color: DB().colorSettings.boardBackgroundColor,
                            child: CustomPaint(
                              painter: MiniBoardPainter(
                                boardLayout: boardLayout,
                              ),
                              child: const SizedBox.expand(),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: _transformTileForegroundColor(context),
                        letterSpacing: 0,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Color _transformTileForegroundColor(BuildContext context) {
  return DefaultTextStyle.of(context).style.color ??
      Theme.of(context).colorScheme.onSurface;
}

class _LichessGameBottomBar extends StatelessWidget {
  const _LichessGameBottomBar({
    required this.onMenuPressed,
    required this.onResignOrResultPressed,
    required this.onTakeBackPressed,
    required this.onHintPressed,
    required this.isShowingResult,
    required this.isHintHighlighted,
  });

  final VoidCallback onMenuPressed;
  final VoidCallback? onResignOrResultPressed;
  final VoidCallback? onTakeBackPressed;
  final VoidCallback? onHintPressed;
  final bool isShowingResult;
  final bool isHintHighlighted;

  @override
  Widget build(BuildContext context) {
    final Color messageColor = DB().colorSettings.messageColor;

    return LichessBottomBar(
      key: const Key('play_area_lichess_bottom_bar'),
      backgroundColor: Colors.transparent,
      foregroundColor: messageColor,
      children: <Widget>[
        LichessBottomBarButton(
          key: const Key('play_area_bottom_bar_menu'),
          icon: Icons.menu,
          label: S.of(context).menu,
          onTap: onMenuPressed,
          withShadow: true,
        ),
        LichessBottomBarButton(
          key: const Key('play_area_bottom_bar_resign'),
          icon: isShowingResult ? Icons.info_outline : CupertinoIcons.flag,
          label: isShowingResult ? S.of(context).results : S.of(context).resign,
          onTap: onResignOrResultPressed,
          highlighted: isShowingResult,
          withShadow: true,
        ),
        LichessBottomBarButton(
          key: const Key('play_area_bottom_bar_take_back'),
          icon: CupertinoIcons.arrow_uturn_left,
          label: S.of(context).takeBack,
          onTap: onTakeBackPressed,
          withShadow: true,
        ),
        LichessBottomBarButton(
          key: const Key('play_area_bottom_bar_hint'),
          icon: CupertinoIcons.lightbulb,
          highlightedIcon: CupertinoIcons.lightbulb_fill,
          label: isHintHighlighted
              ? S.of(context).turnOffHint
              : S.of(context).getAHint,
          onTap: onHintPressed,
          highlighted: isHintHighlighted,
          highlightedContainer: true,
          isToggleButton: true,
          withShadow: true,
        ),
      ],
    );
  }
}
