// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// rule_settings_page.dart

// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:hive_ce_flutter/hive_flutter.dart' show Box;

import '../../custom_drawer/custom_drawer.dart';
import '../../game_page/services/mill.dart';
import '../../generated/intl/l10n.dart';
import '../../shared/database/database.dart';
import '../../shared/services/logger.dart';
import '../../shared/themes/app_theme.dart';
import '../../shared/widgets/settings/settings.dart';
import '../../shared/widgets/snackbars/scaffold_messenger.dart';
import '../models/rule_settings.dart';

part 'modals/board_full_action_modal.dart';
part 'modals/endgame_n_move_rule_modal.dart';
part 'modals/fly_piece_count_modal.dart';
part 'modals/mill_formation_action_in_placing_phase_modal.dart';
part 'modals/n_move_rule_modal.dart';
part 'modals/piece_count_modal.dart';
part 'modals/rule_set_modal.dart';
part 'modals/stalemate_action_modal.dart';

bool visitedRuleSettingsPage = false;

class RuleSettingsPage extends StatelessWidget {
  const RuleSettingsPage({super.key});

  // Rule set
  void _setRuleSet(BuildContext context, RuleSettings ruleSettings) {
    void callback(RuleSet? ruleSet) {
      Navigator.pop(context); // Closes the modal after selection.

      if (ruleSet == RuleSet.current) {
        return; // If the selected rule set is the current one, do nothing.
      }

      if (ruleSet == RuleSet.zhiQi ||
          ruleSet == RuleSet.chengSanQi ||
          ruleSet == RuleSet.daSanQi ||
          ruleSet == RuleSet.mulMulan ||
          ruleSet == RuleSet.nerenchi ||
          ruleSet == RuleSet.elfilja) {
        rootScaffoldMessengerKey.currentState!.showSnackBarClear(
          S.of(context).experimental,
        );
      }

      // Updates the rule settings with the new rule set.
      final RuleSettings? newRuleSettings = ruleSetProperties[ruleSet];
      if (newRuleSettings != null) {
        DB().ruleSettings = newRuleSettings;
      }
    }

    // Display a modal bottom sheet with the available rule sets.
    showModalBottomSheet(
      context: context,
      builder: (_) =>
          _RuleSetModal(ruleSet: RuleSet.current, onChanged: callback),
    );
  }

  // General
  void _setNTotalPiecesEachSide(
    BuildContext context,
    RuleSettings ruleSettings,
  ) {
    void callback(int? piecesCount) {
      Navigator.pop(context);

      DB().ruleSettings = ruleSettings.copyWith(piecesCount: piecesCount ?? 9);

      logger.t("[config] piecesCount = ${piecesCount ?? 9}");

      if (DB().generalSettings.usePerfectDatabase) {
        rootScaffoldMessengerKey.currentState!.showSnackBarClear(
          S.of(context).reopenToTakeEffect,
        );
      }
    }

    showModalBottomSheet(
      context: context,
      builder: (_) => _PieceCountModal(
        piecesCount: ruleSettings.piecesCount,
        onChanged: callback,
      ),
    );
  }

  void _setNMoveRule(BuildContext context, RuleSettings ruleSettings) {
    void callback(int? nMoveRule) {
      Navigator.pop(context);

      DB().ruleSettings = ruleSettings.copyWith(nMoveRule: nMoveRule ?? 100);

      logger.t("[config] nMoveRule = ${nMoveRule ?? 100}");
    }

    showModalBottomSheet(
      context: context,
      builder: (_) => _NMoveRuleModal(
        nMoveRule: ruleSettings.nMoveRule,
        onChanged: callback,
      ),
    );
  }

  // TODO: This feature EndgameNMoveRule is not implemented yet
  void _setEndgameNMoveRule(BuildContext context, RuleSettings ruleSettings) {
    void callback(int? endgameNMoveRule) {
      if (endgameNMoveRule == null ||
          endgameNMoveRule < DB().ruleSettings.nMoveRule) {
        rootScaffoldMessengerKey.currentState!.showSnackBarClear(
          S.of(context).experimental,
        );
      }

      Navigator.pop(context);

      DB().ruleSettings = ruleSettings.copyWith(
        endgameNMoveRule: endgameNMoveRule ?? 100,
      );

      logger.t("[config] endgameNMoveRule = ${endgameNMoveRule ?? 100}");
    }

    showModalBottomSheet(
      context: context,
      builder: (_) => _EndGameNMoveRuleModal(
        endgameNMoveRule: ruleSettings.endgameNMoveRule,
        onChanged: callback,
      ),
    );
  }

  void _setFlyPieceCount(BuildContext context, RuleSettings ruleSettings) {
    void callback(int? flyPieceCount) {
      Navigator.pop(context);

      DB().ruleSettings = ruleSettings.copyWith(
        flyPieceCount: flyPieceCount ?? 3,
      );

      logger.t("[config] flyPieceCount = ${flyPieceCount ?? 3}");
    }

    showModalBottomSheet(
      context: context,
      builder: (_) => _FlyPieceCountModal(
        flyPieceCount: ruleSettings.flyPieceCount,
        onChanged: callback,
      ),
    );
  }

