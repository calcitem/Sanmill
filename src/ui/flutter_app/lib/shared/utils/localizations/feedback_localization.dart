// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// feedback_localization.dart

import 'package:feedback/feedback.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../services/logger.dart';

// TODO: [Leptopoda] This implementation is shitty and I don't like it. Just a reminder that I wanted to rewrite it.

/// This is a localization delegate, which includes all of the localizations
/// already present in this library.
class CustomFeedbackLocalizationsDelegate
    extends LocalizationsDelegate<FeedbackLocalizations> {
  /// Creates a [CustomFeedbackLocalizationsDelegate].
  const CustomFeedbackLocalizationsDelegate();

  /// Returns the default instance of a [CustomFeedbackLocalizationsDelegate].
  static const LocalizationsDelegate<FeedbackLocalizations> delegate =
      CustomFeedbackLocalizationsDelegate();

  static final Map<Locale, FeedbackLocalizations> _supportedLocales =
      <Locale, FeedbackLocalizations>{
    const Locale("af"): const AfFeedbackLocalizations(), // Afrikaans
    const Locale("am"): const AmFeedbackLocalizations(), // Amharic
    const Locale("ar"): const ArFeedbackLocalizations(), // Arabic
    const Locale("az"): const AzFeedbackLocalizations(), // Azerbaijani
    const Locale("be"): const BeFeedbackLocalizations(), // Belarusian
    const Locale("bg"): const BgFeedbackLocalizations(), // Bulgarian
    const Locale("bn"): const BnFeedbackLocalizations(), // Bengali
    const Locale("bo"): const BoFeedbackLocalizations(), // Tibetan
    const Locale("bs"): const BsFeedbackLocalizations(), // Bosnian
    const Locale("ca"): const CaFeedbackLocalizations(), // Catalan
    const Locale("cs"): const CsFeedbackLocalizations(), // Czech
    const Locale("da"): const DaFeedbackLocalizations(), // Danish
    const Locale("de"): const DeFeedbackLocalizations(), // German
    const Locale("el"): const ElFeedbackLocalizations(), // Greek
    const Locale("en"): const EnFeedbackLocalizations(), // English
    const Locale("es"): const EsFeedbackLocalizations(), // Spanish
    const Locale("et"): const EtFeedbackLocalizations(), // Estonian
    const Locale("fa"): const FaFeedbackLocalizations(), // Persian (Farsi)
    const Locale("fi"): const FiFeedbackLocalizations(), // Finnish
    const Locale("fr"): const FrFeedbackLocalizations(), // French
    const Locale("gu"): const GuFeedbackLocalizations(), // Gujarati
    const Locale("he"): const HeFeedbackLocalizations(), // Hebrew
    const Locale("hi"): const HiFeedbackLocalizations(), // Hindi
    const Locale("hr"): const HrFeedbackLocalizations(), // Croatian
    const Locale("hu"): const HuFeedbackLocalizations(), // Hungarian
    const Locale("hy"): const HyFeedbackLocalizations(), // Armenian
    const Locale("id"): const IdFeedbackLocalizations(), // Indonesian
    const Locale("is"): const IsFeedbackLocalizations(), // Icelandic
    const Locale("it"): const ItFeedbackLocalizations(), // Italian
    const Locale("ja"): const JaFeedbackLocalizations(), // Japanese
    const Locale("km"): const KmFeedbackLocalizations(), // Khmer
    const Locale("kn"): const KnFeedbackLocalizations(), // Kannada
    const Locale("ko"): const KoFeedbackLocalizations(), // Korean
    const Locale("lt"): const LtFeedbackLocalizations(), // Lithuanian
    const Locale("lv"): const LvFeedbackLocalizations(), // Latvian
    const Locale("mk"): const MkFeedbackLocalizations(), // Macedonian
    const Locale("ms"): const MsFeedbackLocalizations(), // Malay
    const Locale("my"): const MyFeedbackLocalizations(), // Burmese
    const Locale("nb"): const NbFeedbackLocalizations(), // Norwegian
    const Locale("nl"): const NlFeedbackLocalizations(), // Dutch
    const Locale("pl"): const PlFeedbackLocalizations(), // Polish
    const Locale("pt"): const PtFeedbackLocalizations(), // Portuguese
    const Locale("ro"): const RoFeedbackLocalizations(), // Romanian
    const Locale("ru"): const RuFeedbackLocalizations(), // Russian
    const Locale("si"): const SiFeedbackLocalizations(), // Sinhala
    const Locale("sk"): const SkFeedbackLocalizations(), // Slovak
    const Locale("sl"): const SlFeedbackLocalizations(), // Slovenian
    const Locale("sq"): const SqFeedbackLocalizations(), // Albanian
    const Locale("sr"): const SrFeedbackLocalizations(), // Serbian
    const Locale("sv"): const SvFeedbackLocalizations(), // Swedish
    const Locale("sw"): const SwFeedbackLocalizations(), // Swahili
    const Locale("ta"): const TaFeedbackLocalizations(), // Tamil
    const Locale("te"): const TeFeedbackLocalizations(), // Telugu
    const Locale("th"): const ThFeedbackLocalizations(), // Thai
    const Locale("tr"): const TrFeedbackLocalizations(), // Turkish
    const Locale("uk"): const UkFeedbackLocalizations(), // Ukrainian
    const Locale("ur"): const UrFeedbackLocalizations(), // Urdu
    const Locale("uz"): const UzFeedbackLocalizations(), // Uzbek
    const Locale("vi"): const ViFeedbackLocalizations(), // Vietnamese
    const Locale("zh"): const ZhFeedbackLocalizations(), // Chinese
    const Locale("zu"): const ZuFeedbackLocalizations(), // Zulu
  };

  @override
  bool isSupported(Locale locale) {
    // We only support language codes for now
    if (_supportedLocales.containsKey(Locale(locale.languageCode))) {
      return true;
    }
    logger.w(
      'The locale $locale is not supported, '
      'falling back to english translations',
    );
    return true;
  }

  @override
  Future<FeedbackLocalizations> load(Locale locale) async {
    final Locale languageLocale = Locale(locale.languageCode);
    // We only support language codes for now
    if (_supportedLocales.containsKey(languageLocale)) {
      return _supportedLocales[languageLocale]!;
    }
    // The default is english
    return const EnFeedbackLocalizations();
  }

  @override
  bool shouldReload(CustomFeedbackLocalizationsDelegate old) => false;

  @override
  String toString() => 'DefaultFeedbackLocalizations.delegate(en_EN)';
}

