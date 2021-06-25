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

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:sanmill/common/config.dart';

final supportedLocales = [
  const Locale('en', ''),
  const Locale.fromSubtags(
    languageCode: 'cs',
  ),
  const Locale.fromSubtags(
    languageCode: 'de',
  ),
  const Locale.fromSubtags(
    languageCode: 'fa',
  ),
  const Locale.fromSubtags(
    languageCode: 'hu',
  ),
  const Locale.fromSubtags(
    languageCode: 'ro',
  ),
  const Locale.fromSubtags(
    languageCode: 'zh',
  ),
];

Map<String, String> languageCodeToName = {
  "cs": "Čeština",
  "de": "Deutsch",
  "en": "English",
  "fa": "فارسی",
  "hu": "Magyar",
  "ro": "Română",
  "zh": "简体中文",
};

Map<String, Strings> languageCodeToStrings = {
  "cs": CzechStrings(),
  "de": GermanStrings(),
  "en": EnglishStrings(),
  "fa": FarsiStrings(),
  "hu": HungarianStrings(),
  "ro": RomanianStrings(),
  "zh": ChineseStrings(),
};

/// Interface strings
abstract class Strings {
  String get tapBackAgainToLeave;
}

/// cs
class CzechStrings extends Strings {
  @override
  String get tapBackAgainToLeave => 'Opětovným klepnutím zpět odejdete.';
}

/// de
class GermanStrings extends Strings {
  @override
  String get tapBackAgainToLeave => 'Nochmal drücken um zu Beenden.';
}

/// en
class EnglishStrings extends Strings {
  @override
  String get tapBackAgainToLeave => 'Tap back again to leave.';
}

/// fa
class FarsiStrings extends Strings {
  @override
  String get tapBackAgainToLeave =>
      'برای خروج از برنامه ، دوباره روی دکمه برگشت ضربه بزنید.';
}

/// hu
class HungarianStrings extends Strings {
  @override
  String get tapBackAgainToLeave =>
      'A kilépéshez kattintson ismételten a Vissza gombra.';
}

/// ro
class RomanianStrings extends Strings {
  @override
  String get tapBackAgainToLeave => 'Atingeți din nou pentru a pleca.';
}

/// zh
class ChineseStrings extends Strings {
  @override
  String get tapBackAgainToLeave => '再次按返回键退出应用';
}

class Resources {
  Resources();

  String get languageCode {
    if (Config.languageCode == "Default") {
      return Platform.localeName.substring(0, 2);
    }

    return Config.languageCode;
  }

  Strings get strings {
    Strings? ret = languageCodeToStrings[languageCode];

    if (ret == null) {
      return EnglishStrings();
    }

    return ret;
  }

  static Resources of() {
    return Resources();
  }
}
