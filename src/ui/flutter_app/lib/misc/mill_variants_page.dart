// SPDX-License-Identifier: GPL-3.0-or-later
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

          return ListView(
            key: const Key('mill_variants_page_list'),
            padding: const EdgeInsets.fromLTRB(0, 16, 0, 24),
            children: <Widget>[
              LichessListSection(
                header: Text(strings.millGame),
                cardKey: const Key('mill_variants_section_card'),
                children: <Widget>[
                  for (final _VariantEntry entry in entries)
                    _VariantTile(
                      key: Key('mill_variant_${entry.id}'),
                      entry: entry,
                      selected: entry.id == currentVariant.id,
                      onTap: () => _applyVariant(context, entry),
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
            description: _variantDescription(strings, settings),
            settings: settings,
          );
        })
        .toList(growable: false);
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

  static String _variantDescription(S strings, RuleSettings settings) {
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

    return features.join(' · ');
  }

  void _applyVariant(BuildContext context, _VariantEntry entry) {
    final RuleVariant currentVariant = RuleVariant.fromRuleSettings(
      DB().ruleSettings,
    );
    if (currentVariant.id == entry.id) {
      Navigator.of(context).maybePop();
      return;
    }

    DB().ruleSettings = entry.settings;
    ScaffoldMessenger.of(
      context,
    ).showSnackBarClear(S.of(context).variantApplied(entry.title));
    Navigator.of(context).maybePop();
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

    return ListTile(
      leading: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
        color: selected ? colorScheme.primary : colorScheme.onSurfaceVariant,
      ),
      title: Text(entry.title),
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
          : null,
      onTap: onTap,
    );
  }
}

class _VariantEntry {
  const _VariantEntry({
    required this.id,
    required this.title,
    required this.description,
    required this.settings,
  });

  final String id;
  final String title;
  final String description;
  final RuleSettings settings;
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