class AfFeedbackLocalizations extends FeedbackLocalizations {
  const AfFeedbackLocalizations();

  @override
  String get submitButtonText => 'Indien';

  @override
  String get feedbackDescriptionText => 'Wat is verkeerd?';

  @override
  String get draw => 'Teken';

  @override
  String get navigate => 'Navigeer';

  static Future<FeedbackLocalizations> load(Locale locale) {
    return SynchronousFuture<FeedbackLocalizations>(
      const AfFeedbackLocalizations(),
    );
  }
}

class AmFeedbackLocalizations extends FeedbackLocalizations {
  const AmFeedbackLocalizations();

  @override
  String get submitButtonText => 'አስገባ';

  @override
  String get feedbackDescriptionText => 'ምን ተሳስቷል?';

  @override
  String get draw => 'ማሟያ';

  @override
  String get navigate => 'መራ';

  static Future<FeedbackLocalizations> load(Locale locale) {
    return SynchronousFuture<FeedbackLocalizations>(
      const AmFeedbackLocalizations(),
    );
  }
}

class ArFeedbackLocalizations extends FeedbackLocalizations {
  const ArFeedbackLocalizations();

  @override
  String get submitButtonText => 'إرسال';

  @override
  String get feedbackDescriptionText => 'ما الذي يمكننا فعله بشكل أفضل؟';

  @override
  String get draw => 'رسم';

  @override
  String get navigate => 'التنقل';

  static Future<FeedbackLocalizations> load(Locale locale) {
    return SynchronousFuture<FeedbackLocalizations>(
      const ArFeedbackLocalizations(),
    );
  }
}

class AzFeedbackLocalizations extends FeedbackLocalizations {
  const AzFeedbackLocalizations();

  @override
  String get submitButtonText => 'Göndər';

  @override
  String get feedbackDescriptionText => 'Nə yalnışdır?';

  @override
  String get draw => 'Çək';

  @override
  String get navigate => 'Naviqasiya et';

  static Future<FeedbackLocalizations> load(Locale locale) {
    return SynchronousFuture<FeedbackLocalizations>(
      const AzFeedbackLocalizations(),
    );
  }
}

class BeFeedbackLocalizations extends FeedbackLocalizations {
  const BeFeedbackLocalizations();

  @override
  String get submitButtonText => 'Адправіць';

  @override
  String get feedbackDescriptionText => 'Што не так?';

  @override
  String get draw => 'Цягніць';

  @override
  String get navigate => 'Навігаваць';

  static Future<FeedbackLocalizations> load(Locale locale) {
    return SynchronousFuture<FeedbackLocalizations>(
      const BeFeedbackLocalizations(),
    );
  }
}

class BgFeedbackLocalizations extends FeedbackLocalizations {
  const BgFeedbackLocalizations();

  @override
  String get submitButtonText => 'Подаване на';

  @override
  String get feedbackDescriptionText => 'Какво можем да направим по-добре?';

  @override
  String get draw => 'Боядисване';

  @override
  String get navigate => 'Навигирайте в';