  void _setHasDiagonalLines(RuleSettings ruleSettings, bool value) {
    DB().ruleSettings = ruleSettings.copyWith(hasDiagonalLines: value);

    logger.t("[config] hasDiagonalLines: $value");
  }

  void _setAllowFlyingAllowed(RuleSettings ruleSettings, bool value) {
    DB().ruleSettings = ruleSettings.copyWith(mayFly: value);

    logger.t("[config] mayFly: $value");
  }

  void _setThreefoldRepetitionRule(RuleSettings ruleSettings, bool value) {
    DB().ruleSettings = ruleSettings.copyWith(threefoldRepetitionRule: value);

    logger.t("[config] threefoldRepetitionRule: $value");
  }

  // Placing
  void _setBoardFullAction(BuildContext context, RuleSettings ruleSettings) {
    void callback(BoardFullAction? boardFullAction) {
      Navigator.pop(context);

      DB().ruleSettings = ruleSettings.copyWith(
        boardFullAction: boardFullAction,
      );

      logger.t("[config] boardFullAction = $boardFullAction");

      // TODO: BoardFullAction: experimental
      if (boardFullAction != BoardFullAction.firstPlayerLose &&
          boardFullAction != BoardFullAction.agreeToDraw) {
        rootScaffoldMessengerKey.currentState!.showSnackBarClear(
          S.of(context).experimental,
        );
      }
    }

    showModalBottomSheet(
      context: context,
      builder: (_) => _BoardFullActionModal(
        boardFullAction: ruleSettings.boardFullAction!,
        onChanged: callback,
      ),
    );
  }

  void _setMillFormationActionInPlacingPhase(
    BuildContext context,
    RuleSettings ruleSettings,
  ) {
    void callback(
      MillFormationActionInPlacingPhase? millFormationActionInPlacingPhase,
    ) {
      Navigator.pop(context);

      DB().ruleSettings = ruleSettings.copyWith(
        millFormationActionInPlacingPhase: millFormationActionInPlacingPhase,
      );

      switch (millFormationActionInPlacingPhase) {
        case MillFormationActionInPlacingPhase.removeOpponentsPieceFromBoard:
          rootScaffoldMessengerKey.currentState!.showSnackBarClear(
            S.of(context).removeOpponentsPieceFromBoard_Detail,
          );
          break;
        case MillFormationActionInPlacingPhase
            .removeOpponentsPieceFromHandThenOpponentsTurn:
          rootScaffoldMessengerKey.currentState!.showSnackBarClear(
            S.of(context).removeOpponentsPieceFromHandThenOpponentsTurn_Detail,
          );
          break;
        case MillFormationActionInPlacingPhase
            .removeOpponentsPieceFromHandThenYourTurn:
          rootScaffoldMessengerKey.currentState!.showSnackBarClear(
            S.of(context).removeOpponentsPieceFromHandThenYourTurn_Detail,
          );
          break;
        case MillFormationActionInPlacingPhase.opponentRemovesOwnPiece:
          rootScaffoldMessengerKey.currentState!.showSnackBarClear(
            S.of(context).opponentRemovesOwnPiece_Detail,
          );
          break;
        case MillFormationActionInPlacingPhase.markAndDelayRemovingPieces:
          rootScaffoldMessengerKey.currentState!.showSnackBarClear(
            S.of(context).markAndDelayRemovingPieces_Detail,
          );
          break;
        case MillFormationActionInPlacingPhase.removalBasedOnMillCounts:
          rootScaffoldMessengerKey.currentState!.showSnackBarClear(
            S.of(context).removalBasedOnMillCounts_Detail,
          );
          break;
        case null:
          break;
      }

      logger.t(
        "[config] millFormationActionInPlacingPhase = $millFormationActionInPlacingPhase",
      );
    }

    showModalBottomSheet(
      context: context,
      builder: (_) => _MillFormationActionInPlacingPhaseModal(
        millFormationActionInPlacingPhase:
            ruleSettings.millFormationActionInPlacingPhase!,
        onChanged: callback,
      ),
    );
  }

  // Moving
  void _setMayMoveInPlacingPhase(
    BuildContext context,
    RuleSettings ruleSettings,
    bool value,
  ) {
    DB().ruleSettings = ruleSettings.copyWith(mayMoveInPlacingPhase: value);

    logger.t("[config] mayMoveInPlacingPhase: $value");

    if (DB().generalSettings.usePerfectDatabase) {
      rootScaffoldMessengerKey.currentState!.showSnackBarClear(
        S.of(context).reopenToTakeEffect,
      );
    }
  }

  void _setIsDefenderMoveFirst(RuleSettings ruleSettings, bool value) {
    DB().ruleSettings = ruleSettings.copyWith(isDefenderMoveFirst: value);

    logger.t("[config] isDefenderMoveFirst: $value");
  }

