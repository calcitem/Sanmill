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
    languageCode: 'ar',
  ),
  const Locale.fromSubtags(
    languageCode: 'cs',
  ),
  const Locale.fromSubtags(
    languageCode: 'de',
  ),
  const Locale.fromSubtags(
    languageCode: 'es',
  ),
  const Locale.fromSubtags(
    languageCode: 'fa',
  ),
  const Locale.fromSubtags(
    languageCode: 'fr',
  ),
  const Locale.fromSubtags(
    languageCode: 'hu',
  ),
  const Locale.fromSubtags(
    languageCode: 'ja',
  ),
  const Locale.fromSubtags(
    languageCode: 'ko',
  ),
  const Locale.fromSubtags(
    languageCode: 'pt',
  ),
  const Locale.fromSubtags(
    languageCode: 'ro',
  ),
  const Locale.fromSubtags(
    languageCode: 'ru',
  ),
  const Locale.fromSubtags(
    languageCode: 'zh',
  ),
];

Map<String, String> languageCodeToName = {
  "ar": "عربى",
  "cs": "Čeština",
  "de": "Deutsch",
  "en": "English",
  "es": "Español",
  "fa": "فارسی",
  "fr": "Français",
  "hu": "Magyar",
  "ja": "日本語",
  "ko": "한국어",
  "pt": "Português",
  "ro": "Română",
  "ru": "Pусский",
  "zh": "简体中文",
};

Map<String, Strings> languageCodeToStrings = {
  "ar": ArabicStrings(),
  "cs": CzechStrings(),
  "de": GermanStrings(),
  "en": EnglishStrings(),
  "es": SpanishStrings(),
  "fa": FarsiStrings(),
  "fr": FrenchStrings(),
  "hu": HungarianStrings(),
  "ja": JapaneseStrings(),
  "ko": KoreanStrings(),
  "pt": PortugueseStrings(),
  "ro": RomanianStrings(),
  "ru": RussianStrings(),
  "zh": ChineseStrings(),
};

/// Interface strings
abstract class Strings {
  String get tapBackAgainToLeave;
}

/// ar
class ArabicStrings extends Strings {
  @override
  String get tapBackAgainToLeave => 'انقر مرة أخرى للمغادرة.';
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

/// es
class SpanishStrings extends Strings {
  @override
  String get tapBackAgainToLeave => 'Vuelve a tocar para salir.';
}

/// fa
class FarsiStrings extends Strings {
  @override
  String get tapBackAgainToLeave =>
      'برای خروج از برنامه ، دوباره روی دکمه برگشت ضربه بزنید.';
}

/// fr
class FrenchStrings extends Strings {
  @override
  String get tapBackAgainToLeave => 'Tapez à nouveau pour quitter.';
}

/// hu
class HungarianStrings extends Strings {
  @override
  String get tapBackAgainToLeave =>
      'A kilépéshez kattintson ismételten a Vissza gombra.';
}

/// ja
class JapaneseStrings extends Strings {
  @override
  String get tapBackAgainToLeave => 'もう一度returnを押してアプリケーションを終了する';
}

/// ko
class KoreanStrings extends Strings {
  @override
  String get tapBackAgainToLeave => '애플리케이션을 종료하려면 리턴 키를 다시 누르십시오.';
}

/// pt
class PortugueseStrings extends Strings {
  @override
  String get tapBackAgainToLeave => 'Bater novamente para sair.';
}

/// ro
class RomanianStrings extends Strings {
  @override
  String get tapBackAgainToLeave => 'Atingeți din nou pentru a pleca.';
}

/// ru
class RussianStrings extends Strings {
  @override
  String get tapBackAgainToLeave => 'Нажмите назад еще раз, чтобы выйти.';
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