  static Future<FeedbackLocalizations> load(Locale locale) {
    return SynchronousFuture<FeedbackLocalizations>(
      const BgFeedbackLocalizations(),
    );
  }
}

class BnFeedbackLocalizations extends FeedbackLocalizations {
  const BnFeedbackLocalizations();

  @override
  String get submitButtonText => 'প্রেরণ';

  @override
  String get feedbackDescriptionText => 'আমরা আরও ভাল কি করতে পারি?';

  @override
  String get draw => 'রং করা';

  @override
  String get navigate => 'নেভিগেট করুন';

  static Future<FeedbackLocalizations> load(Locale locale) {
    return SynchronousFuture<FeedbackLocalizations>(
      const BnFeedbackLocalizations(),
    );
  }
}

class BoFeedbackLocalizations extends FeedbackLocalizations {
  const BoFeedbackLocalizations();

  static Future<FeedbackLocalizations> load(Locale locale) {
    return SynchronousFuture<FeedbackLocalizations>(
      const BoFeedbackLocalizations(),
    );
  }

  @override
  String get submitButtonText => 'སྤྲོད་པ';

  @override
  String get feedbackDescriptionText =>
      'རིན་ཐང་ཅན་གྱི་བསམ་ཚུལ་དང་བསམ་ཚུལ་འགོད་རོགས།';

  @override
  String get draw => 'རི་མོ་བྲིས་པ།';

  @override
  String get navigate => 'འགྲིམ་འགྲུལ།';
}

class BsFeedbackLocalizations extends FeedbackLocalizations {
  const BsFeedbackLocalizations();

  @override
  String get submitButtonText => 'Poslati';

  @override
  String get feedbackDescriptionText => 'Što možemo učiniti bolje?';

  @override
  String get draw => 'Obojati';

  @override
  String get navigate => 'Navigacija';

  static Future<FeedbackLocalizations> load(Locale locale) {
    return SynchronousFuture<FeedbackLocalizations>(
      const BsFeedbackLocalizations(),
    );
  }
}

class CaFeedbackLocalizations extends FeedbackLocalizations {
  const CaFeedbackLocalizations();

  @override
  String get submitButtonText => 'Enviar';

  @override
  String get feedbackDescriptionText => 'Què podem fer millor?';

  @override
  String get draw => 'Pintar';

  @override
  String get navigate => 'Navegar';

  static Future<FeedbackLocalizations> load(Locale locale) {
    return SynchronousFuture<FeedbackLocalizations>(
      const CaFeedbackLocalizations(),
    );
  }
}

class CsFeedbackLocalizations extends FeedbackLocalizations {
  const CsFeedbackLocalizations();

  @override
  String get submitButtonText => 'Předložit';

  @override
  String get feedbackDescriptionText =>
      'Zanechte prosím své cenné komentáře a návrhy:';

  @override
  String get draw => 'Kreslit';

  @override
  String get navigate => 'Navigovat';

  static Future<FeedbackLocalizations> load(Locale locale) {
    return SynchronousFuture<FeedbackLocalizations>(
      const CsFeedbackLocalizations(),
    );
  }
}

class DaFeedbackLocalizations extends FeedbackLocalizations {
  const DaFeedbackLocalizations();

  @override
  String get submitButtonText => 'Indsend';

  @override
  String get feedbackDescriptionText => 'Hvad kan vi gøre bedre?';

  @override
  String get draw => 'Maling';

  @override
  String get navigate => 'Navigere';

  static Future<FeedbackLocalizations> load(Locale locale) {
    return SynchronousFuture<FeedbackLocalizations>(
      const DaFeedbackLocalizations(),
    );
  }
}

class ElFeedbackLocalizations extends FeedbackLocalizations {
  const ElFeedbackLocalizations();

  @override
  String get submitButtonText => 'Υποβολή';

  @override
  String get feedbackDescriptionText => 'Τι μπορούμε να κάνουμε καλύτερα;';

  @override
  String get draw => 'Βαφή';

  @override
  String get navigate => 'Κυβερνώ';

  static Future<FeedbackLocalizations> load(Locale locale) {
    return SynchronousFuture<FeedbackLocalizations>(
      const ElFeedbackLocalizations(),
    );
  }
}

class EsFeedbackLocalizations extends FeedbackLocalizations {
  const EsFeedbackLocalizations();

  @override
  String get submitButtonText => 'Enviar';

  @override
  String get feedbackDescriptionText => '¿Qué podemos hacer mejor?';

  @override
  String get draw => 'Dibujar';

  @override
  String get navigate => 'Navegar';

  static Future<FeedbackLocalizations> load(Locale locale) {
    return SynchronousFuture<FeedbackLocalizations>(
      const EsFeedbackLocalizations(),
    );
  }
}

class EtFeedbackLocalizations extends FeedbackLocalizations {
  const EtFeedbackLocalizations();

