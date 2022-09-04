// This file is part of Sanmill.
// Copyright (C) 2019-2022 The Sanmill developers (see AUTHORS file)
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

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:sanmill/common/config.dart';
import 'package:sanmill/generated/intl/l10n.dart';
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
import 'package:sanmill/generated/intl/l10n_nb.dart';
import 'package:sanmill/generated/intl/l10n_nl.dart';
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
import 'package:sanmill/generated/intl/l10n_uk.dart';
import 'package:sanmill/generated/intl/l10n_uz.dart';
import 'package:sanmill/generated/intl/l10n_vi.dart';
import 'package:sanmill/generated/intl/l10n_zh.dart';
import 'package:sanmill/shared/constants.dart';
import 'package:sanmill/style/app_theme.dart';
import 'package:sanmill/widgets/list_item_divider.dart';

Map<Locale, String> languageCodeToStrings = {
  const Locale("ar"): SAr().languageName,
  const Locale("bg"): SBg().languageName,
  const Locale("bn"): SBn().languageName,
  const Locale("cs"): SCs().languageName,
  const Locale("da"): SDa().languageName,
  const Locale("de"): SDe().languageName,
  const Locale("de", "CH"): SDeCh().languageName,
  const Locale("el"): SEl().languageName,
  const Locale("en"): SEn().languageName,
  const Locale("es"): SEs().languageName,
  const Locale("et"): SEt().languageName,
  const Locale("fa"): SFa().languageName,
  const Locale("fi"): SFi().languageName,
  const Locale("fr"): SFr().languageName,
  const Locale("gu"): SGu().languageName,
  const Locale("hi"): SHi().languageName,
  const Locale("hr"): SHr().languageName,
  const Locale("hu"): SHu().languageName,
  const Locale("id"): SId().languageName,
  const Locale("it"): SIt().languageName,
  const Locale("ja"): SJa().languageName,
  const Locale("kn"): SKn().languageName,
  const Locale("ko"): SKo().languageName,
  const Locale("lt"): SLt().languageName,
  const Locale("lv"): SLv().languageName,
  const Locale("mk"): SMk().languageName,
  const Locale("ms"): SMs().languageName,
  const Locale("nl"): SNl().languageName,
  const Locale("nb"): SNb().languageName,
  const Locale("pl"): SPl().languageName,
  const Locale("pt"): SPt().languageName,
  const Locale("ro"): SRo().languageName,
  const Locale("ru"): SRu().languageName,
  const Locale("sk"): SSk().languageName,
  const Locale("sl"): SSl().languageName,
  const Locale("sq"): SSq().languageName,
  const Locale("sr"): SSr().languageName,
  const Locale("sv"): SSv().languageName,
  const Locale("te"): STe().languageName,
  const Locale("th"): STh().languageName,
  const Locale("tr"): STr().languageName,
  const Locale("uk"): SUk().languageName,
  const Locale("uz"): SUz().languageName,
  const Locale("vi"): SVi().languageName,
  const Locale("zh"): SZh().languageName,
  const Locale.fromSubtags(languageCode: "zh", scriptCode: "Hant"):
      SZhHant().languageName,
};

// TODO: Remove below

class Resources {
  Resources();

  String get languageCode {
    if (Config.languageCode == Constants.defaultLanguageCodeName) {
      return Platform.localeName.substring(0, 2);
    }

    return Config.languageCode;
  }

  static Resources of() {
    return Resources();
  }
}

setLanguage(BuildContext context, var callback) async {
  var languageColumn = Column(
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      RadioListTile(
        activeColor: AppTheme.switchListTileActiveColor,
        title: Text(S.of(context).defaultLanguage),
        groupValue: Config.languageCode,
        value: Constants.defaultLanguageCodeName,
        onChanged: callback,
      ),
      ListItemDivider(),
      for (var i in languageCodeToStrings.keys)
        RadioListTile(
          activeColor: AppTheme.switchListTileActiveColor,
          title: Text(languageCodeToStrings[i]!),
          groupValue: Config.languageCode,
          value: i,
          onChanged: callback,
        ),
    ],
  );

  showDialog<void>(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        scrollable: true,
        content: StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            return languageColumn;
          },
        ),
      );
    },
  );
}

// TODO: Remove it (See: 4ac0f192dd9c316ab93dbba4915ef504c01b93c6)
String specialCountryAndRegion = "";

setSpecialCountryAndRegion(BuildContext context) {
  Locale currentLocale = Localizations.localeOf(context);

  switch (currentLocale.countryCode) {
    case "IR":
      specialCountryAndRegion = "Iran";
      break;
    default:
      specialCountryAndRegion = "";
      break;
  }

  print("Set Special Country and Region to $specialCountryAndRegion.");
}
