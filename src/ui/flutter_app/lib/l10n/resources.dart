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
import 'package:sanmill/common/constants.dart';
import 'package:sanmill/generated/l10n.dart';
import 'package:sanmill/style/app_theme.dart';
import 'package:sanmill/widgets/list_item_divider.dart';

Map<String, Strings> languageCodeToStrings = {
  "ar": ArabicStrings(),
  "cs": CzechStrings(),
  "de": GermanStrings(),
  "en": EnglishStrings(),
  "es": SpanishStrings(),
  "fa": FarsiStrings(),
  "fr": FrenchStrings(),
  "hi": HindiStrings(),
  "hu": HungarianStrings(),
  "it": ItalianStrings(),
  "ja": JapaneseStrings(),
  "ko": KoreanStrings(),
  "pl": PolishStrings(),
  "pt": PortugueseStrings(),
  "ro": RomanianStrings(),
  "ru": RussianStrings(),
  "tr": TurkishStrings(),
  "zh": ChineseStrings(),
};

/// Interface strings
abstract class Strings {
  String get languageName;
  String get tapBackAgainToLeave;
}

/// ar
class ArabicStrings extends Strings {
  @override
  String get languageName => 'عربى';

  @override
  String get tapBackAgainToLeave => 'انقر مرة أخرى للمغادرة.';
}

/// cs
class CzechStrings extends Strings {
  @override
  String get languageName => 'Čeština';

  @override
  String get tapBackAgainToLeave => 'Opětovným klepnutím zpět odejdete.';
}

/// de
class GermanStrings extends Strings {
  @override
  String get languageName => 'Deutsch';

  @override
  String get tapBackAgainToLeave => 'Nochmal drücken um zu Beenden.';
}

/// en
class EnglishStrings extends Strings {
  @override
  String get languageName => 'English';

  @override
  String get tapBackAgainToLeave => 'Tap back again to leave.';
}

/// es
class SpanishStrings extends Strings {
  @override
  String get languageName => 'Español';

  @override
  String get tapBackAgainToLeave => 'Vuelve a tocar para salir.';
}

/// fa
class FarsiStrings extends Strings {
  @override
  String get languageName => 'فارسی';

  @override
  String get tapBackAgainToLeave =>
      'برای خروج از برنامه ، دوباره روی دکمه برگشت ضربه بزنید.';
}

/// fr
class FrenchStrings extends Strings {
  @override
  String get languageName => 'Français';

  @override
  String get tapBackAgainToLeave => 'Tapez à nouveau pour quitter.';
}

/// hi
class HindiStrings extends Strings {
  @override
  String get languageName => 'हिंदी';

  @override
  String get tapBackAgainToLeave => 'जाने के लिए फिर से टैप करें।';
}

/// hu
class HungarianStrings extends Strings {
  @override
  String get languageName => 'Magyar';

  @override
  String get tapBackAgainToLeave =>
      'A kilépéshez kattintson ismételten a Vissza gombra.';
}

/// it
class ItalianStrings extends Strings {
  @override
  String get languageName => 'Italiano';

  @override
  String get tapBackAgainToLeave => 'Tocca di nuovo per uscire.';
}

/// ja
class JapaneseStrings extends Strings {
  @override
  String get languageName => '日本語';

  @override
  String get tapBackAgainToLeave => 'もう一度returnを押してアプリケーションを終了する';
}

/// ko
class KoreanStrings extends Strings {
  @override
  String get languageName => '한국어';

  @override
  String get tapBackAgainToLeave => '애플리케이션을 종료하려면 리턴 키를 다시 누르십시오.';
}

/// pl
class PolishStrings extends Strings {
  @override
  String get languageName => 'Polskie';

  @override
  String get tapBackAgainToLeave => 'Stuknij ponownie w tył, aby wyjść.';
}

/// pt
class PortugueseStrings extends Strings {
  @override
  String get languageName => 'Português';

  @override
  String get tapBackAgainToLeave => 'Bater novamente para sair.';
}

/// ro
class RomanianStrings extends Strings {
  @override
  String get languageName => 'Română';

  @override
  String get tapBackAgainToLeave => 'Atingeți din nou pentru a putea muta.';
}

/// ru
class RussianStrings extends Strings {
  @override
  String get languageName => 'Pусский';

  @override
  String get tapBackAgainToLeave => 'Нажмите назад еще раз, чтобы выйти.';
}

/// tr
class TurkishStrings extends Strings {
  @override
  String get languageName => 'Türk';

  @override
  String get tapBackAgainToLeave => 'Tocca di nuovo per uscire.';
}

/// zh
class ChineseStrings extends Strings {
  @override
  String get languageName => '简体中文';

  @override
  String get tapBackAgainToLeave => '再次按返回键退出应用';
}

final supportedLocales = [
  for (var i in languageCodeToStrings.keys) Locale.fromSubtags(languageCode: i),
];

class Resources {
  Resources();

  String get languageCode {
    if (Config.languageCode == Constants.defaultLanguageCodeName) {
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
          title: Text(languageCodeToStrings[i]!.languageName),
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