  @override
  String get submitButtonText => 'Esita';

  @override
  String get feedbackDescriptionText => 'Mida me saame paremini teha?';

  @override
  String get draw => 'Värvi';

  @override
  String get navigate => 'Navigeeri';

  static Future<FeedbackLocalizations> load(Locale locale) {
    return SynchronousFuture<FeedbackLocalizations>(
      const EtFeedbackLocalizations(),
    );
  }
}

class FaFeedbackLocalizations extends FeedbackLocalizations {
  const FaFeedbackLocalizations();

  @override
  String get submitButtonText => 'ارسال';

  @override
  String get feedbackDescriptionText => 'چه کار بهتری میتوانیم انجام دهیم؟';

  @override
  String get draw => 'نقاشی';

  @override
  String get navigate => 'پیمایش کنید';

  static Future<FeedbackLocalizations> load(Locale locale) {
    return SynchronousFuture<FeedbackLocalizations>(
      const FaFeedbackLocalizations(),
    );
  }
}

class FiFeedbackLocalizations extends FeedbackLocalizations {
  const FiFeedbackLocalizations();

  @override
  String get submitButtonText => 'Lähettää';

  @override
  String get feedbackDescriptionText => 'Mitä voimme tehdä paremmin?';

  @override
  String get draw => 'Maalata';

  @override
  String get navigate => 'Navigoida';

  static Future<FeedbackLocalizations> load(Locale locale) {
    return SynchronousFuture<FeedbackLocalizations>(
      const FiFeedbackLocalizations(),
    );
  }
}

class GuFeedbackLocalizations extends FeedbackLocalizations {
  const GuFeedbackLocalizations();

  @override
  String get submitButtonText => 'મોકલો';

  @override
  String get feedbackDescriptionText => 'આપણે વધુ સારું શું કરી શકીએ?';

  @override
  String get draw => 'કલર કરવો';

  @override
  String get navigate => 'નેવિગેટ કરો';

  static Future<FeedbackLocalizations> load(Locale locale) {
    return SynchronousFuture<FeedbackLocalizations>(
      const GuFeedbackLocalizations(),
    );
  }
}

class HeFeedbackLocalizations extends FeedbackLocalizations {
  const HeFeedbackLocalizations();

  @override
  String get submitButtonText => 'שלח';

  @override
  String get feedbackDescriptionText => 'מה לא בסדר?';

  @override
  String get draw => 'צייר';

  @override
  String get navigate => 'נווט';

  static Future<FeedbackLocalizations> load(Locale locale) {
    return SynchronousFuture<FeedbackLocalizations>(
      const HeFeedbackLocalizations(),
    );
  }
}

class HiFeedbackLocalizations extends FeedbackLocalizations {
  const HiFeedbackLocalizations();

  @override
  String get submitButtonText => 'प्रस्तुत';

  @override
  String get feedbackDescriptionText => 'हम बेहतर क्या कर सकते हैं?';

  @override
  String get draw => 'पेंट करने के लिए';

  @override
  String get navigate => 'नेविगेट';

  static Future<FeedbackLocalizations> load(Locale locale) {
    return SynchronousFuture<FeedbackLocalizations>(
      const HiFeedbackLocalizations(),
    );
  }
}

class HrFeedbackLocalizations extends FeedbackLocalizations {
  const HrFeedbackLocalizations();

  @override
  String get submitButtonText => 'Poslati';

  @override
  String get feedbackDescriptionText => 'Što možemo učiniti bolje?';

  @override
  String get draw => 'Obojati';

  @override
  String get navigate => 'Navigacija';

  static Future<FeedbackLocalizations> load(Locale locale) {
    return SynchronousFuture<FeedbackLocalizations>(
      const HrFeedbackLocalizations(),
    );
  }
}

class HuFeedbackLocalizations extends FeedbackLocalizations {
  const HuFeedbackLocalizations();

  @override
  String get submitButtonText => 'Küld';

  @override
  String get feedbackDescriptionText => 'Mit tehetnénk jobban?';

  @override
  String get draw => 'Húz';

  @override
  String get navigate => 'Hajózik';

  static Future<FeedbackLocalizations> load(Locale locale) {
    return SynchronousFuture<FeedbackLocalizations>(
      const HuFeedbackLocalizations(),
    );
  }
}

class HyFeedbackLocalizations extends FeedbackLocalizations {
  const HyFeedbackLocalizations();

  @override
  String get submitButtonText => 'Ներկայացնել';

  @override
  String get feedbackDescriptionText => 'Ի՞նչ է սխալ։';

  @override
  String get draw => 'Նկարել';

  @override
  String get navigate => 'Ցույցադրել';

  static Future<FeedbackLocalizations> load(Locale locale) {
    return SynchronousFuture<FeedbackLocalizations>(
      const HyFeedbackLocalizations(),
    );
  }
}

