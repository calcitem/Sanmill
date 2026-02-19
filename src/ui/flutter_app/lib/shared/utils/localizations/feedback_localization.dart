// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// feedback_localization.dart

import 'package:feedback/feedback.dart';
import 'package:flutter/material.dart';

import '../../services/logger.dart';

/// A data-driven implementation of feedback localizations.
/// This implementation uses a centralized translation map instead of individual classes.
class CustomFeedbackLocalizations extends FeedbackLocalizations {
  /// Creates a [CustomFeedbackLocalizations] with the given translations.
  const CustomFeedbackLocalizations(this._localizedValues);

  /// The localized strings for this instance
  final Map<String, String> _localizedValues;

  @override
  String get submitButtonText => _localizedValues['submitButtonText']!;

  @override
  String get feedbackDescriptionText =>
      _localizedValues['feedbackDescriptionText']!;

  @override
  String get draw => _localizedValues['draw']!;

  @override
  String get navigate => _localizedValues['navigate']!;
}

/// This is a localization delegate, which includes all of the localizations
/// already present in this library.
class CustomFeedbackLocalizationsDelegate
    extends LocalizationsDelegate<FeedbackLocalizations> {
  /// Creates a [CustomFeedbackLocalizationsDelegate].
  const CustomFeedbackLocalizationsDelegate();

  /// Returns the default instance of a [CustomFeedbackLocalizationsDelegate].
  static const CustomFeedbackLocalizationsDelegate delegate =
      CustomFeedbackLocalizationsDelegate();

  /// Translation data for all supported languages
  static const Map<String, Map<String, String>>
  _translations = <String, Map<String, String>>{
    'af': <String, String>{
      // Afrikaans
      'submitButtonText': 'Indien',
      'feedbackDescriptionText': 'Wat is verkeerd?',
      'draw': 'Teken',
      'navigate': 'Navigeer',
    },
    'am': <String, String>{
      // Amharic
      'submitButtonText': 'አስገባ',
      'feedbackDescriptionText': 'ምን ተሳስቷል?',
      'draw': 'ማሟያ',
      'navigate': 'መራ',
    },
    'ar': <String, String>{
      // Arabic
      'submitButtonText': 'إرسال',
      'feedbackDescriptionText': 'ما الذي يمكننا فعله بشكل أفضل؟',
      'draw': 'رسم',
      'navigate': 'التنقل',
    },
    'az': <String, String>{
      // Azerbaijani
      'submitButtonText': 'Göndər',
      'feedbackDescriptionText': 'Nə yalnışdır?',
      'draw': 'Çək',
      'navigate': 'Naviqasiya et',
    },
    'be': <String, String>{
      // Belarusian
      'submitButtonText': 'Адправіць',
      'feedbackDescriptionText': 'Што не так?',
      'draw': 'Цягніць',
      'navigate': 'Навігаваць',
    },
    'bg': <String, String>{
      // Bulgarian
      'submitButtonText': 'Подаване на',
      'feedbackDescriptionText': 'Какво можем да направим по-добре?',
      'draw': 'Боядисване',
      'navigate': 'Навигирайте в',
    },
    'bn': <String, String>{
      // Bengali
      'submitButtonText': 'প্রেরণ',
      'feedbackDescriptionText': 'আমরা আরও ভাল কি করতে পারি?',
      'draw': 'রং করা',
      'navigate': 'নেভিগেট করুন',
    },
    'bo': <String, String>{
      // Tibetan
      'submitButtonText': 'སྤྲོད་པ',
      'feedbackDescriptionText': 'རིན་ཐང་ཅན་གྱི་བསམ་ཚུལ་དང་བསམ་ཚུལ་འགོད་རོགས།',
      'draw': 'རི་མོ་བྲིས་པ།',
      'navigate': 'འགྲིམ་འགྲུལ།',
    },
    'bs': <String, String>{
      // Bosnian
      'submitButtonText': 'Poslati',
      'feedbackDescriptionText': 'Što možemo učiniti bolje?',
      'draw': 'Obojati',
      'navigate': 'Navigacija',
    },
    'ca': <String, String>{
      // Catalan
      'submitButtonText': 'Enviar',
      'feedbackDescriptionText': 'Què podem fer millor?',
      'draw': 'Pintar',
      'navigate': 'Navegar',
    },
    'cs': <String, String>{
      // Czech
      'submitButtonText': 'Předložit',
      'feedbackDescriptionText':
          'Zanechte prosím své cenné komentáře a návrhy:',
      'draw': 'Kreslit',
      'navigate': 'Navigovat',
    },
    'da': <String, String>{
      // Danish
      'submitButtonText': 'Indsend',
      'feedbackDescriptionText': 'Hvad kan vi gøre bedre?',
      'draw': 'Maling',
      'navigate': 'Navigere',
    },
    'de': <String, String>{
      // German
      'submitButtonText': 'Senden',
      'feedbackDescriptionText': 'Was können wir besser machen?',
      'draw': 'Zeichnen',
      'navigate': 'Navigate',
    },
    'el': <String, String>{
      // Greek
      'submitButtonText': 'Υποβολή',
      'feedbackDescriptionText': 'Τι μπορούμε να κάνουμε καλύτερα;',
      'draw': 'Βαφή',
      'navigate': 'Κυβερνώ',
    },
    'en': <String, String>{
      // English
      'submitButtonText': 'Submit',
      'feedbackDescriptionText': "What's wrong?",
      'draw': 'Draw',
      'navigate': 'Navigate',
    },
    'es': <String, String>{
      // Spanish
      'submitButtonText': 'Enviar',
      'feedbackDescriptionText': '¿Qué podemos hacer mejor?',
      'draw': 'Dibujar',
      'navigate': 'Navegar',
    },
    'et': <String, String>{
      // Estonian
      'submitButtonText': 'Esita',
      'feedbackDescriptionText': 'Mida me saame paremini teha?',
      'draw': 'Värvi',
      'navigate': 'Navigeeri',
    },
    'fa': <String, String>{
      // Persian (Farsi)
      'submitButtonText': 'ارسال',
      'feedbackDescriptionText': 'چه کار بهتری میتوانیم انجام دهیم؟',
      'draw': 'نقاشی',
      'navigate': 'پیمایش کنید',
    },
    'fi': <String, String>{
      // Finnish
      'submitButtonText': 'Lähettää',
      'feedbackDescriptionText': 'Mitä voimme tehdä paremmin?',
      'draw': 'Maalata',
      'navigate': 'Navigoida',
    },
    'fr': <String, String>{
      // French
      'submitButtonText': 'Envoyer',
      'feedbackDescriptionText': 'Que pouvons-nous faire de mieux?',
      'draw': 'Dessiner',
      'navigate': 'Naviguer',
    },
    'gu': <String, String>{
      // Gujarati
      'submitButtonText': 'મોકલો',
      'feedbackDescriptionText': 'આપણે વધુ સારું શું કરી શકીએ?',
      'draw': 'કલર કરવો',
      'navigate': 'નેવિગેટ કરો',
    },
    'he': <String, String>{
      // Hebrew
      'submitButtonText': 'שלח',
      'feedbackDescriptionText': 'מה לא בסדר?',
      'draw': 'צייר',
      'navigate': 'נווט',
    },
    'hi': <String, String>{
      // Hindi
      'submitButtonText': 'प्रस्तुत',
      'feedbackDescriptionText': 'हम बेहतर क्या कर सकते हैं?',
      'draw': 'पेंट करने के लिए',
      'navigate': 'नेविगेट',
    },
    'hr': <String, String>{
      // Croatian
      'submitButtonText': 'Poslati',
      'feedbackDescriptionText': 'Što možemo učiniti bolje?',
      'draw': 'Obojati',
      'navigate': 'Navigacija',
    },
    'hu': <String, String>{
      // Hungarian
      'submitButtonText': 'Küld',
      'feedbackDescriptionText': 'Mit tehetnénk jobban?',
      'draw': 'Húz',
      'navigate': 'Hajózik',
    },
    'hy': <String, String>{
      // Armenian
      'submitButtonText': 'Ներկայացնել',
      'feedbackDescriptionText': 'Ի՞նչ է սխալ։',
      'draw': 'Նկարել',
      'navigate': 'Ցույցադրել',
    },
    'id': <String, String>{
      // Indonesian
      'submitButtonText': 'Kirim',
      'feedbackDescriptionText': 'Apa yang bisa kita lakukan lebih baik?',
      'draw': 'Melukis',
      'navigate': 'Navigasi',
    },
    'is': <String, String>{
      // Icelandic
      'submitButtonText': 'Leggja fram',
      'feedbackDescriptionText': 'Hvað er rangt?',
      'draw': 'Teikna',
      'navigate': 'Stjórna',
    },
    'it': <String, String>{
      // Italian
      'submitButtonText': 'Spedire',
      'feedbackDescriptionText': 'Cosa possiamo fare di meglio?',
      'draw': 'Dipingere',
      'navigate': 'Navigare',
    },
    'ja': <String, String>{
      // Japanese
      'submitButtonText': '提交',
      'feedbackDescriptionText': '貴重なご意見やご感想をお寄せください：',
      'draw': '落書き',
      'navigate': 'ナビゲーター',
    },
    'km': <String, String>{
      // Khmer
      'submitButtonText': 'បញ្ជូន',
      'feedbackDescriptionText': 'តើ​មាន​បញ្ហា​អ្វី?',
      'draw': 'គូរ',
      'navigate': 'នាំផ្លូវ',
    },
    'kn': <String, String>{
      // Kannada
      'submitButtonText': 'ಸಲ್ಲಿಸಿ',
      'feedbackDescriptionText': 'ಏನು ತಪ್ಪು?',
      'draw': 'ಗೀಚು',
      'navigate': 'ಸಂಚಾರ',
    },
    'ko': <String, String>{
      // Korean
      'submitButtonText': '제출',
      'feedbackDescriptionText': '소중한 의견과 제안을 남겨주세요:',
      'draw': '낙서',
      'navigate': '항해',
    },
    'lt': <String, String>{
      // Lithuanian
      'submitButtonText': 'Pateikti',
      'feedbackDescriptionText': 'Ką galime padaryti geriau?',
      'draw': 'Dažai',
      'navigate': 'Naršykite',
    },
    'lv': <String, String>{
      // Latvian
      'submitButtonText': 'Iesniegt',
      'feedbackDescriptionText': 'Ko mēs varam darīt labāk?',
      'draw': 'Krāsa',
      'navigate': 'Pārvietoties',
    },
    'mk': <String, String>{
      // Macedonian
      'submitButtonText': 'Испрати',
      'feedbackDescriptionText': 'Што можеме да направиме подобро?',
      'draw': 'Да слика',
      'navigate': 'Навигација',
    },
    'ms': <String, String>{
      // Malay
      'submitButtonText': 'Hantar',
      'feedbackDescriptionText':
          'Apa yang boleh kita lakukan dengan lebih baik?',
      'draw': 'Mengecat',
      'navigate': 'Navigasi',
    },
    'my': <String, String>{
      // Burmese
      'submitButtonText': 'တင်သွင်းပါ',
      'feedbackDescriptionText': 'ဘာဖြစ်နေသလဲ?',
      'draw': 'ဆွဲပါ',
      'navigate': 'လမ်းညွှန်ပါ',
    },
    'nb': <String, String>{
      // Norwegian
      'submitButtonText': 'Send inn',
      'feedbackDescriptionText': 'Hva er galt?',
      'draw': 'Tegne',
      'navigate': 'Navigere',
    },
    'nl': <String, String>{
      // Dutch
      'submitButtonText': 'Indienen',
      'feedbackDescriptionText': 'Wat kunnen we beter doen?',
      'draw': 'Verf',
      'navigate': 'Navigeren',
    },
    'pl': <String, String>{
      // Polish
      'submitButtonText': 'Wysłać',
      'feedbackDescriptionText': 'Co możemy zrobić lepiej?',
      'draw': 'Malować',
      'navigate': 'Nawigować',
    },
    'pt': <String, String>{
      // Portuguese
      'submitButtonText': 'Enviar',
      'feedbackDescriptionText': 'Deixe seus valiosos comentários e sugestões:',
      'draw': 'Desenhar',
      'navigate': 'Navegar',
    },
    'ro': <String, String>{
      // Romanian
      'submitButtonText': 'Trimite',
      'feedbackDescriptionText':
          'Vă rugăm să lăsați comentariile și sugestiile voastre valoroase:',
      'draw': 'Desena',
      'navigate': 'Navigare',
    },
    'ru': <String, String>{
      // Russian
      'submitButtonText': 'Отправить',
      'feedbackDescriptionText': 'Опишите проблему',
      'draw': 'Рисование',
      'navigate': 'Навигация',
    },
    'si': <String, String>{
      // Sinhala
      'submitButtonText': 'යොමු කරන්න',
      'feedbackDescriptionText': 'ඔබේ ගැටළුව විස්තර කරන්න',
      'draw': 'අඳින්න',
      'navigate': 'ගමන් කරන්න',
    },
    'sk': <String, String>{
      // Slovak
      'submitButtonText': 'Odoslať',
      'feedbackDescriptionText': 'Čo môžeme urobiť lepšie?',
      'draw': 'Farba',
      'navigate': 'Navigovať',
    },
    'sl': <String, String>{
      // Slovenian
      'submitButtonText': 'Pošlji',
      'feedbackDescriptionText': 'Kaj lahko naredimo bolje?',
      'draw': 'Barva',
      'navigate': 'Krmarite',
    },
    'sq': <String, String>{
      // Albanian
      'submitButtonText': 'Dërgoni',
      'feedbackDescriptionText': 'Çfarë mund të bëjmë më mirë?',
      'draw': 'Vizato',
      'navigate': 'Lundro',
    },
    'sr': <String, String>{
      // Serbian
      'submitButtonText': 'Пошаљите',
      'feedbackDescriptionText': 'Шта можемо учинити боље?',
      'draw': 'Обојити',
      'navigate': 'Навигација',
    },
    'sv': <String, String>{
      // Swedish
      'submitButtonText': 'Skicka',
      'feedbackDescriptionText': 'Vad kan vi göra bättre?',
      'draw': 'Färg',
      'navigate': 'Navigera',
    },
    'sw': <String, String>{
      // Swahili
      'submitButtonText': 'Tuma',
      'feedbackDescriptionText': 'Nini kibaya?',
      'draw': 'Chora',
      'navigate': 'Elekeza',
    },
    'ta': <String, String>{
      // Tamil
      'submitButtonText': 'அனுப்பு',
      'feedbackDescriptionText': 'என்ன தவறு?',
      'draw': 'வரையுங்கள்',
      'navigate': 'நாவிருந்து',
    },
    'te': <String, String>{
      // Telugu
      'submitButtonText': 'పంపండి',
      'feedbackDescriptionText': 'మనం బాగా ఏమి చేయగలం?',
      'draw': 'అద్దుటకై',
      'navigate': 'నావిగేషన్',
    },
    'th': <String, String>{
      // Thai
      'submitButtonText': 'ส่ง',
      'feedbackDescriptionText': 'เราจะทำอะไรได้ดีกว่านี้?',
      'draw': 'ทาสี',
      'navigate': 'นำทาง',
    },
    'tr': <String, String>{
      // Turkish
      'submitButtonText': 'gönder',
      'feedbackDescriptionText': 'Neyi daha iyi yapabiliriz?',
      'draw': 'boyamak',
      'navigate': 'Gezin',
    },
    'uk': <String, String>{
      // Ukrainian
      'submitButtonText': 'Відправити',
      'feedbackDescriptionText': 'Опишіть проблему',
      'draw': 'Малювання',
      'navigate': 'Навігація',
    },
    'ur': <String, String>{
      // Urdu
      'submitButtonText': 'جمع کرائیں',
      'feedbackDescriptionText': 'کیا خراب ہے؟',
      'draw': 'ڈرا',
      'navigate': 'رہنمائی کریں',
    },
    'uz': <String, String>{
      // Uzbek
      'submitButtonText': 'Yuborish',
      'feedbackDescriptionText': "Nima noto'g'ri?",
      'draw': 'Chizmoq',
      'navigate': "Yo'l hidi",
    },
    'vi': <String, String>{
      // Vietnamese
      'submitButtonText': 'Gửi đi',
      'feedbackDescriptionText': 'Có gì không ổn?',
      'draw': 'Vẽ',
      'navigate': 'Điều hướng',
    },
    'zh': <String, String>{
      // Chinese
      'submitButtonText': '提交',
      'feedbackDescriptionText': '敬请留下您宝贵的意见和建议：',
      'draw': '涂鸦',
      'navigate': '导航',
    },
    'zu': <String, String>{
      // Zulu
      'submitButtonText': 'Thumela',
      'feedbackDescriptionText': 'Kuyini okungalungile?',
      'draw': 'Thinta',
      'navigate': 'Hamba',
    },
  };

  /// Default English translations fallback
  static const Map<String, String> _defaultTranslations = <String, String>{
    'submitButtonText': 'Submit',
    'feedbackDescriptionText': "What's wrong?",
    'draw': 'Draw',
    'navigate': 'Navigate',
  };

  @override
  bool isSupported(Locale locale) {
    // We only support language codes for now
    if (_translations.containsKey(locale.languageCode)) {
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
    final String languageCode = locale.languageCode;

    // Get translations for the requested language, or fallback to English
    final Map<String, String> translations =
        _translations[languageCode] ?? _defaultTranslations;

    return CustomFeedbackLocalizations(translations);
  }

  @override
  bool shouldReload(CustomFeedbackLocalizationsDelegate old) => false;

  @override
  String toString() => 'DefaultFeedbackLocalizations.delegate(en_EN)';
}