  void _setRestrictRepeatedMillsFormation(
    RuleSettings ruleSettings,
    bool value,
  ) {
    DB().ruleSettings = ruleSettings.copyWith(
      restrictRepeatedMillsFormation: value,
    );

    logger.t("[config] restrictRepeatedMillsFormation: $value");
  }

  void _setStalemateAction(BuildContext context, RuleSettings ruleSettings) {
    void callback(StalemateAction? stalemateAction) {
      Navigator.pop(context);

      DB().ruleSettings = ruleSettings.copyWith(
        stalemateAction: stalemateAction,
      );

      logger.t("[config] stalemateAction = $stalemateAction");

      // TODO: StalemateAction: experimental
      if (stalemateAction != StalemateAction.endWithStalemateLoss &&
          stalemateAction != StalemateAction.changeSideToMove) {
        rootScaffoldMessengerKey.currentState!.showSnackBarClear(
          S.of(context).experimental,
        );
      }
    }

    showModalBottomSheet(
      context: context,
      builder: (_) => _StalemateActionModal(
        stalemateAction: ruleSettings.stalemateAction!,
        onChanged: callback,
      ),
    );
  }

  // Removing
  void _setAllowRemovePieceInMill(RuleSettings ruleSettings, bool value) {
    DB().ruleSettings = ruleSettings.copyWith(mayRemoveFromMillsAlways: value);

    logger.t("[config] mayRemoveFromMillsAlways: $value");
  }

  void _setAllowRemoveMultiPiecesWhenCloseMultiMill(
    RuleSettings ruleSettings,
    bool value,
  ) {
    DB().ruleSettings = ruleSettings.copyWith(mayRemoveMultiple: value);

    logger.t("[config] mayRemoveMultiple: $value");
  }

  void _setOneTimeUseMill(RuleSettings ruleSettings, bool value) {
    DB().ruleSettings = ruleSettings.copyWith(oneTimeUseMill: value);

    logger.t("[config] oneTimeUseMill: $value");
  }

  void _updateRuleSettingsBool(
    RuleSettings ruleSettings,
    RuleSettings Function(RuleSettings) updater,
    String fieldName,
    bool value,
  ) {
    DB().ruleSettings = updater(ruleSettings);

    logger.t("[config] $fieldName: $value");
  }

  void _setCustodianCaptureEnabled(RuleSettings ruleSettings, bool value) {
    _updateRuleSettingsBool(
      ruleSettings,
      (RuleSettings settings) =>
          settings.copyWith(enableCustodianCapture: value),
      'enableCustodianCapture',
      value,
    );
  }

  void _setCustodianCaptureOnSquareEdges(
    RuleSettings ruleSettings,
    bool value,
  ) {
    _updateRuleSettingsBool(
      ruleSettings,
      (RuleSettings settings) =>
          settings.copyWith(custodianCaptureOnSquareEdges: value),
      'custodianCaptureOnSquareEdges',
      value,
    );
  }

  void _setCustodianCaptureOnCrossLines(RuleSettings ruleSettings, bool value) {
    _updateRuleSettingsBool(
      ruleSettings,
      (RuleSettings settings) =>
          settings.copyWith(custodianCaptureOnCrossLines: value),
      'custodianCaptureOnCrossLines',
      value,
    );
  }

  void _setCustodianCaptureOnDiagonalLines(
    RuleSettings ruleSettings,
    bool value,
  ) {
    _updateRuleSettingsBool(
      ruleSettings,
      (RuleSettings settings) =>
          settings.copyWith(custodianCaptureOnDiagonalLines: value),
      'custodianCaptureOnDiagonalLines',
      value,
    );
  }

  void _setCustodianCaptureInPlacingPhase(
    RuleSettings ruleSettings,
    bool value,
  ) {
    _updateRuleSettingsBool(
      ruleSettings,
      (RuleSettings settings) =>
          settings.copyWith(custodianCaptureInPlacingPhase: value),
      'custodianCaptureInPlacingPhase',
      value,
    );
  }

  void _setCustodianCaptureInMovingPhase(
    RuleSettings ruleSettings,
    bool value,
  ) {
    _updateRuleSettingsBool(
      ruleSettings,
      (RuleSettings settings) =>
          settings.copyWith(custodianCaptureInMovingPhase: value),
      'custodianCaptureInMovingPhase',
      value,
    );
  }

  void _setCustodianCaptureOnlyWhenOwnPiecesLeq3(
    RuleSettings ruleSettings,
    bool value,
  ) {
    _updateRuleSettingsBool(
      ruleSettings,
      (RuleSettings settings) =>
          settings.copyWith(custodianCaptureOnlyWhenOwnPiecesLeq3: value),
      'custodianCaptureOnlyWhenOwnPiecesLeq3',
      value,
    );
  }