class IdFeedbackLocalizations extends FeedbackLocalizations {
  const IdFeedbackLocalizations();

  @override
  String get submitButtonText => 'Kirim';

  @override
  String get feedbackDescriptionText =>
      'Apa yang bisa kita lakukan lebih baik?';

  @override
  String get draw => 'Melukis';

  @override
  String get navigate => 'Navigasi';

  static Future<FeedbackLocalizations> load(Locale locale) {
    return SynchronousFuture<FeedbackLocalizations>(
      const IdFeedbackLocalizations(),
    );
  }
}

class IsFeedbackLocalizations extends FeedbackLocalizations {
  const IsFeedbackLocalizations();

  @override
  String get submitButtonText => 'Leggja fram';

  @override
  String get feedbackDescriptionText => 'Hvað er rangt?';

  @override
  String get draw => 'Teikna';

  @override
  String get navigate => 'Stjórna';

  static Future<FeedbackLocalizations> load(Locale locale) {
    return SynchronousFuture<FeedbackLocalizations>(
      const IsFeedbackLocalizations(),
    );
  }
}

class ItFeedbackLocalizations extends FeedbackLocalizations {
  const ItFeedbackLocalizations();

  @override
  String get submitButtonText => 'Spedire';

  @override
  String get feedbackDescriptionText => 'Cosa possiamo fare di meglio?';

  @override
  String get draw => 'Dipingere';

  @override
  String get navigate => 'Navigare';

  static Future<FeedbackLocalizations> load(Locale locale) {
    return SynchronousFuture<FeedbackLocalizations>(
      const ItFeedbackLocalizations(),
    );
  }
}

class JaFeedbackLocalizations extends FeedbackLocalizations {
  const JaFeedbackLocalizations();

  static Future<FeedbackLocalizations> load(Locale locale) {
    return SynchronousFuture<FeedbackLocalizations>(
      const JaFeedbackLocalizations(),
    );
  }

  @override
  String get submitButtonText => '提交';

  @override
  String get feedbackDescriptionText => '貴重なご意見やご感想をお寄せください：';

  @override
  String get draw => '落書き';

  @override
  String get navigate => 'ナビゲーター';
}

class KmFeedbackLocalizations implements FeedbackLocalizations {
  const KmFeedbackLocalizations();

  @override
  String get submitButtonText => 'បញ្ជូន';

  @override
  String get feedbackDescriptionText => 'តើ​មាន​បញ្ហា​អ្វី?';

  @override
  String get draw => 'គូរ';

  @override
  String get navigate => 'នាំផ្លូវ';

  static Future<FeedbackLocalizations> load(Locale locale) {
    return SynchronousFuture<FeedbackLocalizations>(
      const KmFeedbackLocalizations(),
    );
  }
}

class KnFeedbackLocalizations extends FeedbackLocalizations {
  const KnFeedbackLocalizations();

  @override
  String get submitButtonText => 'ಸಲ್ಲಿಸಿ';

  @override
  String get feedbackDescriptionText => 'ಏನು ತಪ್ಪು?';

  @override
  String get draw => 'ಗೀಚು';

  @override
  String get navigate => 'ಸಂಚಾರ';

  static Future<FeedbackLocalizations> load(Locale locale) {
    return SynchronousFuture<FeedbackLocalizations>(
      const KnFeedbackLocalizations(),
    );
  }
}

class KoFeedbackLocalizations extends FeedbackLocalizations {
  const KoFeedbackLocalizations();

  static Future<FeedbackLocalizations> load(Locale locale) {
    return SynchronousFuture<FeedbackLocalizations>(
      const KoFeedbackLocalizations(),
    );
  }

  @override
  String get submitButtonText => '제출';

  @override
  String get feedbackDescriptionText => '소중한 의견과 제안을 남겨주세요:';

  @override
  String get draw => '낙서';

  @override
  String get navigate => '항해';
}

class LtFeedbackLocalizations extends FeedbackLocalizations {
  const LtFeedbackLocalizations();

  @override
  String get submitButtonText => 'Pateikti';

  @override
  String get feedbackDescriptionText => 'Ką galime padaryti geriau?';

  @override
  String get draw => 'Dažai';

  @override
  String get navigate => 'Naršykite';

  static Future<FeedbackLocalizations> load(Locale locale) {
    return SynchronousFuture<FeedbackLocalizations>(
      const LtFeedbackLocalizations(),
    );
  }
}

class LvFeedbackLocalizations extends FeedbackLocalizations {
  const LvFeedbackLocalizations();

  @override
  String get submitButtonText => 'Iesniegt';

  @override
  String get feedbackDescriptionText => 'Ko mēs varam darīt labāk?';

  @override
  String get draw => 'Krāsa';

  @override
  String get navigate => 'Pārvietoties';

