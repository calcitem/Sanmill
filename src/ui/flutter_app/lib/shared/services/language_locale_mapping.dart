// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// language_locale_mapping.dart

import 'dart:ui';

import '../../game_page/services/mill.dart';
import '../../generated/intl/l10n_af.dart';
import '../../generated/intl/l10n_am.dart';
import '../../generated/intl/l10n_ar.dart';
import '../../generated/intl/l10n_az.dart';
import '../../generated/intl/l10n_be.dart';
import '../../generated/intl/l10n_bg.dart';
import '../../generated/intl/l10n_bn.dart';
import '../../generated/intl/l10n_bs.dart';
import '../../generated/intl/l10n_ca.dart';
import '../../generated/intl/l10n_cs.dart';
import '../../generated/intl/l10n_da.dart';
import '../../generated/intl/l10n_de.dart';
import '../../generated/intl/l10n_el.dart';
import '../../generated/intl/l10n_en.dart';
import '../../generated/intl/l10n_es.dart';
import '../../generated/intl/l10n_et.dart';
import '../../generated/intl/l10n_fa.dart';
import '../../generated/intl/l10n_fi.dart';
import '../../generated/intl/l10n_fr.dart';
import '../../generated/intl/l10n_gu.dart';
import '../../generated/intl/l10n_he.dart';
import '../../generated/intl/l10n_hi.dart';
import '../../generated/intl/l10n_hr.dart';
import '../../generated/intl/l10n_hu.dart';
import '../../generated/intl/l10n_hy.dart';
import '../../generated/intl/l10n_id.dart';
import '../../generated/intl/l10n_is.dart';
import '../../generated/intl/l10n_it.dart';
import '../../generated/intl/l10n_ja.dart';
import '../../generated/intl/l10n_km.dart';
import '../../generated/intl/l10n_kn.dart';
import '../../generated/intl/l10n_ko.dart';
import '../../generated/intl/l10n_lt.dart';
import '../../generated/intl/l10n_lv.dart';
import '../../generated/intl/l10n_mk.dart';
import '../../generated/intl/l10n_ms.dart';
import '../../generated/intl/l10n_my.dart';
import '../../generated/intl/l10n_nb.dart';
import '../../generated/intl/l10n_nl.dart';
import '../../generated/intl/l10n_pl.dart';
import '../../generated/intl/l10n_pt.dart';
import '../../generated/intl/l10n_ro.dart';
import '../../generated/intl/l10n_ru.dart';
import '../../generated/intl/l10n_si.dart';
import '../../generated/intl/l10n_sk.dart';
import '../../generated/intl/l10n_sl.dart';
import '../../generated/intl/l10n_sq.dart';
import '../../generated/intl/l10n_sr.dart';
import '../../generated/intl/l10n_sv.dart';
import '../../generated/intl/l10n_sw.dart';
import '../../generated/intl/l10n_ta.dart';
import '../../generated/intl/l10n_te.dart';
import '../../generated/intl/l10n_th.dart';
import '../../generated/intl/l10n_tr.dart';
import '../../generated/intl/l10n_uk.dart';
import '../../generated/intl/l10n_ur.dart';
import '../../generated/intl/l10n_uz.dart';
import '../../generated/intl/l10n_vi.dart';
import '../../generated/intl/l10n_zh.dart';
import '../../generated/intl/l10n_zu.dart';
import '../database/database.dart';

