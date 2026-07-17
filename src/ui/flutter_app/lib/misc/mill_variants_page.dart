// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/material.dart';
import 'package:hive_ce_flutter/hive_flutter.dart' show Box;

import '../games/mill/mill_variant_localization.dart';
import '../generated/intl/l10n.dart';
import '../puzzle/models/rule_variant.dart';
import '../rule_settings/models/rule_settings.dart';
import '../rule_settings/widgets/rule_settings_page.dart';
import '../shared/database/database.dart';
import '../shared/themes/app_styles.dart';
import '../shared/widgets/lichess_list_section.dart';
import '../shared/widgets/snackbars/scaffold_messenger.dart';
import 'mill_variant_popularity_map.dart';

class MillVariantsPage extends StatelessWidget {
  const MillVariantsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final S strings = S.of(context);

    return Scaffold(
      key: const Key('mill_variants_page_scaffold'),
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(title: Text(strings.variants)),
      body: ValueListenableBuilder<Box<RuleSettings>>(
        valueListenable: DB().listenRuleSettings,
        builder: (BuildContext context, Box<RuleSettings> box, Widget? child) {
          final RuleSettings currentSettings = DB().ruleSettings;
          final String? currentVariantId = RuleVariant.exactCanonicalIdFor(
            currentSettings,
          );
          final List<_VariantEntry> entries = _variantEntries(context);

          return ListView(
            key: const Key('mill_variants_page_list'),
            padding: const EdgeInsets.fromLTRB(0, 16, 0, 24),
            children: <Widget>[
              LichessListSection(
                cardKey: const Key('mill_variants_section_card'),
                children: <Widget>[
                  for (final _VariantEntry entry in entries)
                    _VariantTile(
                      key: Key('mill_variant_${entry.id}'),
                      entry: entry,
                      selected: entry.isCustom
                          ? currentVariantId == null
                          : entry.id == currentVariantId,
                      onTap: () => _openVariantDetails(context, entry),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  static List<_VariantEntry> _variantEntries(BuildContext context) {
    final S strings = S.of(context);
    const List<String> variantIds = <String>[
      'standard_9mm',
      'twelve_mens_morris',
      'morabaraba',
      'dooz',
      'lasker_morris',
      'russian_mill',
      'cham_gonu',
      'zhi_qi',
      'cheng_san_qi',
      'da_san_qi',
      'mul_mulan',
      'nerenchi',
      'el_filja',
    ];

    return <_VariantEntry>[
      _VariantEntry.custom(
        title: strings.custom,
        description: strings.customVariantDescription,
      ),
      ...variantIds.map((String variantId) {
        final RuleSettings settings = RuleVariant.canonicalSettings[variantId]!;
        assert(
          RuleVariant.exactCanonicalIdFor(settings) == variantId,
          'Canonical settings do not match $variantId.',
        );
        final List<String> features = _variantFeatures(strings, settings);
        return _VariantEntry(
          id: variantId,
          title: localizedMillVariantNameById(strings, variantId),
          description: features.join(' · '),
          features: features,
          settings: settings,
        );
      }),
    ];
  }

  static List<String> _variantFeatures(S strings, RuleSettings settings) {
    final List<String> features = <String>[
      strings.variantPieces(settings.piecesCount),
    ];

    if (settings.hasDiagonalLines) {
      features.add(strings.variantDiagonalLines);
    }
    if (settings.mayMoveInPlacingPhase) {
      features.add(strings.variantPlacingPhaseMovement);
    }
    if (settings.mayFly && settings.flyPieceCount < settings.piecesCount) {
      features.add(strings.variantFlyingAt(settings.flyPieceCount));
    }
    if (settings.oneTimeUseMill) {
      features.add(strings.variantOneTimeMillRule);
    }
    if (settings.enableInterventionCapture ||
        settings.enableCustodianCapture ||
        settings.enableLeapCapture) {
      features.add(strings.variantSpecialCapture);
    }
    if (settings.millFormationActionInPlacingPhase ==
        MillFormationActionInPlacingPhase.markAndDelayRemovingPieces) {
      features.add(strings.variantDelayedCapture);
    }
    return features;
  }

  void _openVariantDetails(BuildContext context, _VariantEntry entry) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => entry.isCustom
            ? const _CustomMillVariantDetailsPage()
            : _MillVariantDetailsPage(entry: entry),
      ),
    );
  }

  static void _applyVariant(
    BuildContext context,
    _VariantEntry entry, {
    bool closeRoute = false,
  }) {
    assert(!entry.isCustom, 'Custom rules cannot be applied as a preset.');
    if (RuleVariant.exactCanonicalIdFor(DB().ruleSettings) == entry.id) {
      return;
    }

    DB().ruleSettings = entry.settings!;
    ScaffoldMessenger.of(
      context,
    ).showSnackBarClear(S.of(context).variantApplied(entry.title));
    if (closeRoute) {
      Navigator.of(context).pop();
    }
  }
}

class _MillVariantDetailsPage extends StatelessWidget {
  const _MillVariantDetailsPage({required this.entry});

  final _VariantEntry entry;

  @override
  Widget build(BuildContext context) {
    final S strings = S.of(context);

    return Scaffold(
      key: Key('mill_variant_detail_${entry.id}'),
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(title: Text(entry.title)),
      body: ValueListenableBuilder<Box<RuleSettings>>(
        valueListenable: DB().listenRuleSettings,
        builder: (BuildContext context, Box<RuleSettings> box, Widget? child) {
          final bool selected =
              RuleVariant.exactCanonicalIdFor(DB().ruleSettings) == entry.id;

          return ListView(
            padding: const EdgeInsets.fromLTRB(0, 16, 0, 24),
            children: <Widget>[
              LichessListSection(
                header: Text(strings.rules),
                cardKey: Key('mill_variant_detail_rules_${entry.id}'),
                children: <Widget>[
                  for (final String feature in entry.features)
                    ListTile(title: Text(feature)),
                ],
              ),
              _VariantPopularitySection(entry: entry),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: FilledButton.icon(
                  key: const Key('mill_variant_detail_apply_button'),
                  onPressed: selected
                      ? null
                      : () => MillVariantsPage._applyVariant(
                          context,
                          entry,
                          closeRoute: true,
                        ),
                  icon: Icon(
                    selected ? Icons.check_rounded : Icons.play_arrow_rounded,
                  ),
                  label: Text(selected ? strings.selected : strings.useVariant),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _VariantPopularitySection extends StatelessWidget {
  const _VariantPopularitySection({required this.entry});

  final _VariantEntry entry;

  @override
  Widget build(BuildContext context) {
    return LichessListSection(
      cardKey: Key('mill_variant_detail_popularity_${entry.id}'),
      hasLeading: false,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.all(16),
          child: MillVariantPopularityMap(
            key: Key('mill_variant_popularity_map_${entry.id}'),
            variantId: entry.id,
            semanticsLabel: entry.title,
          ),
        ),
      ],
    );
  }
}
class _CustomMillVariantDetailsPage extends StatelessWidget {
  const _CustomMillVariantDetailsPage();

  @override
  Widget build(BuildContext context) {
    final S strings = S.of(context);

    return Scaffold(
      key: const Key('mill_variant_detail_custom'),
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(title: Text(strings.custom)),
      body: ValueListenableBuilder<Box<RuleSettings>>(
        valueListenable: DB().listenRuleSettings,
        builder: (BuildContext context, Box<RuleSettings> box, Widget? child) {
          final RuleSettings currentSettings = DB().ruleSettings;
          final String closestId = RuleVariant.closestCanonicalIdFor(
            currentSettings,
          );
          final RuleSettings closestSettings =
              RuleVariant.canonicalSettings[closestId]!;
          final String closestName = localizedMillVariantNameById(
            strings,
            closestId,
          );
          final List<String> differingKeys =
              RuleVariant.differingCanonicalSettingKeys(
                currentSettings,
                closestId,
              );
          final Map<String, dynamic> currentJson = currentSettings.toJson();
          final Map<String, dynamic> closestJson = closestSettings.toJson();

          return ListView(
            padding: const EdgeInsets.fromLTRB(0, 16, 0, 24),
            children: <Widget>[
              LichessListSection(
                header: Text(strings.customVariantClosestPreset),
                cardKey: const Key('mill_variant_custom_closest_preset_card'),
                children: <Widget>[
                  ListTile(
                    title: Text(closestName),
                    subtitle: Text(
                      strings.customVariantDifferenceCount(
                        differingKeys.length,
                      ),
                    ),
                  ),
                ],
              ),
              if (differingKeys.isNotEmpty)
                LichessListSection(
                  header: Text(
                    strings.customVariantDifferencesFromPreset(closestName),
                  ),
                  cardKey: const Key('mill_variant_custom_differences_card'),
                  children: <Widget>[
                    for (final String key in differingKeys)
                      _CustomRuleDifferenceTile(
                        label: _ruleSettingLabel(strings, key),
                        currentValue: _ruleSettingValue(
                          strings,
                          key,
                          currentJson[key],
                        ),
                        presetName: closestName,
                        presetValue: _ruleSettingValue(
                          strings,
                          key,
                          closestJson[key],
                        ),
                      ),
                  ],
                ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: FilledButton.icon(
                  key: const Key('mill_variant_custom_customize_button'),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (BuildContext context) =>
                          const RuleSettingsPage(),
                    ),
                  ),
                  icon: const Icon(Icons.tune_rounded),
                  label: Text(strings.customVariantCustomizeRules),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  static String _ruleSettingLabel(S strings, String key) {
    return switch (key) {
      'PiecesCount' => strings.piecesCount,
      'FlyPieceCount' => strings.flyPieceCount,
      'PiecesAtLeastCount' => strings.piecesAtLeastCount,
      'HasDiagonalLines' => strings.hasDiagonalLines,
      'HasBannedLocations' => strings.customVariantLegacyBannedLocations,
      'MayMoveInPlacingPhase' => strings.mayMoveInPlacingPhase,
      'IsDefenderMoveFirst' => strings.isDefenderMoveFirst,
      'MayRemoveMultiple' => strings.mayRemoveMultiple,
      'MayRemoveFromMillsAlways' => strings.mayRemoveFromMillsAlways,
      'MayOnlyRemoveUnplacedPieceInPlacingPhase' =>
        strings.customVariantLegacyHandRemoval,
      'IsWhiteLoseButNotDrawWhenBoardFull' =>
        strings.customVariantLegacyBoardFullResult,
      'IsLoseButNotChangeSideWhenNoWay' =>
        strings.customVariantLegacyBlockedPlayerResult,
      'MayFly' => strings.allowFlying,
      'NMoveRule' => strings.nMoveRule,
      'EndgameNMoveRule' => strings.endgameNMoveRule,
      'ThreefoldRepetitionRule' => strings.threefoldRepetitionRule,
      'BoardFullAction' => strings.whenBoardIsFull,
      'StalemateAction' => strings.whenStalemate,
      'MillFormationActionInPlacingPhase' =>
        strings.whenFormingMillsDuringPlacingPhase,
      'RestrictRepeatedMillsFormation' =>
        strings.restrictRepeatedMillsFormation,
      'OneTimeUseMill' => strings.oneTimeMill,
      'EnableCustodianCapture' => strings.custodianCaptureEnable,
      'CustodianCaptureOnSquareEdges' => _captureOptionLabel(
        strings,
        strings.custodianCapture,
        strings.captureSquareEdges,
      ),
      'CustodianCaptureOnCrossLines' => _captureOptionLabel(
        strings,
        strings.custodianCapture,
        strings.captureCrossLines,
      ),
      'CustodianCaptureOnDiagonalLines' => _captureOptionLabel(
        strings,
        strings.custodianCapture,
        strings.captureDiagonalLines,
      ),
      'CustodianCaptureInPlacingPhase' => _captureOptionLabel(
        strings,
        strings.custodianCapture,
        strings.placingPhase,
      ),
      'CustodianCaptureInMovingPhase' => _captureOptionLabel(
        strings,
        strings.custodianCapture,
        strings.movingPhase,
      ),
      'CustodianCaptureOnlyWhenOwnPiecesLeq3' => _captureOptionLabel(
        strings,
        strings.custodianCapture,
        strings.capturePiecesCondition,
      ),
      'EnableInterventionCapture' => strings.interventionCaptureEnable,
      'InterventionCaptureOnSquareEdges' => _captureOptionLabel(
        strings,
        strings.interventionCapture,
        strings.captureSquareEdges,
      ),
      'InterventionCaptureOnCrossLines' => _captureOptionLabel(
        strings,
        strings.interventionCapture,
        strings.captureCrossLines,
      ),
      'InterventionCaptureOnDiagonalLines' => _captureOptionLabel(
        strings,
        strings.interventionCapture,
        strings.captureDiagonalLines,
      ),
      'InterventionCaptureInPlacingPhase' => _captureOptionLabel(
        strings,
        strings.interventionCapture,
        strings.placingPhase,
      ),
      'InterventionCaptureInMovingPhase' => _captureOptionLabel(
        strings,
        strings.interventionCapture,
        strings.movingPhase,
      ),
      'InterventionCaptureOnlyWhenOwnPiecesLeq3' => _captureOptionLabel(
        strings,
        strings.interventionCapture,
        strings.capturePiecesCondition,
      ),
      'EnableLeapCapture' => strings.leapCaptureEnable,
      'LeapCaptureOnSquareEdges' => _captureOptionLabel(
        strings,
        strings.leapCapture,
        strings.captureSquareEdges,
      ),
      'LeapCaptureOnCrossLines' => _captureOptionLabel(
        strings,
        strings.leapCapture,
        strings.captureCrossLines,
      ),
      'LeapCaptureOnDiagonalLines' => _captureOptionLabel(
        strings,
        strings.leapCapture,
        strings.captureDiagonalLines,
      ),
      'LeapCaptureInPlacingPhase' => _captureOptionLabel(
        strings,
        strings.leapCapture,
        strings.placingPhase,
      ),
      'LeapCaptureInMovingPhase' => _captureOptionLabel(
        strings,
        strings.leapCapture,
        strings.movingPhase,
      ),
      'LeapCaptureOnlyWhenOwnPiecesLeq3' => _captureOptionLabel(
        strings,
        strings.leapCapture,
        strings.capturePiecesCondition,
      ),
      'StopPlacingWhenTwoEmptySquares' =>
        strings.stopPlacingWhenTwoEmptySquares,
      _ => strings.customVariantOtherRule(key),
    };
  }

  static String _captureOptionLabel(S strings, String capture, String option) {
    return strings.customVariantCaptureOption(capture, option);
  }

  static String _ruleSettingValue(S strings, String key, Object? value) {
    return switch (key) {
      'BoardFullAction' => _boardFullActionValue(strings, value),
      'StalemateAction' => _stalemateActionValue(strings, value),
      'MillFormationActionInPlacingPhase' => _millFormationActionValue(
        strings,
        value,
      ),
      'CustodianCaptureOnlyWhenOwnPiecesLeq3' ||
      'InterventionCaptureOnlyWhenOwnPiecesLeq3' ||
      'LeapCaptureOnlyWhenOwnPiecesLeq3' => _captureAvailabilityValue(
        strings,
        value,
      ),
      _ when value is bool => value ? strings.yes : strings.no,
      _ => value?.toString() ?? strings.none,
    };
  }

  static String _boardFullActionValue(S strings, Object? value) {
    return switch (value) {
      'firstPlayerLose' => strings.firstPlayerLose,
      'firstAndSecondPlayerRemovePiece' =>
        strings.firstAndSecondPlayerRemovePiece,
      'secondAndFirstPlayerRemovePiece' =>
        strings.secondAndFirstPlayerRemovePiece,
      'sideToMoveRemovePiece' => strings.sideToMoveRemovePiece,
      'agreeToDraw' => strings.agreeToDraw,
      _ => value?.toString() ?? strings.none,
    };
  }

  static String _stalemateActionValue(S strings, Object? value) {
    return switch (value) {
      'endWithStalemateLoss' => strings.endWithStalemateLoss,
      'changeSideToMove' => strings.changeSideToMove,
      'removeOpponentsPieceAndMakeNextMove' =>
        strings.removeOpponentsPieceAndMakeNextMove,
      'removeOpponentsPieceAndChangeSideToMove' =>
        strings.removeOpponentsPieceAndChangeSideToMove,
      'endWithStalemateDraw' => strings.endWithStalemateDraw,
      'bothPlayersRemoveOpponentsPiece' =>
        strings.bothPlayersRemoveOpponentsPiece,
      _ => value?.toString() ?? strings.none,
    };
  }

  static String _millFormationActionValue(S strings, Object? value) {
    return switch (value) {
      'removeOpponentsPieceFromBoard' => strings.removeOpponentsPieceFromBoard,
      'removeOpponentsPieceFromHandThenOpponentsTurn' =>
        strings.removeOpponentsPieceFromHandThenOpponentsTurn,
      'removeOpponentsPieceFromHandThenYourTurn' =>
        strings.removeOpponentsPieceFromHandThenYourTurn,
      'opponentRemovesOwnPiece' => strings.opponentRemovesOwnPiece,
      'markAndDelayRemovingPieces' => strings.markAndDelayRemovingPieces,
      'removalBasedOnMillCounts' => strings.removalBasedOnMillCounts,
      _ => value?.toString() ?? strings.none,
    };
  }

  static String _captureAvailabilityValue(S strings, Object? value) {
    return switch (value) {
      true => strings.capturePiecesConditionSelfLeqThree,
      false => strings.capturePiecesConditionUnlimited,
      _ => strings.none,
    };
  }
}

class _CustomRuleDifferenceTile extends StatelessWidget {
  const _CustomRuleDifferenceTile({
    required this.label,
    required this.currentValue,
    required this.presetName,
    required this.presetValue,
  });

  final String label;
  final String currentValue;
  final String presetName;
  final String presetValue;

  @override
  Widget build(BuildContext context) {
    final S strings = S.of(context);
    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: AppStyles.tileTitle.copyWith(color: colorScheme.onSurface),
          ),
          const SizedBox(height: 4),
          Text(
            strings.customVariantCurrentValue(currentValue),
            style: AppStyles.tileSubtitle.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          Text(
            strings.customVariantPresetValue(presetName, presetValue),
            style: AppStyles.tileSubtitle.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _VariantTile extends StatelessWidget {
  const _VariantTile({
    super.key,
    required this.entry,
    required this.selected,
    required this.onTap,
  });

  final _VariantEntry entry;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final TextStyle titleStyle = AppStyles.tileTitle.copyWith(
      color: selected ? colorScheme.primary : colorScheme.onSurface,
      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
    );

    return ListTile(
      selected: selected,
      selectedTileColor: colorScheme.primaryContainer.withValues(alpha: 0.36),
      contentPadding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 8),
      title: Text(entry.title, style: titleStyle),
      subtitle: Text(
        entry.description,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: AppStyles.tileSubtitle.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: selected
          ? Icon(Icons.check_rounded, color: colorScheme.primary)
          : Icon(
              entry.isCustom ? Icons.tune_rounded : Icons.chevron_right_rounded,
              color: colorScheme.outline,
            ),
      onTap: onTap,
    );
  }
}

class _VariantEntry {
  const _VariantEntry({
    required this.id,
    required this.title,
    required this.description,
    required this.features,
    required this.settings,
  }) : isCustom = false;

  const _VariantEntry.custom({required this.title, required this.description})
    : id = 'custom',
      features = const <String>[],
      settings = null,
      isCustom = true;

  final String id;
  final String title;
  final String description;
  final List<String> features;
  final RuleSettings? settings;
  final bool isCustom;
}