  static Future<FeedbackLocalizations> load(Locale locale) {
    return SynchronousFuture<FeedbackLocalizations>(
      const LvFeedbackLocalizations(),
    );
  }
}

class MkFeedbackLocalizations extends FeedbackLocalizations {
  const MkFeedbackLocalizations();

  @override
  String get submitButtonText => 'Испрати';

  @override
  String get feedbackDescriptionText => 'Што можеме да направиме подобро?';

  @override
  String get draw => 'Да слика';

  @override
  String get navigate => 'Навигација';

  static Future<FeedbackLocalizations> load(Locale locale) {
    return SynchronousFuture<FeedbackLocalizations>(
      const MkFeedbackLocalizations(),
    );
  }
}

class MsFeedbackLocalizations extends FeedbackLocalizations {
  const MsFeedbackLocalizations();

  @override
  String get submitButtonText => 'Hantar';

  @override
  String get feedbackDescriptionText =>
      'Apa yang boleh kita lakukan dengan lebih baik?';

  @override
  String get draw => 'Mengecat';

  @override
  String get navigate => 'Navigasi';

  static Future<FeedbackLocalizations> load(Locale locale) {
    return SynchronousFuture<FeedbackLocalizations>(
      const MsFeedbackLocalizations(),
    );
  }
}

class MyFeedbackLocalizations extends FeedbackLocalizations {
  const MyFeedbackLocalizations();

  @override
  String get submitButtonText => 'တင်သွင်းပါ';

  @override
  String get feedbackDescriptionText => 'ဘာဖြစ်နေသလဲ?';

  @override
  String get draw => 'ဆွဲပါ';

  @override
  String get navigate => 'လမ်းညွှန်ပါ';

  static Future<FeedbackLocalizations> load(Locale locale) {
    return SynchronousFuture<FeedbackLocalizations>(
      const MyFeedbackLocalizations(),
    );
  }
}

class NlFeedbackLocalizations extends FeedbackLocalizations {
  const NlFeedbackLocalizations();

  @override
  String get submitButtonText => 'Indienen';

  @override
  String get feedbackDescriptionText => 'Wat kunnen we beter doen?';

  @override
  String get draw => 'Verf';

  @override
  String get navigate => 'Navigeren';

  static Future<FeedbackLocalizations> load(Locale locale) {
    return SynchronousFuture<FeedbackLocalizations>(
      const NlFeedbackLocalizations(),
    );
  }
}

class NbFeedbackLocalizations extends FeedbackLocalizations {
  const NbFeedbackLocalizations();

  @override
  String get submitButtonText => 'Send inn';

  @override
  String get feedbackDescriptionText => 'Hva er galt?';

  @override
  String get draw => 'Tegne';

  @override
  String get navigate => 'Navigere';

  static Future<FeedbackLocalizations> load(Locale locale) {
    return SynchronousFuture<FeedbackLocalizations>(
      const NbFeedbackLocalizations(),
    );
  }
}

class PlFeedbackLocalizations extends FeedbackLocalizations {
  const PlFeedbackLocalizations();

  @override
  String get submitButtonText => 'Wysłać';

  @override
  String get feedbackDescriptionText => 'Co możemy zrobić lepiej?';

  @override
  String get draw => 'Malować';

  @override
  String get navigate => 'Nawigować';

  static Future<FeedbackLocalizations> load(Locale locale) {
    return SynchronousFuture<FeedbackLocalizations>(
      const PlFeedbackLocalizations(),
    );
  }
}

class PtFeedbackLocalizations extends FeedbackLocalizations {
  const PtFeedbackLocalizations();

  static Future<FeedbackLocalizations> load(Locale locale) {
    return SynchronousFuture<FeedbackLocalizations>(
      const PtFeedbackLocalizations(),
    );
  }

  @override
  String get submitButtonText => 'Enviar';

  @override
  String get feedbackDescriptionText =>
      'Deixe seus valiosos comentários e sugestões:';

  @override
  String get draw => 'Desenhar';

  @override
  String get navigate => 'Navegar';
}

class RoFeedbackLocalizations extends FeedbackLocalizations {
  const RoFeedbackLocalizations();

  static Future<FeedbackLocalizations> load(Locale locale) {
    return SynchronousFuture<FeedbackLocalizations>(
      const RoFeedbackLocalizations(),
    );
  }

  @override
  String get submitButtonText => 'Trimite';

  @override
  String get feedbackDescriptionText =>
      'Vă rugăm să lăsați comentariile și sugestiile voastre valoroase:';

  @override
  String get draw => 'Desena';

  @override
  String get navigate => 'Navigare';
}

class RuFeedbackLocalizations extends FeedbackLocalizations {
  const RuFeedbackLocalizations();

  static Future<FeedbackLocalizations> load(Locale locale) {
    return SynchronousFuture<FeedbackLocalizations>(
      const RuFeedbackLocalizations(),
    );
  }

