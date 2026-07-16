// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import '../../generated/intl/l10n.dart';
import '../../puzzle/models/rule_variant.dart';
import '../../rule_settings/models/rule_settings.dart';

/// Returns the localized display name for a Mill rule configuration.
String localizedMillVariantName(S strings, RuleSettings settings) {
  final String variantId = RuleVariant.fromRuleSettings(settings).id;
  return localizedMillVariantNameById(strings, variantId);
}

/// Returns the localized display name for a stable Mill variant identifier.
String localizedMillVariantNameById(S strings, String variantId) {
  if (variantId.startsWith('custom_')) {
    return strings.custom;
  }

  return switch (variantId) {
    'standard_9mm' => strings.nineMensMorris,
    'twelve_mens_morris' => strings.twelveMensMorris,
    'morabaraba' => strings.morabaraba,
    'dooz' => strings.dooz,
    'lasker_morris' => strings.laskerMorris,
    'russian_mill' => strings.oneTimeMill,
    'cham_gonu' => strings.chamGonu,
    'zhi_qi' => strings.zhiQi,
    'cheng_san_qi' => strings.chengSanQi,
    'da_san_qi' => strings.daSanQi,
    'mul_mulan' => strings.mulMulan,
    'nerenchi' => strings.nerenchi,
    'el_filja' => strings.elfilja,
    _ => throw StateError('Unsupported Mill variant: $variantId'),
  };
}
