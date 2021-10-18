/*
  This file is part of Sanmill.
  Copyright (C) 2019-2021 The Sanmill developers (see AUTHORS file)

  Sanmill is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  Sanmill is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

import 'package:flutter/material.dart';
import 'package:sanmill/generated/intl/l10n_ar.dart';
import 'package:sanmill/generated/intl/l10n_bg.dart';
import 'package:sanmill/generated/intl/l10n_bn.dart';
import 'package:sanmill/generated/intl/l10n_cs.dart';
import 'package:sanmill/generated/intl/l10n_da.dart';
import 'package:sanmill/generated/intl/l10n_de.dart';
import 'package:sanmill/generated/intl/l10n_el.dart';
import 'package:sanmill/generated/intl/l10n_en.dart';
import 'package:sanmill/generated/intl/l10n_es.dart';
import 'package:sanmill/generated/intl/l10n_et.dart';
import 'package:sanmill/generated/intl/l10n_fa.dart';
import 'package:sanmill/generated/intl/l10n_fi.dart';
import 'package:sanmill/generated/intl/l10n_fr.dart';
import 'package:sanmill/generated/intl/l10n_gu.dart';
import 'package:sanmill/generated/intl/l10n_hi.dart';
import 'package:sanmill/generated/intl/l10n_hr.dart';
import 'package:sanmill/generated/intl/l10n_hu.dart';
import 'package:sanmill/generated/intl/l10n_id.dart';
import 'package:sanmill/generated/intl/l10n_it.dart';
import 'package:sanmill/generated/intl/l10n_ja.dart';
import 'package:sanmill/generated/intl/l10n_kn.dart';
import 'package:sanmill/generated/intl/l10n_ko.dart';
import 'package:sanmill/generated/intl/l10n_lt.dart';
import 'package:sanmill/generated/intl/l10n_lv.dart';
import 'package:sanmill/generated/intl/l10n_mk.dart';
import 'package:sanmill/generated/intl/l10n_ms.dart';
import 'package:sanmill/generated/intl/l10n_nl.dart';
import 'package:sanmill/generated/intl/l10n_nn.dart';
import 'package:sanmill/generated/intl/l10n_pl.dart';
import 'package:sanmill/generated/intl/l10n_pt.dart';
import 'package:sanmill/generated/intl/l10n_ro.dart';
import 'package:sanmill/generated/intl/l10n_ru.dart';
import 'package:sanmill/generated/intl/l10n_sk.dart';
import 'package:sanmill/generated/intl/l10n_sl.dart';
import 'package:sanmill/generated/intl/l10n_sq.dart';
import 'package:sanmill/generated/intl/l10n_sr.dart';
import 'package:sanmill/generated/intl/l10n_sv.dart';
import 'package:sanmill/generated/intl/l10n_te.dart';
import 'package:sanmill/generated/intl/l10n_th.dart';
import 'package:sanmill/generated/intl/l10n_tr.dart';
import 'package:sanmill/generated/intl/l10n_uz.dart';
import 'package:sanmill/generated/intl/l10n_vi.dart';
import 'package:sanmill/generated/intl/l10n_zh.dart';

Map<String, String> languageCodeToStrings = {
  'ar': SAr().languageName,
  'bg': SBg().languageName,
  'bn': SBn().languageName,
  'cs': SCs().languageName,
  'da': SDa().languageName,
  'de': SDe().languageName,
  'de_CH': SDeCh().languageName,
  'el': SEl().languageName,
  'en': SEn().languageName,
  'es': SEs().languageName,
  'et': SEt().languageName,
  'fa': SFa().languageName,
  'fi': SFi().languageName,
  'fr': SFr().languageName,
  'gu': SGu().languageName,
  'hi': SHi().languageName,
  'hr': SHr().languageName,
  'hu': SHu().languageName,
  'id': SId().languageName,
  'it': SIt().languageName,
  'ja': SJa().languageName,
  'kn': SKn().languageName,
  'ko': SKo().languageName,
  'lt': SLt().languageName,
  'lv': SLv().languageName,
  'mk': SMk().languageName,
  'ms': SMs().languageName,
  'nl': SNl().languageName,
  'nn': SNn().languageName,
  'pl': SPl().languageName,
  'pt': SPt().languageName,
  'ro': SRo().languageName,
  'ru': SRu().languageName,
  'sk': SSk().languageName,
  'sl': SSl().languageName,
  'sq': SSq().languageName,
  'sr': SSr().languageName,
  'sv': SSv().languageName,
  'te': STe().languageName,
  'th': STh().languageName,
  'tr': STr().languageName,
  'uz': SUz().languageName,
  'vi': SVi().languageName,
  'zh': SZh().languageName,
  'zh_Hant': SZhHant().languageName,
};

String specialCountryAndRegion = "";

void setSpecialCountryAndRegion(BuildContext context) {
  final Locale currentLocale = Localizations.localeOf(context);

  switch (currentLocale.countryCode) {
    case "IR":
      specialCountryAndRegion = "Iran";
      break;
    default:
      specialCountryAndRegion = "";
      break;
  }

  debugPrint("Set Special Country and Region to $specialCountryAndRegion.");
}