  @override
  String get submitButtonText => 'Отправить';

  @override
  String get feedbackDescriptionText => 'Опишите проблему';

  @override
  String get draw => 'Рисование';

  @override
  String get navigate => 'Навигация';
}

class SiFeedbackLocalizations extends FeedbackLocalizations {
  const SiFeedbackLocalizations();

  static Future<FeedbackLocalizations> load(Locale locale) {
    return SynchronousFuture<FeedbackLocalizations>(
      const SiFeedbackLocalizations(),
    );
  }

  @override
  String get submitButtonText => 'යොමු කරන්න';

  @override
  String get feedbackDescriptionText => 'ඔබේ ගැටළුව විස්තර කරන්න';

  @override
  String get draw => 'අඳින්න';

  @override
  String get navigate => 'ගමන් කරන්න';
}

class SkFeedbackLocalizations extends FeedbackLocalizations {
  const SkFeedbackLocalizations();

  @override
  String get submitButtonText => 'Odoslať';

  @override
  String get feedbackDescriptionText => 'Čo môžeme urobiť lepšie?';

  @override
  String get draw => 'Farba';

  @override
  String get navigate => 'Navigovať';

  static Future<FeedbackLocalizations> load(Locale locale) {
    return SynchronousFuture<FeedbackLocalizations>(
      const SkFeedbackLocalizations(),
    );
  }
}

class SlFeedbackLocalizations extends FeedbackLocalizations {
  const SlFeedbackLocalizations();

  @override
  String get submitButtonText => 'Pošlji';

  @override
  String get feedbackDescriptionText => 'Kaj lahko naredimo bolje?';

  @override
  String get draw => 'Barva';

  @override
  String get navigate => 'Krmarite';

  static Future<FeedbackLocalizations> load(Locale locale) {
    return SynchronousFuture<FeedbackLocalizations>(
      const SlFeedbackLocalizations(),
    );
  }
}

class SqFeedbackLocalizations extends FeedbackLocalizations {
  const SqFeedbackLocalizations();

  @override
  String get submitButtonText => 'Dërgoni';

  @override
  String get feedbackDescriptionText => 'Çfarë mund të bëjmë më mirë?';

  @override
  String get draw => 'Vizato';

  @override
  String get navigate => 'Lundro';

  static Future<FeedbackLocalizations> load(Locale locale) {
    return SynchronousFuture<FeedbackLocalizations>(
      const SqFeedbackLocalizations(),
    );
  }
}

class SrFeedbackLocalizations extends FeedbackLocalizations {
  const SrFeedbackLocalizations();

  @override
  String get submitButtonText => 'Пошаљите';

  @override
  String get feedbackDescriptionText => 'Шта можемо учинити боље?';

  @override
  String get draw => 'Обојити';

  @override
  String get navigate => 'Навигација';

  static Future<FeedbackLocalizations> load(Locale locale) {
    return SynchronousFuture<FeedbackLocalizations>(
      const SrFeedbackLocalizations(),
    );
  }
}

class SvFeedbackLocalizations extends FeedbackLocalizations {
  const SvFeedbackLocalizations();

  @override
  String get submitButtonText => 'Skicka';

  @override
  String get feedbackDescriptionText => 'Vad kan vi göra bättre?';

  @override
  String get draw => 'Färg';

  @override
  String get navigate => 'Navigera';

  static Future<FeedbackLocalizations> load(Locale locale) {
    return SynchronousFuture<FeedbackLocalizations>(
      const SvFeedbackLocalizations(),
    );
  }
}

class SwFeedbackLocalizations extends FeedbackLocalizations {
  const SwFeedbackLocalizations();

  @override
  String get submitButtonText => 'Tuma';

  @override
  String get feedbackDescriptionText => 'Nini kibaya?';

  @override
  String get draw => 'Chora';

  @override
  String get navigate => 'Elekeza';

  static Future<FeedbackLocalizations> load(Locale locale) {
    return SynchronousFuture<FeedbackLocalizations>(
      const SwFeedbackLocalizations(),
    );
  }
}

// Tamil
class TaFeedbackLocalizations extends FeedbackLocalizations {
  const TaFeedbackLocalizations();

  @override
  String get submitButtonText => 'அனுப்பு';

  @override
  String get feedbackDescriptionText => 'என்ன தவறு?';

  @override
  String get draw => 'வரையுங்கள்';

  @override
  String get navigate => 'நாவிருந்து';

  static Future<FeedbackLocalizations> load(Locale locale) {
    return SynchronousFuture<FeedbackLocalizations>(
      const TaFeedbackLocalizations(),
    );
  }
}

class TeFeedbackLocalizations extends FeedbackLocalizations {
  const TeFeedbackLocalizations();

  @override
  String get submitButtonText => 'పంపండి';

