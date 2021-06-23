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

Map<String, String> languageMap = {
  "de": "Deutsch",
  "en": "English",
  "fa": "فارسی",
  "hu": "Magyar",
  "ro": "Română",
  "zh": "简体中文",
};

/// Interface strings
abstract class Strings {
  String get tapBackAgainToLeave;
}

/// English strings
class EnglishStrings extends Strings {
  @override
  String get tapBackAgainToLeave => 'Tap back again to leave.';
}

/// German strings
class GermanStrings extends Strings {
  @override
  String get tapBackAgainToLeave => 'Nochmal drücken um zu Beenden.';
}

/// Hungarian strings
class HungarianStrings extends Strings {
  @override
  String get tapBackAgainToLeave =>
      'A kilépéshez kattintson ismételten a Vissza gombra.';
}

/// Romanian strings
class RomanianStrings extends Strings {
  @override
  String get tapBackAgainToLeave => 'Atingeți din nou pentru a pleca.';
}

/// Chinese strings
class ChineseStrings extends Strings {
  @override
  String get tapBackAgainToLeave => '再次按返回键退出应用';
}

/// Farsi strings
class FarsiStrings extends Strings {
  @override
  String get tapBackAgainToLeave =>
      'برای خروج از برنامه ، دوباره روی دکمه برگشت ضربه بزنید.';
}

class Resources {
  Resources();

  Strings get strings {
    String deviceLanguage = Platform.localeName.substring(0, 2);
    switch (deviceLanguage) {
      case 'de':
        return GermanStrings();
      case 'hu':
        return HungarianStrings();
      case 'ro':
        return RomanianStrings();
      case 'zh':
        return ChineseStrings();
      case 'fa':
        return FarsiStrings();
      default:
        return EnglishStrings();
    }
  }

  static Resources of() {
    return Resources();
  }
}
