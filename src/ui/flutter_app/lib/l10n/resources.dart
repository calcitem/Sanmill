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
import 'package:sanmill/generated/l10n.dart';
import 'package:sanmill/services/storage/storage.dart';
import 'package:sanmill/shared/constants.dart';
import 'package:sanmill/shared/list_item_divider.dart';
import 'package:sanmill/shared/theme/app_theme.dart';

Map<Locale, Strings> languageCodeToStrings = {
  const Locale("ar"): ArabicStrings(),
  const Locale("bg"): BulgarianStrings(),
  const Locale("bn"): BengaliStrings(),
  const Locale("cs"): CzechStrings(),
  const Locale("da"): DanishStrings(),
  const Locale("de"): GermanStrings(),
  const Locale("de_CH"): SwissGermanStrings(),
  const Locale("el"): GreekStrings(),
  const Locale("en"): EnglishStrings(),
  const Locale("es"): SpanishStrings(),
  const Locale("et"): EstonianStrings(),
  const Locale("fa"): FarsiStrings(),
  const Locale("fi"): FinnishStrings(),
  const Locale("fr"): FrenchStrings(),
  const Locale("gu"): GujaratiStrings(),
  const Locale("hi"): HindiStrings(),
  const Locale("hr"): CroatianStrings(),
  const Locale("hu"): HungarianStrings(),
  const Locale("id"): IndonesianStrings(),
  const Locale("it"): ItalianStrings(),
  const Locale("ja"): JapaneseStrings(),
  const Locale("kn"): KannadaStrings(),
  const Locale("ko"): KoreanStrings(),
  const Locale("lt"): LithuanianStrings(),
  const Locale("lv"): LatvianStrings(),
  const Locale("mk"): MacedonianStrings(),
  const Locale("ms"): MalayStrings(),
  const Locale("nl"): DutchStrings(),
  const Locale("nn"): NorwegianStrings(),
  const Locale("pl"): PolishStrings(),
  const Locale("pt"): PortugueseStrings(),
  const Locale("ro"): RomanianStrings(),
  const Locale("ru"): RussianStrings(),
  const Locale("sk"): SlovakStrings(),
  const Locale("sl"): SlovenianStrings(),
  const Locale("sq"): AlbanianStrings(),
  const Locale("sr"): SerbianStrings(),
  const Locale("sv"): SwedishStrings(),
  const Locale("te"): TeluguStrings(),
  const Locale("th"): ThaiStrings(),
  const Locale("tr"): TurkishStrings(),
  const Locale("uz"): UzbekStrings(),
  const Locale("vi"): VietnameseStrings(),
  const Locale("zh"): ChineseStrings(),
  const Locale("zh_Hant"): TraditionalChineseStrings(),
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

/// bg
class BulgarianStrings extends Strings {
  @override
  String get languageName => 'български';

  @override
  String get tapBackAgainToLeave => 'Докоснете отново назад, за да излезете.';
}

/// bn
class BengaliStrings extends Strings {
  @override
  String get languageName => 'বাংলা';

  @override
  String get tapBackAgainToLeave => 'ছেড়ে যেতে আবার আলতো চাপুন।';
}

/// cs
class CzechStrings extends Strings {
  @override
  String get languageName => 'Čeština';

  @override
  String get tapBackAgainToLeave => 'Opětovným klepnutím zpět odejdete.';
}

/// da
class DanishStrings extends Strings {
  @override
  String get languageName => 'Dansk';

  @override
  String get tapBackAgainToLeave => 'Tryk tilbage igen for at gå.';
}

/// de
class GermanStrings extends Strings {
  @override
  String get languageName => 'Deutsch';

  @override
  String get tapBackAgainToLeave => 'Nochmal drücken um zu Beenden.';
}

/// de-ch
class SwissGermanStrings extends Strings {
  @override
  String get languageName => 'Schweizerdeutsch';

  @override
  String get tapBackAgainToLeave => 'Nochmal drücken um zu Beenden.';
}

/// el
class GreekStrings extends Strings {
  @override
  String get languageName => 'Ελληνικά';

  @override
  String get tapBackAgainToLeave => 'Πατήστε ξανά πίσω για να φύγετε.';
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
  String get tapBackAgainToLeave => 'Vuelva a tocar para salir.';
}

/// et
class EstonianStrings extends Strings {
  @override
  String get languageName => 'Eestlane';

  @override
  String get tapBackAgainToLeave => 'Koputage uuesti tagasi, et lahkuda.';
}

/// fa
class FarsiStrings extends Strings {
  @override
  String get languageName => 'فارسی';

  @override
  String get tapBackAgainToLeave =>
      'برای خروج از برنامه ، دوباره روی دکمه برگشت ضربه بزنید.';
}

/// fi
class FinnishStrings extends Strings {
  @override
  String get languageName => 'Suomalainen';

  @override
  String get tapBackAgainToLeave => 'Poistu napauttamalla uudelleen takaisin.';
}

/// fr
class FrenchStrings extends Strings {
  @override
  String get languageName => 'Français';

  @override
  String get tapBackAgainToLeave => 'Tapez à nouveau pour quitter.';
}

/// gu
class GujaratiStrings extends Strings {
  @override
  String get languageName => 'ગુજરાતી';

  @override
  String get tapBackAgainToLeave => 'જવા માટે ફરીથી ટેપ કરો.';
}

/// hi
class HindiStrings extends Strings {
  @override
  String get languageName => 'हिंदी';

  @override
  String get tapBackAgainToLeave => 'जाने के लिए फिर से टैप करें।';
}

/// hr
class CroatianStrings extends Strings {
  @override
  String get languageName => 'Hrvatski';

  @override
  String get tapBackAgainToLeave => 'Ponovno dodirnite za napuštanje.';
}

/// hu
class HungarianStrings extends Strings {
  @override
  String get languageName => 'Magyar';

  @override
  String get tapBackAgainToLeave =>
      'A kilépéshez kattintson ismételten a Vissza gombra.';
}

/// id
class IndonesianStrings extends Strings {
  @override
  String get languageName => 'Indonesia';

  @override
  String get tapBackAgainToLeave => 'Ketuk kembali lagi untuk pergi.';
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

/// kn
class KannadaStrings extends Strings {
  @override
  String get languageName => 'ಕನ್ನಡ';

  @override
  String get tapBackAgainToLeave => 'ಬಿಡಲು ಮತ್ತೆ ಟ್ಯಾಪ್ ಮಾಡಿ.';
}

/// ko
class KoreanStrings extends Strings {
  @override
  String get languageName => '한국어';

  @override
  String get tapBackAgainToLeave => '애플리케이션을 종료하려면 리턴 키를 다시 누르십시오.';
}

/// lt
class LithuanianStrings extends Strings {
  @override
  String get languageName => 'Lietuvis';

  @override
  String get tapBackAgainToLeave =>
      'Dar kartą bakstelėkite atgal, kad išeitumėte.';
}

/// lv
class LatvianStrings extends Strings {
  @override
  String get languageName => 'Latvietis';

  @override
  String get tapBackAgainToLeave => 'Pieskarieties atpakaļ, lai izietu.';
}

/// mk
class MacedonianStrings extends Strings {
  @override
  String get languageName => 'Македонски';

  @override
  String get tapBackAgainToLeave => 'Допрете назад за да заминете.';
}

/// ms
class MalayStrings extends Strings {
  @override
  String get languageName => 'Melayu';

  @override
  String get tapBackAgainToLeave => 'Ketik kembali sekali lagi untuk pergi.';
}

/// nl
class DutchStrings extends Strings {
  @override
  String get languageName => 'Nederlands';

  @override
  String get tapBackAgainToLeave => 'Tik opnieuw om te vertrekken.';
}

/// nn
class NorwegianStrings extends Strings {
  @override
  String get languageName => 'Norsk';

  @override
  String get tapBackAgainToLeave => 'Trykk tilbake for å dra.';
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
  String get tapBackAgainToLeave => 'Toque novamente para sair.';
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

/// sk
class SlovakStrings extends Strings {
  @override
  String get languageName => 'Slovák';

  @override
  String get tapBackAgainToLeave => 'Ťuknutím na tlačidlo späť znova odíďte.';
}

/// sl
class SlovenianStrings extends Strings {
  @override
  String get languageName => 'Slovenščina';

  @override
  String get tapBackAgainToLeave =>
      'Ponovno se dotaknite nazaj, če želite oditi.';
}

/// sq
class AlbanianStrings extends Strings {
  @override
  String get languageName => 'Shqiptare';

  @override
  String get tapBackAgainToLeave => 'Trokit përsëri përsëri për t\'u larguar.';
}

/// sr
class SerbianStrings extends Strings {
  @override
  String get languageName => 'Српски';

  @override
  String get tapBackAgainToLeave => 'Додирните поново да бисте изашли.';
}

/// sv
class SwedishStrings extends Strings {
  @override
  String get languageName => 'Svenska';

  @override
  String get tapBackAgainToLeave => 'Tryck tillbaka igen för att gå vidare.';
}

/// te
class TeluguStrings extends Strings {
  @override
  String get languageName => 'తెలుగు';

  @override
  String get tapBackAgainToLeave => 'బయలుదేరడానికి మళ్ళీ నొక్కండి.';
}

/// th
class ThaiStrings extends Strings {
  @override
  String get languageName => 'ไทย';

  @override
  String get tapBackAgainToLeave => 'แตะกลับอีกครั้งเพื่อออก';
}

/// tr
class TurkishStrings extends Strings {
  @override
  String get languageName => 'Türk';

  @override
  String get tapBackAgainToLeave => 'Tocca di nuovo per uscire.';
}

/// uz
class UzbekStrings extends Strings {
  @override
  String get languageName => 'O\'zbek';

  @override
  String get tapBackAgainToLeave => 'Ketish uchun yana bir marta bosing.';
}

/// vi
class VietnameseStrings extends Strings {
  @override
  String get languageName => 'Tiếng Việt';

  @override
  String get tapBackAgainToLeave =>
      'Nhấn phím quay lại một lần nữa để thoát ứng dụng.';
}

/// zh
class ChineseStrings extends Strings {
  @override
  String get languageName => '简体中文';

  @override
  String get tapBackAgainToLeave => '再次按返回键退出应用';
}

/// zh-Hant
class TraditionalChineseStrings extends Strings {
  @override
  String get languageName => '繁體中文';

  @override
  String get tapBackAgainToLeave => '再次按 Back 鍵退出';
}

final List<Locale> supportedLocales = [
  ...languageCodeToStrings.keys,
];

class Resources {
  Resources();

  String get languageCode {
    if (LocalDatabaseService.display.languageCode == Constants.defaultLocale) {
      return Platform.localeName.substring(0, 2);
    }

    return LocalDatabaseService.display.languageCode.languageCode;
  }

  Strings get strings {
    final Strings? ret = languageCodeToStrings[languageCode];

    if (ret == null) {
      return EnglishStrings();
    }

    return ret;
  }

  // ignore: prefer_constructors_over_static_methods
  static Resources of() {
    return Resources();
  }
}

Future<void> setLanguage(
  BuildContext context,
  Function(Locale?)? callback,
) async {
  final languageColumn = Column(
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      RadioListTile<Locale>(
        activeColor: AppTheme.switchListTileActiveColor,
        title: Text(S.of(context).defaultLanguage),
        groupValue: LocalDatabaseService.display.languageCode,
        value: Constants.defaultLocale,
        onChanged: callback,
      ),
      const ListItemDivider(),
      for (var i in languageCodeToStrings.keys)
        RadioListTile<Locale>(
          activeColor: AppTheme.switchListTileActiveColor,
          title: Text(languageCodeToStrings[i]!.languageName),
          groupValue: LocalDatabaseService.display.languageCode,
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

enum Bidirectionality {
  leftToRight,
  rightToLeft,
}

Bidirectionality getBidirectionality(BuildContext context) {
  final Locale currentLocale = Localizations.localeOf(context);
  if (currentLocale.languageCode == "ar" ||
      currentLocale.languageCode == "fa" ||
      currentLocale.languageCode == "he" ||
      currentLocale.languageCode == "ps" ||
      currentLocale.languageCode == "ur") {
    debugPrint("bidirectionality: RTL");
    return Bidirectionality.rightToLeft;
  } else {
    return Bidirectionality.leftToRight;
  }
}

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
