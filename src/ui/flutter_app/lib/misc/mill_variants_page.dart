// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/material.dart';
import 'package:hive_ce_flutter/hive_flutter.dart' show Box;

import '../games/mill/mill_variant_localization.dart';
import '../generated/intl/l10n.dart';
import '../puzzle/models/rule_variant.dart';
import '../rule_settings/models/rule_settings.dart';
import '../shared/database/database.dart';
import '../shared/themes/app_styles.dart';
import '../shared/widgets/lichess_list_section.dart';
import '../shared/widgets/snackbars/scaffold_messenger.dart';

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
          final RuleVariant currentVariant = RuleVariant.fromRuleSettings(
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
                      selected: entry.id == currentVariant.id,
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

    return variantIds
        .map((String variantId) {
          final RuleSettings? settings =
              RuleVariant.canonicalSettings[variantId];
          assert(
            settings != null,
            'Missing canonical settings for $variantId.',
          );
          final RuleVariant variant = RuleVariant.fromRuleSettings(settings!);
          assert(
            variant.id == variantId,
            'Variant id mismatch: expected $variantId, got ${variant.id}.',
          );
          return _VariantEntry(
            id: variantId,
            title: localizedMillVariantNameById(strings, variantId),
            features: _variantFeatures(strings, settings),
            settings: settings,
          );
        })
        .toList(growable: false);
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
        builder: (BuildContext context) =>
            _MillVariantDetailsPage(entry: entry),
      ),
    );
  }

  static void _applyVariant(
    BuildContext context,
    _VariantEntry entry, {
    bool closeRoute = false,
  }) {
    final RuleVariant currentVariant = RuleVariant.fromRuleSettings(
      DB().ruleSettings,
    );
    if (currentVariant.id == entry.id) {
      return;
    }

    DB().ruleSettings = entry.settings;
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
          final RuleVariant currentVariant = RuleVariant.fromRuleSettings(
            DB().ruleSettings,
          );
          final bool selected = currentVariant.id == entry.id;

          return ListView(
            padding: const EdgeInsets.fromLTRB(0, 16, 0, 24),
            children: <Widget>[
              _VariantDetailsHeader(
                key: Key('mill_variant_detail_header_${entry.id}'),
                entry: entry,
                selected: selected,
              ),
              LichessListSection(
                header: Text(strings.rules),
                cardKey: Key('mill_variant_detail_rules_${entry.id}'),
                children: <Widget>[
                  for (final String feature in entry.features)
                    ListTile(title: Text(feature)),
                ],
              ),
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

class _VariantDetailsHeader extends StatelessWidget {
  const _VariantDetailsHeader({
    super.key,
    required this.entry,
    required this.selected,
  });

  final _VariantEntry entry;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final TextTheme textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  entry.title,
                  style: textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (selected)
                Icon(Icons.check_rounded, color: colorScheme.primary),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            entry.description,
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
          : Icon(Icons.chevron_right_rounded, color: colorScheme.outline),
      onTap: onTap,
    );
  }
}

class _VariantEntry {
  const _VariantEntry({
    required this.id,
    required this.title,
    required this.features,
    required this.settings,
  });

  final String id;
  final String title;
  final List<String> features;
  final RuleSettings settings;

  String get description => features.join(' · ');
}
