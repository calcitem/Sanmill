// This file is part of Sanmill.
// Copyright (C) 2019-2024 The Sanmill developers (see AUTHORS file)
//
// Sanmill is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Sanmill is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

import 'package:flutter/material.dart';

import '../../generated/intl/l10n_af.dart';
import '../../generated/intl/l10n_ar.dart';
import '../../generated/intl/l10n_az.dart';
import '../../generated/intl/l10n_be.dart';
import '../../generated/intl/l10n_bg.dart';
import '../../generated/intl/l10n_bn.dart';
import '../../generated/intl/l10n_bs.dart';
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
import '../../generated/intl/l10n_te.dart';
import '../../generated/intl/l10n_th.dart';
import '../../generated/intl/l10n_tr.dart';
import '../../generated/intl/l10n_uk.dart';
import '../../generated/intl/l10n_ur.dart';
import '../../generated/intl/l10n_uz.dart';
import '../../generated/intl/l10n_vi.dart';
import '../../generated/intl/l10n_zh.dart';
import '../../generated/intl/l10n_zu.dart';

Map<Locale, String> localeToLanguageName = <Locale, String>{
  const Locale("af"): SAf().languageName, // Afrikaans
  const Locale("ar"): SAr().languageName, // Arabic
  const Locale("az"): SAz().languageName, // Azerbaijani
  const Locale("be"): SBe().languageName, // Belarusian
  const Locale("bg"): SBg().languageName, // Bulgarian
  const Locale("bn"): SBn().languageName, // Bengali
  const Locale("bs"): SBs().languageName, // Bosnian
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