Map<Locale, String> localeToLanguageName = <Locale, String>{
  const Locale("af"): SAf().languageName, // Afrikaans
  const Locale("am"): SAm().languageName, // Amharic
  const Locale("ar"): SAr().languageName, // Arabic
  const Locale("az"): SAz().languageName, // Azerbaijani
  const Locale("be"): SBe().languageName, // Belarusian
  const Locale("bg"): SBg().languageName, // Bulgarian
  const Locale("bn"): SBn().languageName, // Bengali
  const Locale("bs"): SBs().languageName, // Bosnian
  const Locale("ca"): SCa().languageName, // Catalan
  const Locale("cs"): SCs().languageName, // Czech
  const Locale("da"): SDa().languageName, // Danish
  const Locale("de"): SDe().languageName, // German
  const Locale("de", "CH"): SDeCh().languageName, // Swiss German
  const Locale("el"): SEl().languageName, // Greek
  const Locale("en"): SEn().languageName, // English
  const Locale("es"): SEs().languageName, // Spanish
  const Locale("et"): SEt().languageName, // Estonian
  const Locale("fa"): SFa().languageName, // Persian (Farsi)
  const Locale("fi"): SFi().languageName, // Finnish
  const Locale("fr"): SFr().languageName, // French
  const Locale("gu"): SGu().languageName, // Gujarati
  const Locale("he"): SHe().languageName, // Hebrew
  const Locale("hi"): SHi().languageName, // Hindi
  const Locale("hr"): SHr().languageName, // Croatian
  const Locale("hu"): SHu().languageName, // Hungarian
  const Locale("hy"): SHy().languageName, // Armenian
  const Locale("id"): SId().languageName, // Indonesian
  const Locale("is"): SIs().languageName, // Icelandic
  const Locale("it"): SIt().languageName, // Italian
  const Locale("ja"): SJa().languageName, // Japanese
  const Locale("km"): SKm().languageName, // Khmer
  const Locale("kn"): SKn().languageName, // Kannada
  const Locale("ko"): SKo().languageName, // Korean
  const Locale("lt"): SLt().languageName, // Lithuanian
  const Locale("lv"): SLv().languageName, // Latvian
  const Locale("mk"): SMk().languageName, // Macedonian
  const Locale("ms"): SMs().languageName, // Malay
  const Locale("my"): SMy().languageName, // Burmese
  const Locale("nl"): SNl().languageName, // Dutch
  const Locale("nb"): SNb().languageName, // Norwegian
  const Locale("pl"): SPl().languageName, // Polish
  const Locale("pt"): SPt().languageName, // Portuguese
  const Locale("ro"): SRo().languageName, // Romanian
  const Locale("ru"): SRu().languageName, // Russian
  const Locale("si"): SSi().languageName, // Sinhala
  const Locale("sk"): SSk().languageName, // Slovak
  const Locale("sl"): SSl().languageName, // Slovenian
  const Locale("sq"): SSq().languageName, // Albanian
  const Locale("sr"): SSr().languageName, // Serbian
  const Locale("sv"): SSv().languageName, // Swedish
  const Locale("sw"): SSw().languageName, // Swahili
  const Locale("ta"): STa().languageName, // Tamil
  const Locale("te"): STe().languageName, // Telugu
  const Locale("th"): STh().languageName, // Thai
  const Locale("tr"): STr().languageName, // Turkish
  const Locale("uk"): SUk().languageName, // Ukrainian
  const Locale("ur"): SUr().languageName, // Urdu
  const Locale("uz"): SUz().languageName, // Uzbek
  const Locale("vi"): SVi().languageName, // Vietnamese
  const Locale("zh"): SZh().languageName, // Chinese (Simplified)
  const Locale.fromSubtags(languageCode: "zh", scriptCode: "Hant"):
      SZhHant().languageName, // Chinese (Traditional),
  const Locale("zu"): SZu().languageName, // Zulu
};

/// Get the effective locale, considering system default when app locale is null
Locale getEffectiveLocale() {
  final Locale? appLocale = DB().displaySettings.locale;
  if (appLocale != null) {
    return appLocale;
  }

  // App is set to follow system, get system locale
  try {
    return PlatformDispatcher.instance.locale;
  } catch (e) {
    // Fallback to English if system locale is not available
    return const Locale('en');
  }
}

/// Check if the current locale should display Chinese names for Zhuolu Chess pieces
/// Returns true for Chinese, Japanese, and Korean locales
/// Handles both app-set locale and system default locale
bool shouldUseChinese(Locale locale) {
  final String languageCode = locale.languageCode.toLowerCase();

  // Chinese locales (simplified and traditional)
  if (languageCode == 'zh') {
    return true;
  }

  // Japanese locale
  if (languageCode == 'ja') {
    return true;
  }

  // Korean locale
  if (languageCode == 'ko') {
    return true;
  }

  return false;
}