  void _setInterventionCaptureEnabled(RuleSettings ruleSettings, bool value) {
    _updateRuleSettingsBool(
      ruleSettings,
      (RuleSettings settings) =>
          settings.copyWith(enableInterventionCapture: value),
      'enableInterventionCapture',
      value,
    );
  }

  void _setInterventionCaptureOnSquareEdges(
    RuleSettings ruleSettings,
    bool value,
  ) {
    _updateRuleSettingsBool(
      ruleSettings,
      (RuleSettings settings) =>
          settings.copyWith(interventionCaptureOnSquareEdges: value),
      'interventionCaptureOnSquareEdges',
      value,
    );
  }

  void _setInterventionCaptureOnCrossLines(
    RuleSettings ruleSettings,
    bool value,
  ) {
    _updateRuleSettingsBool(
      ruleSettings,
      (RuleSettings settings) =>
          settings.copyWith(interventionCaptureOnCrossLines: value),
      'interventionCaptureOnCrossLines',
      value,
    );
  }

  void _setInterventionCaptureOnDiagonalLines(
    RuleSettings ruleSettings,
    bool value,
  ) {
    _updateRuleSettingsBool(
      ruleSettings,
      (RuleSettings settings) =>
          settings.copyWith(interventionCaptureOnDiagonalLines: value),
      'interventionCaptureOnDiagonalLines',
      value,
    );
  }

  void _setInterventionCaptureInPlacingPhase(
    RuleSettings ruleSettings,
    bool value,
  ) {
    _updateRuleSettingsBool(
      ruleSettings,
      (RuleSettings settings) =>
          settings.copyWith(interventionCaptureInPlacingPhase: value),
      'interventionCaptureInPlacingPhase',
      value,
    );
  }

  void _setInterventionCaptureInMovingPhase(
    RuleSettings ruleSettings,
    bool value,
  ) {
    _updateRuleSettingsBool(
      ruleSettings,
      (RuleSettings settings) =>
          settings.copyWith(interventionCaptureInMovingPhase: value),
      'interventionCaptureInMovingPhase',
      value,
    );
  }

  void _setInterventionCaptureOnlyWhenOwnPiecesLeq3(
    RuleSettings ruleSettings,
    bool value,
  ) {
    _updateRuleSettingsBool(
      ruleSettings,
      (RuleSettings settings) =>
          settings.copyWith(interventionCaptureOnlyWhenOwnPiecesLeq3: value),
      'interventionCaptureOnlyWhenOwnPiecesLeq3',
      value,
    );
  }

  void _setLeapCaptureEnabled(RuleSettings ruleSettings, bool value) {
    _updateRuleSettingsBool(
      ruleSettings,
      (RuleSettings settings) => settings.copyWith(enableLeapCapture: value),
      'enableLeapCapture',
      value,
    );
  }

  void _setLeapCaptureOnSquareEdges(RuleSettings ruleSettings, bool value) {
    _updateRuleSettingsBool(
      ruleSettings,
      (RuleSettings settings) =>
          settings.copyWith(leapCaptureOnSquareEdges: value),
      'leapCaptureOnSquareEdges',
      value,
    );
  }

  void _setLeapCaptureOnCrossLines(RuleSettings ruleSettings, bool value) {
    _updateRuleSettingsBool(
      ruleSettings,
      (RuleSettings settings) =>
          settings.copyWith(leapCaptureOnCrossLines: value),
      'leapCaptureOnCrossLines',
      value,
    );
  }

  void _setLeapCaptureOnDiagonalLines(RuleSettings ruleSettings, bool value) {
    _updateRuleSettingsBool(
      ruleSettings,
      (RuleSettings settings) =>
          settings.copyWith(leapCaptureOnDiagonalLines: value),
      'leapCaptureOnDiagonalLines',
      value,
    );
  }

  void _setLeapCaptureInPlacingPhase(RuleSettings ruleSettings, bool value) {
    _updateRuleSettingsBool(
      ruleSettings,
      (RuleSettings settings) =>
          settings.copyWith(leapCaptureInPlacingPhase: value),
      'leapCaptureInPlacingPhase',
      value,
    );
  }

  void _setLeapCaptureInMovingPhase(RuleSettings ruleSettings, bool value) {
    _updateRuleSettingsBool(
      ruleSettings,
      (RuleSettings settings) =>
          settings.copyWith(leapCaptureInMovingPhase: value),
      'leapCaptureInMovingPhase',
      value,
    );
  }

  void _setLeapCaptureOnlyWhenOwnPiecesLeq3(
    RuleSettings ruleSettings,
    bool value,
  ) {
    _updateRuleSettingsBool(
      ruleSettings,
      (RuleSettings settings) =>
          settings.copyWith(leapCaptureOnlyWhenOwnPiecesLeq3: value),
      'leapCaptureOnlyWhenOwnPiecesLeq3',
      value,
    );
  }

