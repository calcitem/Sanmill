// This file is part of Sanmill.
// Copyright (C) 2019-2023 The Sanmill developers (see AUTHORS file)
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

import '../generated/intl/l10n_ar.dart';
import '../generated/intl/l10n_bg.dart';
import '../generated/intl/l10n_bn.dart';
import '../generated/intl/l10n_cs.dart';
import '../generated/intl/l10n_da.dart';
import '../generated/intl/l10n_de.dart';
import '../generated/intl/l10n_el.dart';
import '../generated/intl/l10n_en.dart';
import '../generated/intl/l10n_es.dart';
import '../generated/intl/l10n_et.dart';
import '../generated/intl/l10n_fa.dart';
import '../generated/intl/l10n_fi.dart';
import '../generated/intl/l10n_fr.dart';
import '../generated/intl/l10n_gu.dart';
import '../generated/intl/l10n_hi.dart';
import '../generated/intl/l10n_hr.dart';
import '../generated/intl/l10n_hu.dart';
import '../generated/intl/l10n_id.dart';
import '../generated/intl/l10n_it.dart';
import '../generated/intl/l10n_ja.dart';
import '../generated/intl/l10n_kn.dart';
import '../generated/intl/l10n_ko.dart';
import '../generated/intl/l10n_lt.dart';
import '../generated/intl/l10n_lv.dart';
import '../generated/intl/l10n_mk.dart';
import '../generated/intl/l10n_ms.dart';
import '../generated/intl/l10n_nb.dart';
import '../generated/intl/l10n_nl.dart';
import '../generated/intl/l10n_pl.dart';
import '../generated/intl/l10n_pt.dart';
import '../generated/intl/l10n_ro.dart';
import '../generated/intl/l10n_ru.dart';
import '../generated/intl/l10n_sk.dart';
import '../generated/intl/l10n_sl.dart';
import '../generated/intl/l10n_sq.dart';
import '../generated/intl/l10n_sr.dart';
import '../generated/intl/l10n_sv.dart';
import '../generated/intl/l10n_te.dart';
import '../generated/intl/l10n_th.dart';
import '../generated/intl/l10n_tr.dart';
import '../generated/intl/l10n_uk.dart';
import '../generated/intl/l10n_uz.dart';
import '../generated/intl/l10n_vi.dart';
import '../generated/intl/l10n_zh.dart';

Map<Locale, String> localeToLanguageName = <Locale, String>{
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