/// Check if should use Chinese names considering both app and system locale
bool shouldUseChineseForCurrentSetting() {
  final Locale effectiveLocale = getEffectiveLocale();
  return shouldUseChinese(effectiveLocale);
}

/// Generate a tip message for Zhuolu Chess piece placement
/// Shows coordinates and piece ability description
String generateZhuoluPlacementTip(String notation, SpecialPiece? specialPiece) {
  final StringBuffer buffer = StringBuffer();

  // Add coordinates
  buffer.write('Placed at $notation');

  // Add special piece ability if applicable
  if (specialPiece != null) {
    if (shouldUseChineseForCurrentSetting()) {
      // Use Chinese names and descriptions
      final Map<SpecialPiece, String> chineseDescriptions =
          <SpecialPiece, String>{
        SpecialPiece.huangDi: '落子同化相邻敌子为己方',
        SpecialPiece.nuBa: '落子同化单体相邻敌子',
        SpecialPiece.yanDi: '落子提取所有相邻敌子',
        SpecialPiece.chiYou: '落子令相邻空位转弃位',
        SpecialPiece.changXian: '落子全图提取任意一子',
        SpecialPiece.xingTian: '落子相邻单体提取',
        SpecialPiece.zhuRong: '成三时额外提取一子',
        SpecialPiece.yuShi: '成三时将任意空位变弃位',
        SpecialPiece.fengHou: '可选择在弃位落子',
        SpecialPiece.gongGong: '仅能在弃位落子',
        SpecialPiece.nuWa: '落子令相邻弃位转己子',
        SpecialPiece.fuXi: '落子令任意弃位转己子',
        SpecialPiece.kuaFu: '不可被提取',
        SpecialPiece.yingLong: '相邻有己子时不可被提取',
        SpecialPiece.fengBo: '落子消灭任意一子，不留弃位',
      };

      buffer.write(
          ' - ${specialPiece.chineseName}: ${chineseDescriptions[specialPiece] ?? ''}');
    } else {
      // Use English names and descriptions
      final Map<SpecialPiece, String> englishDescriptions =
          <SpecialPiece, String>{
        SpecialPiece.huangDi: 'Converts adjacent opponent pieces',
        SpecialPiece.nuBa: 'Converts one adjacent opponent piece',
        SpecialPiece.yanDi: 'Removes all adjacent opponent pieces',
        SpecialPiece.chiYou: 'Converts adjacent empty squares to abandoned',
        SpecialPiece.changXian: 'Removes any opponent piece on board',
        SpecialPiece.xingTian: 'Removes one adjacent opponent piece',
        SpecialPiece.zhuRong: 'Extra removal when forming mill',
        SpecialPiece.yuShi:
            'Converts empty square to abandoned when forming mill',
        SpecialPiece.fengHou: 'Can be placed on abandoned squares',
        SpecialPiece.gongGong: 'Can ONLY be placed on abandoned squares',
        SpecialPiece.nuWa: 'Converts adjacent abandoned squares to own pieces',
        SpecialPiece.fuXi: 'Converts any abandoned square to own piece',
        SpecialPiece.kuaFu: 'Cannot be removed by opponent',
        SpecialPiece.yingLong: 'Cannot be removed when adjacent to own pieces',
        SpecialPiece.fengBo:
            'Destroys opponent piece without leaving abandoned square',
      };

      buffer.write(
          ' - ${specialPiece.emoji} ${specialPiece.englishName}: ${englishDescriptions[specialPiece] ?? ''}');
    }
  } else {
    // Normal piece
    if (shouldUseChineseForCurrentSetting()) {
      buffer.write(' - 普通棋子');
    } else {
      buffer.write(' - ⚫ Normal piece');
    }
  }

  return buffer.toString();
}