  Widget _buildCaptureOptionGroup({
    required String label,
    required List<Widget> tiles,
  }) {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text(label, style: AppTheme.listTileTitleStyle),
          ),
          const SizedBox(height: 8),
          ListTileTheme(
            data: const ListTileThemeData(contentPadding: EdgeInsets.zero),
            child: Column(
              children: <Widget>[
                for (int i = 0; i < tiles.length; i++) ...<Widget>[
                  tiles[i],
                  if (i < tiles.length - 1) const SizedBox(height: 4),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCaptureCheckboxTile({
    required String keyPrefix,
    required String keySuffix,
    required String label,
    required bool enabled,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return CheckboxListTile(
      key: Key('rule_settings_checkbox_${keyPrefix}_$keySuffix'),
      value: value,
      onChanged: enabled
          ? (bool? newValue) => onChanged(newValue ?? false)
          : null,
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.trailing,
      title: Text(label, style: AppTheme.listTileTitleStyle),
    );
  }

  Widget _buildCaptureRadioTile({
    required String keyPrefix,
    required String keySuffix,
    required String label,
    required bool enabled,
    required bool value,
    required bool groupValue,
    required ValueChanged<bool> onChanged,
  }) {
    return RadioListTile<bool>(
      key: Key('rule_settings_radio_${keyPrefix}_$keySuffix'),
      value: value,
      groupValue: groupValue,
      onChanged: enabled
          ? (bool? newValue) => onChanged(newValue ?? false)
          : null,
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.trailing,
      title: Text(label, style: AppTheme.listTileTitleStyle),
    );
  }

  SettingsCard _buildCaptureRuleCard({
    required BuildContext context,
    required String keyPrefix,
    required String title,
    required String enableLabel,
    required String description,
    required bool enabled,
    required ValueChanged<bool> onEnabledChanged,
    required bool onSquareEdges,
    required ValueChanged<bool> onSquareEdgesChanged,
    required bool onCrossLines,
    required ValueChanged<bool> onCrossLinesChanged,
    required bool onDiagonalLines,
    required ValueChanged<bool> onDiagonalLinesChanged,
    required bool inPlacingPhase,
    required ValueChanged<bool> onInPlacingPhaseChanged,
    required bool inMovingPhase,
    required ValueChanged<bool> onInMovingPhaseChanged,
    required bool onlyWhenOwnPiecesLeq3,
    required ValueChanged<bool> onOnlyWhenOwnPiecesLeq3Changed,
  }) {
    const TextStyle subtitleStyle = AppTheme.listTileSubtitleStyle;

    return SettingsCard(
      key: Key('rule_settings_card_$keyPrefix'),
      title: Text(title),
      children: <Widget>[
        SwitchListTile(
          key: Key('rule_settings_switch_${keyPrefix}_enabled'),
          value: enabled,
          onChanged: onEnabledChanged,
          title: Text(enableLabel, style: AppTheme.listTileTitleStyle),
          subtitle: Text(description, style: subtitleStyle),
        ),
        // Only show additional options when the main toggle is enabled
        if (enabled) ...<Widget>[
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            child: _buildCaptureOptionGroup(
              label: S.of(context).captureApplicableLines,
              tiles: <Widget>[
                _buildCaptureCheckboxTile(
                  keyPrefix: keyPrefix,
                  keySuffix: 'square_edges',
                  label: S.of(context).captureSquareEdges,
                  enabled: enabled,
                  value: onSquareEdges,
                  onChanged: onSquareEdgesChanged,
                ),
                _buildCaptureCheckboxTile(
                  keyPrefix: keyPrefix,
                  keySuffix: 'cross_lines',
                  label: S.of(context).captureCrossLines,
                  enabled: enabled,
                  value: onCrossLines,
                  onChanged: onCrossLinesChanged,
                ),
                _buildCaptureCheckboxTile(
                  keyPrefix: keyPrefix,
                  keySuffix: 'diagonal_lines',
                  label: S.of(context).captureDiagonalLines,
                  enabled: enabled,
                  value: onDiagonalLines,
                  onChanged: onDiagonalLinesChanged,
                ),
              ],
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            child: _buildCaptureOptionGroup(
              label: S.of(context).captureExecutionPhases,
              tiles: <Widget>[
                _buildCaptureCheckboxTile(
                  keyPrefix: keyPrefix,
                  keySuffix: 'placing_phase',
                  label: S.of(context).placingPhase,
                  enabled: enabled,
                  value: inPlacingPhase,
                  onChanged: onInPlacingPhaseChanged,
                ),
                _buildCaptureCheckboxTile(
                  keyPrefix: keyPrefix,
                  keySuffix: 'moving_phase',
                  label: S.of(context).movingPhase,
                  enabled: enabled,
                  value: inMovingPhase,
                  onChanged: onInMovingPhaseChanged,
                ),
              ],
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            child: _buildCaptureOptionGroup(
              label: S.of(context).capturePiecesCondition,
              tiles: <Widget>[
                _buildCaptureRadioTile(
                  keyPrefix: keyPrefix,
                  keySuffix: 'unlimited',
                  label: S.of(context).capturePiecesConditionUnlimited,
                  enabled: enabled,
                  value: false,
                  groupValue: onlyWhenOwnPiecesLeq3,
                  onChanged: onOnlyWhenOwnPiecesLeq3Changed,
                ),
                _buildCaptureRadioTile(
                  keyPrefix: keyPrefix,
                  keySuffix: 'self_leq_three',
                  label: S.of(context).capturePiecesConditionSelfLeqThree,
                  enabled: enabled,
                  value: true,
                  groupValue: onlyWhenOwnPiecesLeq3,
                  onChanged: onOnlyWhenOwnPiecesLeq3Changed,
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildRuleSettings(BuildContext context, Box<RuleSettings> box, _) {
    final Locale? locale = DB().displaySettings.locale;

    final RuleSettings ruleSettings = box.get(
      DB.ruleSettingsKey,
      defaultValue: RuleSettings.fromLocale(locale),
    )!;
    return SettingsList(
      key: const Key('rule_settings_list'),
      children: <Widget>[
        SettingsCard(
          key: const Key('rule_settings_card_rule_set'),
          title: Text(S.of(context).ruleSet),
          children: <Widget>[
            SettingsListTile(
              key: const Key('rule_settings_tile_rule_set'),
              titleString: S.of(context).ruleSet,
              //subtitleString: S.of(context).ruleSet_Detail,
              //trailingString: ruleSettings.ruleSet,
              onTap: () => _setRuleSet(context, ruleSettings),
            ),
          ],
        ),
        SettingsCard(
          key: const Key('rule_settings_card_general'),
          title: Text(S.of(context).general),
          children: <Widget>[
            SettingsListTile(
              key: const Key('rule_settings_tile_pieces_count'),
              titleString: S.of(context).piecesCount,
              subtitleString: S.of(context).piecesCount_Detail,
              trailingString: ruleSettings.piecesCount.toString(),
              onTap: () => _setNTotalPiecesEachSide(context, ruleSettings),
            ),
            SettingsListTile.switchTile(
              key: const Key('rule_settings_switch_has_diagonal_lines'),
              value: ruleSettings.hasDiagonalLines,
              onChanged: (bool val) => _setHasDiagonalLines(ruleSettings, val),
              titleString: S.of(context).hasDiagonalLines,
              subtitleString: S.of(context).hasDiagonalLines_Detail,
            ),
            SettingsListTile(
              key: const Key('rule_settings_tile_n_move_rule'),
              titleString: S.of(context).nMoveRule,
              subtitleString: S.of(context).nMoveRule_Detail,
              trailingString: ruleSettings.nMoveRule.toString(),
              onTap: () => _setNMoveRule(context, ruleSettings),
            ),
            SettingsListTile(
              key: const Key('rule_settings_tile_endgame_n_move_rule'),
              titleString: S.of(context).endgameNMoveRule,
              subtitleString: S.of(context).endgameNMoveRule_Detail,
              trailingString: ruleSettings.endgameNMoveRule.toString(),
              onTap: () => _setEndgameNMoveRule(context, ruleSettings),
            ),
            SettingsListTile.switchTile(
              key: const Key('rule_settings_switch_threefold_repetition_rule'),
              value: ruleSettings.threefoldRepetitionRule,
              onChanged: (bool val) =>
                  _setThreefoldRepetitionRule(ruleSettings, val),
              titleString: S.of(context).threefoldRepetitionRule,
              subtitleString: S.of(context).threefoldRepetitionRule_Detail,
            ),
          ],
        ),
        SettingsCard(
          key: const Key('rule_settings_card_placing_phase'),
          title: Text(S.of(context).placingPhase),
          children: <Widget>[
            SettingsListTile(
              key: const Key(
                'rule_settings_tile_mill_formation_action_in_placing_phase',
              ),
              onTap: () =>
                  _setMillFormationActionInPlacingPhase(context, ruleSettings),
              titleString: S.of(context).whenFormingMillsDuringPlacingPhase,
              subtitleString: S
                  .of(context)
                  .whenFormingMillsDuringPlacingPhase_Detail,
            ),
            if (DB().ruleSettings.millFormationActionInPlacingPhase !=
                MillFormationActionInPlacingPhase.removalBasedOnMillCounts)
              SettingsListTile(
                key: const Key('rule_settings_tile_board_full_action'),
                onTap: () => _setBoardFullAction(context, ruleSettings),
                titleString: S.of(context).whenBoardIsFull,
                subtitleString: S.of(context).whenBoardIsFull_Detail,
              ),
            SettingsListTile.switchTile(
              key: const Key('rule_settings_switch_may_move_in_placing_phase'),
              value: ruleSettings.mayMoveInPlacingPhase,
              onChanged: (bool val) =>
                  _setMayMoveInPlacingPhase(context, ruleSettings, val),
              titleString: S.of(context).mayMoveInPlacingPhase,
              subtitleString: S.of(context).mayMoveInPlacingPhase_Detail,
            ),
          ],
        ),
        SettingsCard(
          key: const Key('rule_settings_card_moving_phase'),
          title: Text(S.of(context).movingPhase),
          children: <Widget>[
            SettingsListTile.switchTile(
              key: const Key('rule_settings_switch_is_defender_move_first'),
              value: ruleSettings.isDefenderMoveFirst,
              onChanged: (bool val) =>
                  _setIsDefenderMoveFirst(ruleSettings, val),
              titleString: S.of(context).isDefenderMoveFirst,
              subtitleString: S.of(context).isDefenderMoveFirst_Detail,
            ),
            SettingsListTile.switchTile(
              key: const Key(
                'rule_settings_switch_restrict_repeated_mills_formation',
              ),
              value: ruleSettings.restrictRepeatedMillsFormation,
              onChanged: (bool val) =>
                  _setRestrictRepeatedMillsFormation(ruleSettings, val),
              titleString: S.of(context).restrictRepeatedMillsFormation,
              subtitleString: S
                  .of(context)
                  .restrictRepeatedMillsFormation_Detail,
            ),
            SettingsListTile(
              key: const Key('rule_settings_tile_stalemate_action'),
              onTap: () => _setStalemateAction(context, ruleSettings),
              titleString: S.of(context).whenStalemate,
              subtitleString: S.of(context).whenStalemate_Detail,
            ),
          ],
        ),
        SettingsCard(
          key: const Key('rule_settings_card_may_fly'),
          title: Text(S.of(context).mayFly),
          children: <Widget>[
            SettingsListTile.switchTile(
              key: const Key('rule_settings_switch_may_fly'),
              value: ruleSettings.mayFly,
              onChanged: (bool val) =>
                  _setAllowFlyingAllowed(ruleSettings, val),
              titleString: S.of(context).mayFly,
              subtitleString: S.of(context).mayFly_Detail,
            ),
            SettingsListTile(
              key: const Key('rule_settings_tile_fly_piece_count'),
              titleString: S.of(context).flyPieceCount,
              subtitleString: S.of(context).flyPieceCount_Detail,
              trailingString: ruleSettings.flyPieceCount.toString(),
              onTap: () => _setFlyPieceCount(context, ruleSettings),
            ),
          ],
        ),
        SettingsCard(
          key: const Key('rule_settings_card_removing'),
          title: Text(S.of(context).removing),
          children: <Widget>[
            SettingsListTile.switchTile(
              key: const Key(
                'rule_settings_switch_may_remove_from_mills_always',
              ),
              value: ruleSettings.mayRemoveFromMillsAlways,
              onChanged: (bool val) =>
                  _setAllowRemovePieceInMill(ruleSettings, val),
              titleString: S.of(context).mayRemoveFromMillsAlways,
              subtitleString: S.of(context).mayRemoveFromMillsAlways_Detail,
            ),
            SettingsListTile.switchTile(
              key: const Key('rule_settings_switch_may_remove_multiple'),
              value: ruleSettings.mayRemoveMultiple,
              onChanged: (bool val) =>
                  _setAllowRemoveMultiPiecesWhenCloseMultiMill(
                    ruleSettings,
                    val,
                  ),
              titleString: S.of(context).mayRemoveMultiple,
              subtitleString: S.of(context).mayRemoveMultiple_Detail,
            ),
            SettingsListTile.switchTile(
              key: const Key('rule_settings_switch_one_time_use_mill'),
              value: ruleSettings.oneTimeUseMill,
              onChanged: (bool val) => _setOneTimeUseMill(ruleSettings, val),
              titleString: S.of(context).oneTimeUseMill,
              subtitleString: S.of(context).oneTimeUseMill_Detail,
            ),
          ],
        ),
        _buildCaptureRuleCard(
          context: context,
          keyPrefix: 'custodian_capture',
          title: S.of(context).custodianCapture,
          enableLabel: S.of(context).custodianCaptureEnable,
          description: S.of(context).custodianCaptureDescription,
          enabled: ruleSettings.enableCustodianCapture,
          onEnabledChanged: (bool value) =>
              _setCustodianCaptureEnabled(ruleSettings, value),
          onSquareEdges: ruleSettings.custodianCaptureOnSquareEdges,
          onSquareEdgesChanged: (bool value) =>
              _setCustodianCaptureOnSquareEdges(ruleSettings, value),
          onCrossLines: ruleSettings.custodianCaptureOnCrossLines,
          onCrossLinesChanged: (bool value) =>
              _setCustodianCaptureOnCrossLines(ruleSettings, value),
          onDiagonalLines: ruleSettings.custodianCaptureOnDiagonalLines,
          onDiagonalLinesChanged: (bool value) =>
              _setCustodianCaptureOnDiagonalLines(ruleSettings, value),
          inPlacingPhase: ruleSettings.custodianCaptureInPlacingPhase,
          onInPlacingPhaseChanged: (bool value) =>
              _setCustodianCaptureInPlacingPhase(ruleSettings, value),
          inMovingPhase: ruleSettings.custodianCaptureInMovingPhase,
          onInMovingPhaseChanged: (bool value) =>
              _setCustodianCaptureInMovingPhase(ruleSettings, value),
          onlyWhenOwnPiecesLeq3:
              ruleSettings.custodianCaptureOnlyWhenOwnPiecesLeq3,
          onOnlyWhenOwnPiecesLeq3Changed: (bool value) =>
              _setCustodianCaptureOnlyWhenOwnPiecesLeq3(ruleSettings, value),
        ),
        _buildCaptureRuleCard(
          context: context,
          keyPrefix: 'intervention_capture',
          title: S.of(context).interventionCapture,
          enableLabel: S.of(context).interventionCaptureEnable,
          description: S.of(context).interventionCaptureDescription,
          enabled: ruleSettings.enableInterventionCapture,
          onEnabledChanged: (bool value) =>
              _setInterventionCaptureEnabled(ruleSettings, value),
          onSquareEdges: ruleSettings.interventionCaptureOnSquareEdges,
          onSquareEdgesChanged: (bool value) =>
              _setInterventionCaptureOnSquareEdges(ruleSettings, value),
          onCrossLines: ruleSettings.interventionCaptureOnCrossLines,
          onCrossLinesChanged: (bool value) =>
              _setInterventionCaptureOnCrossLines(ruleSettings, value),
          onDiagonalLines: ruleSettings.interventionCaptureOnDiagonalLines,
          onDiagonalLinesChanged: (bool value) =>
              _setInterventionCaptureOnDiagonalLines(ruleSettings, value),
          inPlacingPhase: ruleSettings.interventionCaptureInPlacingPhase,
          onInPlacingPhaseChanged: (bool value) =>
              _setInterventionCaptureInPlacingPhase(ruleSettings, value),
          inMovingPhase: ruleSettings.interventionCaptureInMovingPhase,
          onInMovingPhaseChanged: (bool value) =>
              _setInterventionCaptureInMovingPhase(ruleSettings, value),
          onlyWhenOwnPiecesLeq3:
              ruleSettings.interventionCaptureOnlyWhenOwnPiecesLeq3,
          onOnlyWhenOwnPiecesLeq3Changed: (bool value) =>
              _setInterventionCaptureOnlyWhenOwnPiecesLeq3(ruleSettings, value),
        ),
        _buildCaptureRuleCard(
          context: context,
          keyPrefix: 'leap_capture',
          title: S.of(context).leapCapture,
          enableLabel: S.of(context).leapCaptureEnable,
          description: S.of(context).leapCaptureDescription,
          enabled: ruleSettings.enableLeapCapture,
          onEnabledChanged: (bool value) =>
              _setLeapCaptureEnabled(ruleSettings, value),
          onSquareEdges: ruleSettings.leapCaptureOnSquareEdges,
          onSquareEdgesChanged: (bool value) =>
              _setLeapCaptureOnSquareEdges(ruleSettings, value),
          onCrossLines: ruleSettings.leapCaptureOnCrossLines,
          onCrossLinesChanged: (bool value) =>
              _setLeapCaptureOnCrossLines(ruleSettings, value),
          onDiagonalLines: ruleSettings.leapCaptureOnDiagonalLines,
          onDiagonalLinesChanged: (bool value) =>
              _setLeapCaptureOnDiagonalLines(ruleSettings, value),
          inPlacingPhase: ruleSettings.leapCaptureInPlacingPhase,
          onInPlacingPhaseChanged: (bool value) =>
              _setLeapCaptureInPlacingPhase(ruleSettings, value),
          inMovingPhase: ruleSettings.leapCaptureInMovingPhase,
          onInMovingPhaseChanged: (bool value) =>
              _setLeapCaptureInMovingPhase(ruleSettings, value),
          onlyWhenOwnPiecesLeq3: ruleSettings.leapCaptureOnlyWhenOwnPiecesLeq3,
          onOnlyWhenOwnPiecesLeq3Changed: (bool value) =>
              _setLeapCaptureOnlyWhenOwnPiecesLeq3(ruleSettings, value),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    visitedRuleSettingsPage = true;

    GameController().isControllerActive = false;
    GameController().reset();

    //GameController().engine.shutdown();

    return BlockSemantics(
      child: Scaffold(
        key: const Key('rule_settings_scaffold'),
        resizeToAvoidBottomInset: false,
        backgroundColor: AppTheme.lightBackgroundColor,
        appBar: AppBar(
          key: const Key('rule_settings_appbar'),
          leading: CustomDrawerIcon.of(context)?.drawerIcon,
          title: Text(
            S.of(context).ruleSettings,
            style: AppTheme.appBarTheme.titleTextStyle,
          ),
        ),
        body: ValueListenableBuilder<Box<RuleSettings>>(
          key: const Key('rule_settings_value_listenable_builder'),
          valueListenable: DB().listenRuleSettings,
          builder: _buildRuleSettings,
        ),
      ),
    );
  }
}
