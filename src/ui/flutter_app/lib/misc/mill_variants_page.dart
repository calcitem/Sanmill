// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/material.dart';
import 'package:hive_ce_flutter/hive_flutter.dart' show Box;

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
          final List<_VariantGroup> groups = _variantGroups(context, entries);

          return ListView(
            key: const Key('mill_variants_page_list'),
            padding: const EdgeInsets.fromLTRB(0, 16, 0, 24),
            children: <Widget>[
              for (int index = 0; index < groups.length; index++)
                LichessListSection(
                  header: Text(groups[index].title),
                  headerKey: Key('mill_variants_${groups[index].id}_header'),
                  cardKey: index == 0
                      ? const Key('mill_variants_section_card')
                      : Key('mill_variants_${groups[index].id}_section_card'),
                  children: <Widget>[
                    for (final _VariantEntry entry in groups[index].entries)
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
    const List<_VariantSource> sources = <_VariantSource>[
      _VariantSource(
        id: 'standard_9mm',
        titleKey: _VariantTitleKey.nineMensMorris,
      ),
      _VariantSource(
        id: 'twelve_mens_morris',
        titleKey: _VariantTitleKey.twelveMensMorris,
      ),
      _VariantSource(id: 'morabaraba', titleKey: _VariantTitleKey.morabaraba),
      _VariantSource(id: 'dooz', titleKey: _VariantTitleKey.dooz),
      _VariantSource(
        id: 'lasker_morris',
        titleKey: _VariantTitleKey.laskerMorris,
      ),
      _VariantSource(
        id: 'russian_mill',
        titleKey: _VariantTitleKey.oneTimeMill,
      ),
      _VariantSource(id: 'cham_gonu', titleKey: _VariantTitleKey.chamGonu),
      _VariantSource(id: 'zhi_qi', titleKey: _VariantTitleKey.zhiQi),
      _VariantSource(id: 'cheng_san_qi', titleKey: _VariantTitleKey.chengSanQi),
      _VariantSource(id: 'da_san_qi', titleKey: _VariantTitleKey.daSanQi),
      _VariantSource(id: 'mul_mulan', titleKey: _VariantTitleKey.mulMulan),
      _VariantSource(id: 'nerenchi', titleKey: _VariantTitleKey.nerenchi),
      _VariantSource(id: 'el_filja', titleKey: _VariantTitleKey.elfilja),
    ];

    return sources
        .map((_VariantSource source) {
          final RuleSettings? settings =
              RuleVariant.canonicalSettings[source.id];
          assert(
            settings != null,
            'Missing canonical settings for ${source.id}.',
          );
          final RuleVariant variant = RuleVariant.fromRuleSettings(settings!);
          assert(
            variant.id == source.id,
            'Variant id mismatch: expected ${source.id}, got ${variant.id}.',
          );
          return _VariantEntry(
            id: source.id,
            title: _localizedVariantTitle(strings, source.titleKey),
            features: _variantFeatures(strings, settings),
            settings: settings,
          );
        })
        .toList(growable: false);
  }

  static List<_VariantGroup> _variantGroups(
    BuildContext context,
    List<_VariantEntry> entries,
  ) {
    final S strings = S.of(context);
    final List<_VariantEntry> mainline = entries
        .where(
          (_VariantEntry entry) =>
              entry.id == 'standard_9mm' ||
              entry.id == 'twelve_mens_morris' ||
              entry.id == 'morabaraba' ||
              entry.id == 'dooz',
        )
        .toList(growable: false);
    final List<_VariantEntry> capture = entries
        .where(
          (_VariantEntry entry) =>
              _hasSpecialCapture(entry.settings) &&
              !mainline.any((_VariantEntry main) => main.id == entry.id),
        )
        .toList(growable: false);
    final List<_VariantEntry> rules = entries
        .where(
          (_VariantEntry entry) =>
              !mainline.any((_VariantEntry main) => main.id == entry.id) &&
              !capture.any((_VariantEntry capture) => capture.id == entry.id),
        )
        .toList(growable: false);
    final Set<String> groupedIds = <String>{
      for (final _VariantEntry entry in mainline) entry.id,
      for (final _VariantEntry entry in capture) entry.id,
      for (final _VariantEntry entry in rules) entry.id,
    };
    assert(
      groupedIds.length == entries.length,
      'Every Mill variant must appear in exactly one group.',
    );

    return <_VariantGroup>[
          _VariantGroup(
            id: 'mainline',
            title: strings.millGame,
            entries: mainline,
          ),
          _VariantGroup(
            id: 'capture',
            title: strings.puzzleCategoryCapturePieces,
            entries: capture,
          ),
          _VariantGroup(id: 'rules', title: strings.rules, entries: rules),
        ]
        .where((_VariantGroup group) => group.entries.isNotEmpty)
        .toList(growable: false);
  }

  static bool _hasSpecialCapture(RuleSettings settings) {
    return settings.enableInterventionCapture ||
        settings.enableCustodianCapture ||
        settings.enableLeapCapture ||
        settings.millFormationActionInPlacingPhase ==
            MillFormationActionInPlacingPhase.markAndDelayRemovingPieces;
  }

  static String _localizedVariantTitle(S strings, _VariantTitleKey key) {
    switch (key) {
      case _VariantTitleKey.nineMensMorris:
        return strings.nineMensMorris;
      case _VariantTitleKey.twelveMensMorris:
        return strings.twelveMensMorris;
      case _VariantTitleKey.morabaraba:
        return strings.morabaraba;
      case _VariantTitleKey.dooz:
        return strings.dooz;
      case _VariantTitleKey.laskerMorris:
        return strings.laskerMorris;
      case _VariantTitleKey.oneTimeMill:
        return strings.oneTimeMill;
      case _VariantTitleKey.chamGonu:
        return strings.chamGonu;
      case _VariantTitleKey.zhiQi:
        return strings.zhiQi;
      case _VariantTitleKey.chengSanQi:
        return strings.chengSanQi;
      case _VariantTitleKey.daSanQi:
        return strings.daSanQi;
      case _VariantTitleKey.mulMulan:
        return strings.mulMulan;
      case _VariantTitleKey.nerenchi:
        return strings.nerenchi;
      case _VariantTitleKey.elfilja:
        return strings.elfilja;
    }
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
              _VariantDetailsHeader(entry: entry, selected: selected),
              LichessListSection(
                header: Text(strings.rules),
                cardKey: Key('mill_variant_detail_rules_${entry.id}'),
                children: <Widget>[
                  for (final String feature in entry.features)
                    ListTile(
                      leading: const Icon(Icons.check_circle_outline_rounded),
                      title: Text(feature),
                    ),
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
  const _VariantDetailsHeader({required this.entry, required this.selected});

  final _VariantEntry entry;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final TextTheme textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox.square(
            dimension: 44,
            child: Icon(
              Icons.category_outlined,
              size: 32,
              color: colorScheme.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
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
      leading: Icon(
        entry.icon,
        color: selected ? colorScheme.primary : colorScheme.onSurfaceVariant,
      ),
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

  IconData get icon {
    if (id == 'standard_9mm') {
      return Icons.grid_3x3_rounded;
    }
    if (settings.hasDiagonalLines) {
      return Icons.hub_outlined;
    }
    if (MillVariantsPage._hasSpecialCapture(settings)) {
      return Icons.control_camera_outlined;
    }
    if (settings.mayMoveInPlacingPhase || settings.mayFly) {
      return Icons.alt_route_rounded;
    }
    return Icons.category_outlined;
  }
}

class _VariantGroup {
  const _VariantGroup({
    required this.id,
    required this.title,
    required this.entries,
  });

  final String id;
  final String title;
  final List<_VariantEntry> entries;
}

class _VariantSource {
  const _VariantSource({required this.id, required this.titleKey});

  final String id;
  final _VariantTitleKey titleKey;
}

enum _VariantTitleKey {
  nineMensMorris,
  twelveMensMorris,
  morabaraba,
  dooz,
  laskerMorris,
  oneTimeMill,
  chamGonu,
  zhiQi,
  chengSanQi,
  daSanQi,
  mulMulan,
  nerenchi,
  elfilja,
}