  @override
  String get feedbackDescriptionText => 'మనం బాగా ఏమి చేయగలం?';

  @override
  String get draw => 'అద్దుటకై';

  @override
  String get navigate => 'నావిగేషన్';

  static Future<FeedbackLocalizations> load(Locale locale) {
    return SynchronousFuture<FeedbackLocalizations>(
      const TeFeedbackLocalizations(),
    );
  }
}

class ThFeedbackLocalizations extends FeedbackLocalizations {
  const ThFeedbackLocalizations();

  @override
  String get submitButtonText => 'ส่ง';

  @override
  String get feedbackDescriptionText => 'เราจะทำอะไรได้ดีกว่านี้?';

  @override
  String get draw => 'ทาสี';

  @override
  String get navigate => 'นำทาง';

  static Future<FeedbackLocalizations> load(Locale locale) {
    return SynchronousFuture<FeedbackLocalizations>(
      const ThFeedbackLocalizations(),
    );
  }
}

class TrFeedbackLocalizations extends FeedbackLocalizations {
  const TrFeedbackLocalizations();

  @override
  String get submitButtonText => 'gönder';

  @override
  String get feedbackDescriptionText => 'Neyi daha iyi yapabiliriz?';

  @override
  String get draw => 'boyamak';

  @override
  String get navigate => 'Gezin';

  static Future<FeedbackLocalizations> load(Locale locale) {
    return SynchronousFuture<FeedbackLocalizations>(
      const TrFeedbackLocalizations(),
    );
  }
}

class UkFeedbackLocalizations extends FeedbackLocalizations {
  const UkFeedbackLocalizations();

  static Future<FeedbackLocalizations> load(Locale locale) {
    return SynchronousFuture<FeedbackLocalizations>(
      const UkFeedbackLocalizations(),
    );
  }

  @override
  String get submitButtonText => 'Відправити';

  @override
  String get feedbackDescriptionText => 'Опишіть проблему';

  @override
  String get draw => 'Малювання';

  @override
  String get navigate => 'Навігація';
}

class UrFeedbackLocalizations extends FeedbackLocalizations {
  const UrFeedbackLocalizations();

  @override
  String get submitButtonText => 'جمع کرائیں';

  @override
  String get feedbackDescriptionText => 'کیا خراب ہے؟';

  @override
  String get draw => 'ڈرا';

  @override
  String get navigate => 'رہنمائی کریں';

  static Future<FeedbackLocalizations> load(Locale locale) {
    return SynchronousFuture<FeedbackLocalizations>(
      const UrFeedbackLocalizations(),
    );
  }
}

class UzFeedbackLocalizations extends FeedbackLocalizations {
  const UzFeedbackLocalizations();

  @override
  String get submitButtonText => 'Yuborish';

  @override
  String get feedbackDescriptionText => "Nima noto'g'ri?";

  @override
  String get draw => 'Chizmoq';

  @override
  String get navigate => "Yo'l hidi";

  static Future<FeedbackLocalizations> load(Locale locale) {
    return SynchronousFuture<FeedbackLocalizations>(
      const UzFeedbackLocalizations(),
    );
  }
}

class ViFeedbackLocalizations extends FeedbackLocalizations {
  const ViFeedbackLocalizations();

  @override
  String get submitButtonText => 'Gửi đi';

  @override
  String get feedbackDescriptionText => 'Có gì không ổn?';

  @override
  String get draw => 'Vẽ';

  @override
  String get navigate => 'Điều hướng';

  static Future<FeedbackLocalizations> load(Locale locale) {
    return SynchronousFuture<FeedbackLocalizations>(
      const ViFeedbackLocalizations(),
    );
  }
}

class ZhFeedbackLocalizations extends FeedbackLocalizations {
  const ZhFeedbackLocalizations();

  static Future<FeedbackLocalizations> load(Locale locale) {
    return SynchronousFuture<FeedbackLocalizations>(
      const ZhFeedbackLocalizations(),
    );
  }

  @override
  String get submitButtonText => '提交';

  @override
  String get feedbackDescriptionText => '敬请留下您宝贵的意见和建议：';

  @override
  String get draw => '涂鸦';

  @override
  String get navigate => '导航';
}

class ZuFeedbackLocalizations extends FeedbackLocalizations {
  const ZuFeedbackLocalizations();

  @override
  String get submitButtonText => 'Thumela'; // 'Submit' in Zulu

  @override
  String get feedbackDescriptionText =>
      'Kuyini okungalungile?'; // 'What's wrong?' in Zulu

  @override
  String get draw => 'Thinta'; // 'Draw' in Zulu

  @override
  String get navigate => 'Hamba'; // 'Navigate' in Zulu

  static Future<FeedbackLocalizations> load(Locale locale) {
    return SynchronousFuture<FeedbackLocalizations>(
      const ZuFeedbackLocalizations(),
    );
  }
}
