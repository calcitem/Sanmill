const SUPPORTED_LOCALES = [
  "ar",
  "bg",
  "bn",
  "cs",
  "de",
  "el",
  "en",
  "es",
  "fr",
  "hi",
  "hr",
  "hu",
  "it",
  "pl",
  "ps",
  "pt-BR",
  "ro",
  "sk",
  "sq",
  "sr",
  "tr",
  "ur",
  "zh-CN",
  "zh-TW",
];

const RTL_LOCALES = new Set(["ar", "ps", "ur"]);
const STORAGE_KEY = "sanmill-locale";

const LOCALE_LABELS = {
  ar: "ar - العربية",
  bg: "bg - Български",
  bn: "bn - বাংলা",
  cs: "cs - Čeština",
  de: "de - Deutsch",
  el: "el - Ελληνικά",
  en: "en - English",
  es: "es - Español",
  fr: "fr - Français",
  hi: "hi - हिन्दी",
  hr: "hr - Hrvatski",
  hu: "hu - Magyar",
  it: "it - Italiano",
  pl: "pl - Polski",
  ps: "ps - پښتو",
  "pt-BR": "pt-BR - Português (Brasil)",
  ro: "ro - Română",
  sk: "sk - Slovenčina",
  sq: "sq - Shqip",
  sr: "sr - Српски",
  tr: "tr - Türkçe",
  ur: "ur - اردو",
  "zh-CN": "zh-CN - 简体中文",
  "zh-TW": "zh-TW - 繁體中文",
};
const PRIMARY_LOCALE_MAP = {
  ar: "ar",
  bg: "bg",
  bn: "bn",
  cs: "cs",
  de: "de",
  el: "el",
  en: "en",
  es: "es",
  fr: "fr",
  hi: "hi",
  hr: "hr",
  hu: "hu",
  it: "it",
  pl: "pl",
  ps: "ps",
  pt: "pt-BR",
  ro: "ro",
  sk: "sk",
  sq: "sq",
  sr: "sr",
  tr: "tr",
  ur: "ur",
  zh: "zh-CN",
};

const LOCALE_ALIASES = {
  "pt-br": "pt-BR",
  "pt-pt": "pt-BR",
  "zh-cn": "zh-CN",
  "zh-sg": "zh-CN",
  "zh-hans": "zh-CN",
  "zh-tw": "zh-TW",
  "zh-hk": "zh-TW",
  "zh-mo": "zh-TW",
  "zh-hant": "zh-TW",
};

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

function normalizeLocale(value) {
  if (!value) {
    return null;
  }

  const trimmed = value.trim();
  if (!trimmed) {
    return null;
  }

  const direct = SUPPORTED_LOCALES.find(
    (locale) => locale.toLowerCase() === trimmed.toLowerCase(),
  );
  if (direct) {
    return direct;
  }

  const alias = LOCALE_ALIASES[trimmed.toLowerCase()];
  if (alias) {
    return alias;
  }

  return PRIMARY_LOCALE_MAP[trimmed.split("-")[0].toLowerCase()] ?? null;
}

function getPreferredLocale() {
  const stored = normalizeLocale(window.localStorage.getItem(STORAGE_KEY));
  if (stored) {
    return stored;
  }

  const browserLocales =
    Array.isArray(navigator.languages) && navigator.languages.length > 0
      ? navigator.languages
      : [navigator.language];

  for (const locale of browserLocales) {
    const normalized = normalizeLocale(locale);
    if (normalized) {
      return normalized;
    }
  }

  return "en";
}

function getValue(record, path) {
  return path.split(".").reduce((current, part) => {
    assert(current !== null && typeof current === "object", `Invalid path: ${path}`);
    assert(part in current, `Missing translation key: ${path}`);
    return current[part];
  }, record);
}

function escapeHtml(value) {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;");
}

function renderContent(element, value) {
  if (Array.isArray(value)) {
    if (element.tagName === "UL" || element.tagName === "OL") {
      element.innerHTML = value
        .map((item) => `<li>${escapeHtml(String(item))}</li>`)
        .join("");
      return;
    }

    element.innerHTML = value
      .map((item) => `<p>${escapeHtml(String(item))}</p>`)
      .join("");
    return;
  }

  element.textContent = String(value);
}

function applyTranslations(translations) {
  document.querySelectorAll("[data-i18n]").forEach((element) => {
    element.textContent = String(getValue(translations, element.dataset.i18n));
  });

  document.querySelectorAll("[data-i18n-html]").forEach((element) => {
    element.innerHTML = String(getValue(translations, element.dataset.i18nHtml));
  });

  document.querySelectorAll("[data-i18n-content]").forEach((element) => {
    renderContent(element, getValue(translations, element.dataset.i18nContent));
  });

  document.querySelectorAll("[data-i18n-attr]").forEach((element) => {
    const mappings = element.dataset.i18nAttr
      .split(";")
      .map((part) => part.trim())
      .filter(Boolean);

    for (const mapping of mappings) {
      const [attribute, key] = mapping.split(":").map((part) => part.trim());
      assert(attribute && key, `Invalid data-i18n-attr mapping: ${mapping}`);
      element.setAttribute(attribute, String(getValue(translations, key)));
    }
  });
}

function compareShape(reference, candidate, path) {
  if (Array.isArray(reference)) {
    assert(Array.isArray(candidate), `Expected array at ${path}`);
    return;
  }

  if (reference !== null && typeof reference === "object") {
    assert(
      candidate !== null && typeof candidate === "object" && !Array.isArray(candidate),
      `Expected object at ${path}`,
    );
    for (const key of Object.keys(reference)) {
      assert(key in candidate, `Missing key ${path}.${key}`);
      compareShape(reference[key], candidate[key], `${path}.${key}`);
    }
    return;
  }

  assert(typeof candidate === "string", `Expected string at ${path}`);
}

function homeLocale(title, description, heroTitle, lead, sublead, study, project) {
  return {
    meta: { title, description },
    hero: {
      eyebrow: "Sanmill",
      title: heroTitle,
      lead,
      sublead,
    },
    actions: {
      study,
      project,
    },
  };
}

const COMMON = {
  ar: { language: "اللغة", studyPages: "صفحات دراسة Sanmill" },
  bg: { language: "Език", studyPages: "Учебни страници на Sanmill" },
  bn: { language: "ভাষা", studyPages: "Sanmill অধ্যয়ন পৃষ্ঠা" },
  cs: { language: "Jazyk", studyPages: "Studijní stránky Sanmill" },
  de: { language: "Sprache", studyPages: "Sanmill Lernseiten" },
  el: { language: "Γλώσσα", studyPages: "Σελίδες μελέτης Sanmill" },
  en: { language: "Language", studyPages: "Sanmill Study Pages" },
  es: { language: "Idioma", studyPages: "Páginas de estudio de Sanmill" },
  fr: { language: "Langue", studyPages: "Pages d'étude Sanmill" },
  hi: { language: "भाषा", studyPages: "Sanmill अध्ययन पृष्ठ" },
  hr: { language: "Jezik", studyPages: "Stranice za učenje Sanmill" },
  hu: { language: "Nyelv", studyPages: "Sanmill tanulóoldalak" },
  it: { language: "Lingua", studyPages: "Pagine di studio di Sanmill" },
  pl: { language: "Język", studyPages: "Strony szkoleniowe Sanmill" },
  ps: { language: "ژبه", studyPages: "د Sanmill د زده کړې پاڼې" },
  "pt-BR": { language: "Idioma", studyPages: "Páginas de estudo do Sanmill" },
  ro: { language: "Limbă", studyPages: "Pagini de studiu Sanmill" },
  sk: { language: "Jazyk", studyPages: "Študijné stránky Sanmill" },
  sq: { language: "Gjuha", studyPages: "Faqet e studimit të Sanmill" },
  sr: { language: "Језик", studyPages: "Странице за учење Sanmill" },
  tr: { language: "Dil", studyPages: "Sanmill çalışma sayfaları" },
  ur: { language: "زبان", studyPages: "Sanmill مطالعہ صفحات" },
  "zh-CN": { language: "语言", studyPages: "Sanmill 学习页面" },
  "zh-TW": { language: "語言", studyPages: "Sanmill 學習頁面" },
};

const HOME = {
  ar: homeLocale(
    "صفحات دراسة Sanmill",
    "صفحات دراسة رسمية مرتبطة من تطبيق Sanmill.",
    "صفحات دراسية للاعبي Morris",
    "يستضيف هذا الموقع صفحات الدراسة الرسمية المرتبطة من تطبيق Sanmill.",
    "افتح صفحة Nine Men's Morris للحصول على ملاحظات استراتيجية سريعة وتمارين قصيرة وخطوات عملية تالية.",
    "افتح صفحة دراسة NMM",
    "اعرض مشروع Sanmill",
  ),
  bg: homeLocale(
    "Учебни страници на Sanmill",
    "Официални учебни страници, свързани от приложението Sanmill.",
    "Учебни страници за играчи на Morris",
    "Този сайт съдържа официалните учебни страници, свързани от приложението Sanmill.",
    "Отворете страницата за Nine Men's Morris за кратки стратегически бележки, кратки упражнения и практични следващи стъпки.",
    "Отвори учебната страница за NMM",
    "Виж проекта Sanmill",
  ),
  bn: homeLocale(
    "Sanmill অধ্যয়ন পৃষ্ঠা",
    "Sanmill অ্যাপ থেকে সংযুক্ত অফিসিয়াল অধ্যয়ন পৃষ্ঠা।",
    "Morris খেলোয়াড়দের জন্য অধ্যয়ন পৃষ্ঠা",
    "এই সাইটে Sanmill অ্যাপ থেকে সংযুক্ত অফিসিয়াল অধ্যয়ন পৃষ্ঠা রয়েছে।",
    "দ্রুত কৌশল নোট, ছোট অনুশীলন এবং ব্যবহারিক পরবর্তী ধাপের জন্য Nine Men's Morris পৃষ্ঠা খুলুন।",
    "NMM অধ্যয়ন পৃষ্ঠা খুলুন",
    "Sanmill প্রকল্প দেখুন",
  ),
  cs: homeLocale(
    "Studijní stránky Sanmill",
    "Oficiální studijní stránky propojené z aplikace Sanmill.",
    "Studijní stránky pro hráče Morris",
    "Tento web hostí oficiální studijní stránky propojené z aplikace Sanmill.",
    "Otevřete stránku Nine Men's Morris pro stručné strategické poznámky, krátká cvičení a praktické další kroky.",
    "Otevřít studijní stránku NMM",
    "Zobrazit projekt Sanmill",
  ),
  de: homeLocale(
    "Sanmill Lernseiten",
    "Offizielle Lernseiten, die aus der Sanmill-App verlinkt sind.",
    "Lernseiten für Morris-Spieler",
    "Diese Website enthält offizielle Lernseiten, die aus der Sanmill-App verlinkt sind.",
    "Öffne die Nine Men's Morris-Seite für kurze Strategienotizen, kurze Übungen und praktische nächste Schritte.",
    "NMM-Lernseite öffnen",
    "Sanmill-Projekt ansehen",
  ),
  el: homeLocale(
    "Σελίδες μελέτης Sanmill",
    "Επίσημες σελίδες μελέτης που συνδέονται από την εφαρμογή Sanmill.",
    "Σελίδες μελέτης για παίκτες Morris",
    "Αυτός ο ιστότοπος φιλοξενεί τις επίσημες σελίδες μελέτης που συνδέονται από την εφαρμογή Sanmill.",
    "Ανοίξτε τη σελίδα Nine Men's Morris για σύντομες σημειώσεις στρατηγικής, μικρές ασκήσεις και πρακτικά επόμενα βήματα.",
    "Άνοιγμα της σελίδας μελέτης NMM",
    "Δείτε το έργο Sanmill",
  ),
  en: homeLocale(
    "Sanmill Study Pages",
    "Official study pages linked from the Sanmill app.",
    "Study pages for Morris players",
    "This site hosts official study pages linked from the Sanmill app.",
    "Open the Nine Men's Morris page for quick strategy notes, short drills, and practical next steps.",
    "Open the NMM study page",
    "View the Sanmill project",
  ),
  es: homeLocale(
    "Páginas de estudio de Sanmill",
    "Páginas de estudio oficiales enlazadas desde la aplicación Sanmill.",
    "Páginas de estudio para jugadores de Morris",
    "Este sitio aloja las páginas de estudio oficiales enlazadas desde la aplicación Sanmill.",
    "Abre la página de Nine Men's Morris para ver notas estratégicas breves, ejercicios cortos y próximos pasos prácticos.",
    "Abrir la página de estudio de NMM",
    "Ver el proyecto Sanmill",
  ),
  fr: homeLocale(
    "Pages d'étude Sanmill",
    "Pages d'étude officielles liées depuis l'application Sanmill.",
    "Pages d'étude pour les joueurs de Morris",
    "Ce site héberge les pages d'étude officielles liées depuis l'application Sanmill.",
    "Ouvrez la page Nine Men's Morris pour de courtes notes de stratégie, de petits exercices et des étapes pratiques.",
    "Ouvrir la page d'étude NMM",
    "Voir le projet Sanmill",
  ),
  hi: homeLocale(
    "Sanmill अध्ययन पृष्ठ",
    "Sanmill ऐप से जुड़े आधिकारिक अध्ययन पृष्ठ।",
    "Morris खिलाड़ियों के लिए अध्ययन पृष्ठ",
    "यह साइट Sanmill ऐप से जुड़े आधिकारिक अध्ययन पृष्ठ होस्ट करती है।",
    "त्वरित रणनीति नोट्स, छोटे अभ्यास और व्यावहारिक अगले कदमों के लिए Nine Men's Morris पृष्ठ खोलें।",
    "NMM अध्ययन पृष्ठ खोलें",
    "Sanmill प्रोजेक्ट देखें",
  ),
  hr: homeLocale(
    "Stranice za učenje Sanmill",
    "Službene stranice za učenje povezane iz aplikacije Sanmill.",
    "Stranice za učenje za igrače Morrisa",
    "Ova stranica sadrži službene stranice za učenje povezane iz aplikacije Sanmill.",
    "Otvorite stranicu Nine Men's Morris za kratke strateške bilješke, kratke vježbe i praktične sljedeće korake.",
    "Otvori stranicu za učenje NMM",
    "Pogledaj projekt Sanmill",
  ),
  hu: homeLocale(
    "Sanmill tanulóoldalak",
    "A Sanmill alkalmazásból hivatkozott hivatalos tanulóoldalak.",
    "Tanulóoldalak Morris-játékosoknak",
    "Ez az oldal a Sanmill alkalmazásból hivatkozott hivatalos tanulóoldalakat tartalmazza.",
    "Nyisd meg a Nine Men's Morris oldalt rövid stratégiai jegyzetekért, rövid gyakorlásokért és gyakorlati következő lépésekért.",
    "Az NMM tanulóoldal megnyitása",
    "A Sanmill projekt megtekintése",
  ),
  it: homeLocale(
    "Pagine di studio di Sanmill",
    "Pagine di studio ufficiali collegate dall'app Sanmill.",
    "Pagine di studio per giocatori di Morris",
    "Questo sito ospita le pagine di studio ufficiali collegate dall'app Sanmill.",
    "Apri la pagina di Nine Men's Morris per note strategiche rapide, brevi esercizi e prossimi passi pratici.",
    "Apri la pagina di studio NMM",
    "Visualizza il progetto Sanmill",
  ),
  pl: homeLocale(
    "Strony szkoleniowe Sanmill",
    "Oficjalne strony szkoleniowe podlinkowane z aplikacji Sanmill.",
    "Strony szkoleniowe dla graczy Morrisa",
    "Ta witryna zawiera oficjalne strony szkoleniowe podlinkowane z aplikacji Sanmill.",
    "Otwórz stronę Nine Men's Morris, aby zobaczyć krótkie notatki strategiczne, krótkie ćwiczenia i praktyczne kolejne kroki.",
    "Otwórz stronę szkoleniową NMM",
    "Zobacz projekt Sanmill",
  ),
  ps: homeLocale(
    "د Sanmill د زده کړې پاڼې",
    "رسمي د زده کړې پاڼې چې د Sanmill اپ څخه تړلې دي.",
    "د Morris لوبغاړو لپاره د زده کړې پاڼې",
    "دا سایټ د Sanmill اپ څخه تړلې رسمي د زده کړې پاڼې کوربه کوي.",
    "د چټکو ستراتېژۍ یادښتونو، لنډو تمرینونو او عملي بل ګام لپاره د Nine Men's Morris پاڼه پرانیزئ.",
    "د NMM د زده کړې پاڼه پرانیزئ",
    "د Sanmill پروژه وګورئ",
  ),
  "pt-BR": homeLocale(
    "Páginas de estudo do Sanmill",
    "Páginas de estudo oficiais vinculadas a partir do app Sanmill.",
    "Páginas de estudo para jogadores de Morris",
    "Este site reúne as páginas de estudo oficiais vinculadas a partir do app Sanmill.",
    "Abra a página de Nine Men's Morris para ver notas rápidas de estratégia, exercícios curtos e próximos passos práticos.",
    "Abrir a página de estudo de NMM",
    "Ver o projeto Sanmill",
  ),
  ro: homeLocale(
    "Pagini de studiu Sanmill",
    "Pagini de studiu oficiale legate din aplicația Sanmill.",
    "Pagini de studiu pentru jucătorii de Morris",
    "Acest site găzduiește paginile de studiu oficiale legate din aplicația Sanmill.",
    "Deschide pagina Nine Men's Morris pentru note strategice scurte, exerciții scurte și pași practici următori.",
    "Deschide pagina de studiu NMM",
    "Vezi proiectul Sanmill",
  ),
  sk: homeLocale(
    "Študijné stránky Sanmill",
    "Oficiálne študijné stránky prepojené z aplikácie Sanmill.",
    "Študijné stránky pre hráčov Morris",
    "Táto stránka hostí oficiálne študijné stránky prepojené z aplikácie Sanmill.",
    "Otvorte stránku Nine Men's Morris pre stručné strategické poznámky, krátke cvičenia a praktické ďalšie kroky.",
    "Otvoriť študijnú stránku NMM",
    "Zobraziť projekt Sanmill",
  ),
  sq: homeLocale(
    "Faqet e studimit të Sanmill",
    "Faqe studimi zyrtare të lidhura nga aplikacioni Sanmill.",
    "Faqe studimi për lojtarët e Morris",
    "Kjo faqe mban faqet zyrtare të studimit të lidhura nga aplikacioni Sanmill.",
    "Hap faqen e Nine Men's Morris për shënime të shkurtra strategjie, ushtrime të shkurtra dhe hapa praktikë të radhës.",
    "Hap faqen e studimit NMM",
    "Shih projektin Sanmill",
  ),
  sr: homeLocale(
    "Странице за учење Sanmill",
    "Званичне странице за учење повезане из апликације Sanmill.",
    "Странице за учење за играче Morrisa",
    "Овај сајт садржи званичне странице за учење повезане из апликације Sanmill.",
    "Отворите страницу Nine Men's Morris за кратке стратешке белешке, кратке вежбе и практичне следеће кораке.",
    "Отвори NMM страницу за учење",
    "Погледај пројекат Sanmill",
  ),
  tr: homeLocale(
    "Sanmill çalışma sayfaları",
    "Sanmill uygulamasından bağlanan resmî çalışma sayfaları.",
    "Morris oyuncuları için çalışma sayfaları",
    "Bu site, Sanmill uygulamasından bağlanan resmî çalışma sayfalarını barındırır.",
    "Kısa strateji notları, kısa alıştırmalar ve pratik sonraki adımlar için Nine Men's Morris sayfasını açın.",
    "NMM çalışma sayfasını aç",
    "Sanmill projesini görüntüle",
  ),
  ur: homeLocale(
    "Sanmill مطالعہ صفحات",
    "Sanmill ایپ سے منسلک سرکاری مطالعہ صفحات۔",
    "Morris کھلاڑیوں کے لیے مطالعہ صفحات",
    "یہ سائٹ Sanmill ایپ سے منسلک سرکاری مطالعہ صفحات مہیا کرتی ہے۔",
    "مختصر حکمتِ عملی نوٹس، چھوٹی مشقوں اور عملی اگلے قدم کے لیے Nine Men's Morris صفحہ کھولیں۔",
    "NMM مطالعہ صفحہ کھولیں",
    "Sanmill منصوبہ دیکھیں",
  ),
  "zh-CN": homeLocale(
    "Sanmill 学习页面",
    "从 Sanmill 应用链接过来的官方学习页面。",
    "面向 Morris 玩家 的学习页面",
    "这个站点承载从 Sanmill 应用链接过来的官方学习页面。",
    "打开 Nine Men's Morris 页面，查看简明策略笔记、短练习和可立即尝试的下一步。",
    "打开 NMM 学习页面",
    "查看 Sanmill 项目",
  ),
  "zh-TW": homeLocale(
    "Sanmill 學習頁面",
    "從 Sanmill 應用連結過來的官方學習頁面。",
    "面向 Morris 玩家 的學習頁面",
    "這個站點承載從 Sanmill 應用連結過來的官方學習頁面。",
    "打開 Nine Men's Morris 頁面，查看精簡策略筆記、短練習與可立即嘗試的下一步。",
    "打開 NMM 學習頁面",
    "查看 Sanmill 專案",
  ),
};

const STRATEGY = {
  en: {
    meta: {
      title: "Sanmill | Nine Men's Morris Strategy Notes",
      description: "Short strategy notes and drills for Sanmill Nine Men's Morris players.",
    },
    nav: {
      fixes: "Fixes",
      drills: "Drills",
      mistakes: "Habits",
      resources: "Resources",
    },
    hero: {
      eyebrow: "Nine Men's Morris Strategy",
      title: "Play calmer.<br>Create two threats.<br>Keep your moves alive.",
      lead: "This page is for Sanmill players who want a short plan, not a theory book. Focus on one adjustment in your next games.",
      rules: "<strong>Rules note:</strong> Standard Nine Men's Morris uses a placing phase, a moving phase on adjacent points, and flying when a side has three pieces.",
      primary: "Show the fixes",
      secondary: "Open resources",
    },
    tips: [
      "Count legal moves before you count material.",
      "Ask whether each move creates a second threat.",
      "Near three pieces, watch flying threats first.",
    ],
    fixes: {
      title: "Three common fixes",
      cards: [
        {
          title: "Fix A: You run out of moves",
          body: "This is a mobility problem. In the moving phase, prefer the move that keeps your legal moves stable or growing.",
        },
        {
          title: "Fix B: You never build pressure",
          body: "This is a structure problem. In the placing phase, prefer connector points and spread across rings.",
        },
        {
          title: "Fix C: Your mills do not change the game",
          body: "This is a tempo problem. Do not reopen the same mill automatically unless the capture improves your position.",
        },
      ],
    },
    drills: {
      title: "Three short drills",
      items: [
        "Play three games and reject any move that lowers your legal-move count unless it wins material immediately.",
        "Play three games where you place on points that connect multiple lines before chasing an early mill.",
        "Review one loss and mark the first turn when your options became narrower than the AI's.",
      ],
    },
    mistakes: {
      title: "Habits to drop and habits to keep",
      badTitle: "Drop these habits",
      bad: [
        "Capturing any piece just because you can.",
        "Defending one threat without creating another.",
        "Packing pieces on one ring and losing flexibility.",
      ],
      goodTitle: "Keep these habits",
      good: [
        "Count legal moves for both sides before the board gets tight.",
        "Prefer placements that connect lines and future threats.",
        "Treat the three-piece threshold as a change in priorities.",
      ],
      rememberTitle: "One sentence to remember",
      rememberText: "<strong>You can lose by being reduced below three pieces or by having no legal move.</strong>",
    },
    resources: {
      title: "Resources",
      externalTitle: "External strategy reference",
      externalBody: "The NMM Strategy page collects broader material on openings, structure, and endgames if you want to study further.",
      externalCta: "Open NMM Strategy",
      appTitle: "Keep using the app",
      appBody: "Sanmill is still the best place to test one change at a time. Short repeatable games make progress visible.",
      repoCta: "Open the Sanmill repository",
    },
    footer: {
      note: "A short focused drill is often more useful than a long article. Pick one idea here and try it in your next game.",
    },
  },
  ar: {
    meta: {
      title: "Sanmill | ملاحظات استراتيجية Nine Men's Morris",
      description: "ملاحظات قصيرة وتمارين للاعبي Nine Men's Morris في Sanmill.",
    },
    nav: {
      fixes: "الإصلاحات",
      drills: "تمارين",
      mistakes: "العادات",
      resources: "المصادر",
    },
    hero: {
      eyebrow: "استراتيجية Nine Men's Morris",
      title: "العب بهدوء.<br>اصنع تهديدين.<br>وأبقِ حركاتك حيّة.",
      lead: "هذه الصفحة للاعبي Sanmill الذين يريدون خطة قصيرة لا كتاب نظريات. ركّز على تعديل واحد في مبارياتك القادمة.",
      rules: "<strong>ملاحظة القواعد:</strong> يستخدم Nine Men's Morris القياسي مرحلة وضع، ثم مرحلة حركة إلى النقاط المجاورة، ثم الطيران عندما تبقى ثلاث قطع.",
      primary: "أرني الإصلاحات",
      secondary: "افتح المصادر",
    },
    tips: [
      "احسب الحركات القانونية قبل أن تحسب القطع.",
      "اسأل هل تصنع كل نقلة تهديدًا ثانيًا.",
      "قرب ثلاث قطع، راقب تهديدات الطيران أولًا.",
    ],
    fixes: {
      title: "ثلاثة إصلاحات شائعة",
      cards: [
        {
          title: "الإصلاح A: تنفد حركاتك",
          body: "هذه مشكلة حركة. في مرحلة الحركة فضّل النقلة التي تُبقي حركاتك القانونية ثابتة أو أعلى.",
        },
        {
          title: "الإصلاح B: لا تبني ضغطًا",
          body: "هذه مشكلة بنية. في مرحلة الوضع فضّل نقاط الربط وانتشر عبر الحلقات.",
        },
        {
          title: "الإصلاح C: الثلاثيات لا تغيّر المباراة",
          body: "هذه مشكلة إيقاع. لا تعِد فتح الثلاثية نفسها تلقائيًا إلا إذا حسّنت الأخذ وضعك.",
        },
      ],
    },
    drills: {
      title: "ثلاثة تمارين قصيرة",
      items: [
        "العب ثلاث مباريات وارفض أي نقلة تقلّل حركاتك القانونية ما لم تربح مادة فورًا.",
        "العب ثلاث مباريات تضع فيها قطعك على نقاط تصل أكثر من خط قبل مطاردة ثلاثية مبكرة.",
        "راجع خسارة واحدة وحدّد أول دور أصبحت فيه خياراتك أضيق من خيارات الذكاء الاصطناعي.",
      ],
    },
    mistakes: {
      title: "عادات يجب تركها وعادات يجب الحفاظ عليها",
      badTitle: "اترك هذه العادات",
      bad: [
        "أخذ أي قطعة لمجرد أنك تستطيع.",
        "الدفاع عن تهديد واحد من دون صنع تهديد آخر.",
        "تكديس القطع على حلقة واحدة وخسارة المرونة.",
      ],
      goodTitle: "حافظ على هذه العادات",
      good: [
        "عدّ الحركات القانونية للطرفين قبل أن تضيق الرقعة.",
        "فضّل النقاط التي تصل الخطوط وتهديدات المستقبل.",
        "اعتبر عتبة الثلاث قطع تغيّرًا في الأولويات.",
      ],
      rememberTitle: "جملة واحدة لتتذكرها",
      rememberText: "<strong>يمكنك أن تخسر إذا هبطت إلى أقل من ثلاث قطع أو إذا لم يعد لديك أي تحرك قانوني.</strong>",
    },
    resources: {
      title: "المصادر",
      externalTitle: "مرجع استراتيجية خارجي",
      externalBody: "تجمع صفحة NMM Strategy مواد أوسع عن الافتتاحيات والبنية ونهايات اللعب إذا أردت دراسة أعمق.",
      externalCta: "افتح NMM Strategy",
      appTitle: "واصل استخدام التطبيق",
      appBody: "يبقى Sanmill أفضل مكان لاختبار تعديل واحد في كل مرة. المباريات القصيرة القابلة للتكرار تجعل التقدّم واضحًا.",
      repoCta: "افتح مستودع Sanmill",
    },
    footer: {
      note: "غالبًا ما يكون التمرين القصير المركّز أنفع من مقال طويل. اختر فكرة واحدة هنا وجرّبها في مباراتك القادمة.",
    },
  },
  bg: {
    meta: {
      title: "Sanmill | Кратки стратегически бележки за Nine Men's Morris",
      description: "Кратки бележки и упражнения за играчи на Nine Men's Morris в Sanmill.",
    },
    nav: {
      fixes: "Поправки",
      drills: "Упражнения",
      mistakes: "Навици",
      resources: "Ресурси",
    },
    hero: {
      eyebrow: "Стратегия за Nine Men's Morris",
      title: "Играй по-спокойно.<br>Създавай две заплахи.<br>Пази ходовете си живи.",
      lead: "Тази страница е за играчи на Sanmill, които искат кратък план, а не книга по теория. Фокусирай се върху една промяна в следващите си партии.",
      rules: "<strong>Бележка за правилата:</strong> Стандартният Nine Men's Morris има фаза на поставяне, фаза на движение към съседни точки и летене, когато страна остане с три фигури.",
      primary: "Покажи поправките",
      secondary: "Отвори ресурсите",
    },
    tips: [
      "Брой законните ходове, преди да броиш фигурите.",
      "Питай дали всеки ход създава втора заплаха.",
      "При три фигури гледай първо летящите заплахи.",
    ],
    fixes: {
      title: "Три чести поправки",
      cards: [
        {
          title: "Поправка A: Оставаш без ходове",
          body: "Това е проблем с подвижността. Във фазата на движение предпочитай хода, който запазва или увеличава законните ти ходове.",
        },
        {
          title: "Поправка B: Не изграждаш натиск",
          body: "Това е проблем със структурата. Във фазата на поставяне предпочитай свързващите точки и се разпределяй по пръстените.",
        },
        {
          title: "Поправка C: Мелниците ти не променят партията",
          body: "Това е проблем с темпото. Не отваряй автоматично същата мелница, освен ако вземането не подобрява позицията ти.",
        },
      ],
    },
    drills: {
      title: "Три кратки упражнения",
      items: [
        "Играй три партии и отхвърляй всеки ход, който намалява законните ти ходове, освен ако не печели материал веднага.",
        "Играй три партии, в които поставяш на точки, свързващи няколко линии, преди да гониш ранна мелница.",
        "Прегледай една загуба и отбележи първия ход, в който възможностите ти станаха по-тесни от тези на ИИ.",
      ],
    },
    mistakes: {
      title: "Навици за махане и навици за запазване",
      badTitle: "Махни тези навици",
      bad: [
        "Вземаш всяка фигура само защото можеш.",
        "Защитаваш една заплаха без да създаваш друга.",
        "Трупаш фигури на един пръстен и губиш гъвкавост.",
      ],
      goodTitle: "Запази тези навици",
      good: [
        "Брой законните ходове и на двете страни, преди дъската да се стегне.",
        "Предпочитай точки, които свързват линии и бъдещи заплахи.",
        "Приемай прага от три фигури като смяна на приоритетите.",
      ],
      rememberTitle: "Едно изречение за запомняне",
      rememberText: "<strong>Можеш да загубиш, ако паднеш под три фигури или ако нямаш законен ход.</strong>",
    },
    resources: {
      title: "Ресурси",
      externalTitle: "Външен стратегически източник",
      externalBody: "Страницата NMM Strategy събира по-широк материал за откривания, структура и ендшпили, ако искаш да учиш още.",
      externalCta: "Отвори NMM Strategy",
      appTitle: "Продължавай да използваш приложението",
      appBody: "Sanmill остава най-доброто място да тестваш по една промяна. Кратките повтаряеми партии правят напредъка видим.",
      repoCta: "Отвори хранилището на Sanmill",
    },
    footer: {
      note: "Краткото фокусирано упражнение често е по-полезно от дълга статия. Избери една идея тук и я пробвай в следващата си партия.",
    },
  },
  bn: {
    meta: {
      title: "Sanmill | Nine Men's Morris কৌশল নোট",
      description: "Sanmill এর Nine Men's Morris খেলোয়াড়দের জন্য সংক্ষিপ্ত নোট ও অনুশীলন।",
    },
    nav: {
      fixes: "সমাধান",
      drills: "অনুশীলন",
      mistakes: "অভ্যাস",
      resources: "রিসোর্স",
    },
    hero: {
      eyebrow: "Nine Men's Morris কৌশল",
      title: "শান্তভাবে খেলুন।<br>দুটি হুমকি গড়ুন।<br>চালগুলো খোলা রাখুন।",
      lead: "এই পৃষ্ঠা Sanmill খেলোয়াড়দের জন্য, যারা তত্ত্বের বই নয়, ছোট একটি পরিকল্পনা চান। পরের খেলাগুলোতে একটি বদলেই মন দিন।",
      rules: "<strong>নিয়ম নোট:</strong> মানক Nine Men's Morris এ বসানোর পর্যায়, পাশের পয়েন্টে চালের পর্যায়, এবং তিনটি গুটি থাকলে flying থাকে।",
      primary: "সমাধানগুলো দেখান",
      secondary: "রিসোর্স খুলুন",
    },
    tips: [
      "গুটি গোনার আগে বৈধ চাল গুনুন।",
      "দেখুন প্রতিটি চাল কি দ্বিতীয় হুমকি তৈরি করছে।",
      "তিন গুটি কাছে এলে আগে flying হুমকি দেখুন।",
    ],
    fixes: {
      title: "তিনটি সাধারণ সমাধান",
      cards: [
        {
          title: "Fix A: আপনার চাল ফুরিয়ে যায়",
          body: "এটি mobility সমস্যা। চালের পর্যায়ে সেই চালকে অগ্রাধিকার দিন যা বৈধ চালের সংখ্যা স্থির রাখে বা বাড়ায়।",
        },
        {
          title: "Fix B: আপনি চাপ গড়তে পারেন না",
          body: "এটি structure সমস্যা। বসানোর পর্যায়ে connector point নিন এবং রিং জুড়ে ছড়িয়ে খেলুন।",
        },
        {
          title: "Fix C: mill বানিয়েও খেলা বদলায় না",
          body: "এটি tempo সমস্যা। capture আপনার অবস্থান না বদলালে একই mill আবার খুলবেন না।",
        },
      ],
    },
    drills: {
      title: "তিনটি ছোট অনুশীলন",
      items: [
        "তিনটি খেলা খেলুন এবং এমন কোনো চাল নেবেন না যা বৈধ চাল কমায়, যদি না তা সঙ্গে সঙ্গে material জেতায়।",
        "তিনটি খেলায় early mill ধরার আগে একাধিক লাইন যুক্ত করে এমন পয়েন্টে গুটি বসান।",
        "একটি হার দেখুন এবং সেই প্রথম টার্নটি চিহ্নিত করুন যখন আপনার বিকল্প AI এর চেয়ে সংকীর্ণ হয়ে যায়।",
      ],
    },
    mistakes: {
      title: "যে অভ্যাস ছাড়বেন আর রাখবেন",
      badTitle: "এই অভ্যাসগুলো ছাড়ুন",
      bad: [
        "শুধু পারছেন বলে যেকোনো গুটি খাওয়া।",
        "একটি হুমকি ঠেকিয়ে আরেকটি না তৈরি করা।",
        "একটি রিংয়েই গুটি ঠাসা করে নমনীয়তা হারানো।",
      ],
      goodTitle: "এই অভ্যাসগুলো রাখুন",
      good: [
        "বোর্ড চাপা হওয়ার আগে দুই পক্ষের বৈধ চাল গুনুন।",
        "লাইন ও ভবিষ্যৎ হুমকি যুক্ত করে এমন পয়েন্ট বেছে নিন।",
        "তিন গুটি সীমাকে অগ্রাধিকারের পরিবর্তন হিসেবে ধরুন।",
      ],
      rememberTitle: "মনে রাখার একটি বাক্য",
      rememberText: "<strong>আপনি তিনটির কম গুটিতে নেমে গেলে বা কোনো বৈধ চাল না থাকলেও হারতে পারেন।</strong>",
    },
    resources: {
      title: "রিসোর্স",
      externalTitle: "বাহ্যিক কৌশল রেফারেন্স",
      externalBody: "আরও গভীরে যেতে চাইলে NMM Strategy পৃষ্ঠা opening, structure এবং endgame নিয়ে বড় উপকরণ জোগাড় করে।",
      externalCta: "NMM Strategy খুলুন",
      appTitle: "অ্যাপ ব্যবহার চালিয়ে যান",
      appBody: "Sanmill এখনো একবারে একটি বদল পরীক্ষা করার সেরা জায়গা। ছোট পুনরাবৃত্তিমূলক খেলা উন্নতি চোখে আনে।",
      repoCta: "Sanmill repository খুলুন",
    },
    footer: {
      note: "দীর্ঘ প্রবন্ধের চেয়ে ছোট মনোযোগী অনুশীলন অনেক সময় বেশি কাজে লাগে। এখান থেকে একটি ধারণা নিন এবং পরের খেলায় চেষ্টা করুন।",
    },
  },
  cs: {
    meta: {
      title: "Sanmill | Strategické poznámky k Nine Men's Morris",
      description: "Krátké poznámky a cvičení pro hráče Nine Men's Morris v Sanmill.",
    },
    nav: {
      fixes: "Opravy",
      drills: "Cvičení",
      mistakes: "Návyky",
      resources: "Zdroje",
    },
    hero: {
      eyebrow: "Strategie Nine Men's Morris",
      title: "Hraj klidněji.<br>Vytvářej dvě hrozby.<br>Udrž si tahy naživu.",
      lead: "Tato stránka je pro hráče Sanmill, kteří chtějí krátký plán, ne učebnici teorie. V dalších hrách se soustřeď na jednu změnu.",
      rules: "<strong>Poznámka k pravidlům:</strong> Standardní Nine Men's Morris má fázi pokládání, fázi pohybu na sousední body a létání, když straně zůstanou tři kameny.",
      primary: "Ukaž opravy",
      secondary: "Otevřít zdroje",
    },
    tips: [
      "Nejdřív počítej legální tahy, až potom materiál.",
      "Ptej se, zda každý tah vytváří druhou hrozbu.",
      "Když se blíží tři kameny, sleduj nejdřív hrozby létání.",
    ],
    fixes: {
      title: "Tři časté opravy",
      cards: [
        {
          title: "Oprava A: Docházejí ti tahy",
          body: "To je problém mobility. Ve fázi pohybu dávej přednost tahu, který drží nebo zvyšuje počet tvých legálních tahů.",
        },
        {
          title: "Oprava B: Nevytváříš tlak",
          body: "To je problém struktury. Ve fázi pokládání dávej přednost spojovacím bodům a rozprostři kameny mezi kruhy.",
        },
        {
          title: "Oprava C: Tvoje mlýny nemění partii",
          body: "To je problém tempa. Neotvírej stejný mlýn znovu automaticky, pokud braní nezlepší tvoji pozici.",
        },
      ],
    },
    drills: {
      title: "Tři krátká cvičení",
      items: [
        "Zahraj tři partie a odmítni každý tah, který sníží počet tvých legálních tahů, pokud hned nezíská materiál.",
        "Ve třech partiích nejdřív pokládej na body, které spojují více linií, a teprve pak chaseuj raný mlýn.",
        "Projdi jednu prohru a označ první tah, kdy byly tvoje možnosti užší než možnosti AI.",
      ],
    },
    mistakes: {
      title: "Návyky k odložení a návyky k udržení",
      badTitle: "Tyto návyky odhoď",
      bad: [
        "Brát libovolný kámen jen proto, že můžeš.",
        "Bránit jednu hrozbu bez vytvoření další.",
        "Hromadit kameny na jednom kruhu a ztrácet pružnost.",
      ],
      goodTitle: "Tyto návyky si nech",
      good: [
        "Počítej legální tahy obou stran dřív, než se deska sevře.",
        "Dávej přednost bodům, které spojují linie a budoucí hrozby.",
        "Ber tři kameny jako změnu priorit.",
      ],
      rememberTitle: "Jedna věta k zapamatování",
      rememberText: "<strong>Můžeš prohrát pádem pod tři kameny nebo tím, že nebudeš mít žádný legální tah.</strong>",
    },
    resources: {
      title: "Zdroje",
      externalTitle: "Externí strategický zdroj",
      externalBody: "Stránka NMM Strategy shromažďuje širší materiál o zahájeních, struktuře a koncovkách, pokud chceš studovat hlouběji.",
      externalCta: "Otevřít NMM Strategy",
      appTitle: "Pokračuj v používání aplikace",
      appBody: "Sanmill je stále nejlepší místo pro testování jedné změny. Krátké opakovatelné partie dělají pokrok viditelný.",
      repoCta: "Otevřít repozitář Sanmill",
    },
    footer: {
      note: "Krátké soustředěné cvičení bývá často užitečnější než dlouhý článek. Vyber si tu jednu myšlenku a zkus ji v další partii.",
    },
  },
  de: {
    meta: {
      title: "Sanmill | Strategienotizen für Nine Men's Morris",
      description: "Kurze Notizen und Übungen für Nine Men's Morris-Spieler in Sanmill.",
    },
    nav: {
      fixes: "Korrekturen",
      drills: "Übungen",
      mistakes: "Gewohnheiten",
      resources: "Ressourcen",
    },
    hero: {
      eyebrow: "Nine Men's Morris Strategie",
      title: "Spiele ruhiger.<br>Erzeuge zwei Drohungen.<br>Halte deine Züge lebendig.",
      lead: "Diese Seite ist für Sanmill-Spieler gedacht, die einen kurzen Plan wollen, kein Theoriebuch. Konzentriere dich in deinen nächsten Partien auf eine Änderung.",
      rules: "<strong>Regelhinweis:</strong> Standard-Nine Men's Morris hat eine Setzphase, eine Bewegungsphase zu angrenzenden Punkten und Fliegen, wenn eine Seite drei Steine hat.",
      primary: "Zeig die Korrekturen",
      secondary: "Ressourcen öffnen",
    },
    tips: [
      "Zähle zuerst legale Züge, dann Material.",
      "Frage dich, ob jeder Zug eine zweite Drohung erzeugt.",
      "In der Nähe von drei Steinen achte zuerst auf Flugdrohungen.",
    ],
    fixes: {
      title: "Drei häufige Korrekturen",
      cards: [
        {
          title: "Korrektur A: Dir gehen die Züge aus",
          body: "Das ist ein Mobilitätsproblem. Bevorzuge in der Bewegungsphase den Zug, der deine legalen Züge stabil hält oder erhöht.",
        },
        {
          title: "Korrektur B: Du baust keinen Druck auf",
          body: "Das ist ein Strukturproblem. Bevorzuge in der Setzphase Verbindungspunkte und verteile dich über mehrere Ringe.",
        },
        {
          title: "Korrektur C: Deine Mühlen ändern die Partie nicht",
          body: "Das ist ein Tempoproblem. Öffne dieselbe Mühle nicht automatisch wieder, wenn das Schlagen deine Stellung nicht verbessert.",
        },
      ],
    },
    drills: {
      title: "Drei kurze Übungen",
      items: [
        "Spiele drei Partien und lehne jeden Zug ab, der deine legalen Züge verringert, außer er gewinnt sofort Material.",
        "Spiele drei Partien, in denen du zuerst Punkte besetzt, die mehrere Linien verbinden, bevor du einer frühen Mühle nachjagst.",
        "Sieh dir eine Niederlage an und markiere den ersten Zug, in dem deine Möglichkeiten enger wurden als die der KI.",
      ],
    },
    mistakes: {
      title: "Gewohnheiten, die du ablegen und behalten solltest",
      badTitle: "Lege diese Gewohnheiten ab",
      bad: [
        "Irgendeinen Stein schlagen, nur weil es geht.",
        "Eine Drohung verteidigen, ohne eine zweite zu erzeugen.",
        "Steine auf einem Ring stapeln und Flexibilität verlieren.",
      ],
      goodTitle: "Behalte diese Gewohnheiten",
      good: [
        "Zähle die legalen Züge beider Seiten, bevor das Brett eng wird.",
        "Bevorzuge Punkte, die Linien und spätere Drohungen verbinden.",
        "Behandle die Drei-Steine-Schwelle als Wechsel der Prioritäten.",
      ],
      rememberTitle: "Ein Satz zum Merken",
      rememberText: "<strong>Du kannst verlieren, weil du auf weniger als drei Steine reduziert wirst oder weil du keinen legalen Zug mehr hast.</strong>",
    },
    resources: {
      title: "Ressourcen",
      externalTitle: "Externe Strategiequelle",
      externalBody: "Die NMM Strategy-Seite sammelt umfangreicheres Material zu Eröffnungen, Struktur und Endspielen, wenn du tiefer einsteigen willst.",
      externalCta: "NMM Strategy öffnen",
      appTitle: "Nutze die App weiter",
      appBody: "Sanmill ist weiterhin der beste Ort, um jeweils genau eine Änderung zu testen. Kurze wiederholbare Partien machen Fortschritt sichtbar.",
      repoCta: "Sanmill-Repository öffnen",
    },
    footer: {
      note: "Eine kurze fokussierte Übung ist oft hilfreicher als ein langer Artikel. Nimm dir hier eine Idee mit und probiere sie in deiner nächsten Partie aus.",
    },
  },
  el: {
    meta: {
      title: "Sanmill | Σημειώσεις στρατηγικής για Nine Men's Morris",
      description: "Σύντομες σημειώσεις και ασκήσεις για παίκτες Nine Men's Morris στο Sanmill.",
    },
    nav: {
      fixes: "Διορθώσεις",
      drills: "Ασκήσεις",
      mistakes: "Συνήθειες",
      resources: "Πόροι",
    },
    hero: {
      eyebrow: "Στρατηγική Nine Men's Morris",
      title: "Παίξε πιο ήρεμα.<br>Φτιάξε δύο απειλές.<br>Κράτα ζωντανές τις κινήσεις σου.",
      lead: "Αυτή η σελίδα είναι για παίκτες Sanmill που θέλουν ένα σύντομο πλάνο και όχι βιβλίο θεωρίας. Εστίασε σε μία αλλαγή στα επόμενα παιχνίδια σου.",
      rules: "<strong>Σημείωση κανόνων:</strong> Το κανονικό Nine Men's Morris έχει φάση τοποθέτησης, φάση κίνησης σε γειτονικά σημεία και πτήση όταν μια πλευρά έχει τρία πιόνια.",
      primary: "Δείξε τις διορθώσεις",
      secondary: "Άνοιγμα πόρων",
    },
    tips: [
      "Μέτρα πρώτα τις νόμιμες κινήσεις και μετά το υλικό.",
      "Ρώτα αν κάθε κίνηση δημιουργεί δεύτερη απειλή.",
      "Κοντά στα τρία πιόνια κοίτα πρώτα τις απειλές πτήσης.",
    ],
    fixes: {
      title: "Τρεις συνηθισμένες διορθώσεις",
      cards: [
        {
          title: "Διόρθωση A: Σου τελειώνουν οι κινήσεις",
          body: "Αυτό είναι πρόβλημα κινητικότητας. Στη φάση κίνησης προτίμησε την κίνηση που κρατά σταθερές ή αυξάνει τις νόμιμες κινήσεις σου.",
        },
        {
          title: "Διόρθωση B: Δεν χτίζεις πίεση",
          body: "Αυτό είναι πρόβλημα δομής. Στη φάση τοποθέτησης προτίμησε σημεία σύνδεσης και άπλωσε τα πιόνια σου σε διαφορετικούς δακτυλίους.",
        },
        {
          title: "Διόρθωση C: Οι μύλοι σου δεν αλλάζουν το παιχνίδι",
          body: "Αυτό είναι πρόβλημα τέμπο. Μην ανοίγεις ξανά τον ίδιο μύλο αυτόματα αν η αφαίρεση δεν βελτιώνει τη θέση σου.",
        },
      ],
    },
    drills: {
      title: "Τρεις σύντομες ασκήσεις",
      items: [
        "Παίξε τρία παιχνίδια και απόρριψε κάθε κίνηση που μειώνει τις νόμιμες κινήσεις σου, εκτός αν κερδίζει υλικό αμέσως.",
        "Παίξε τρία παιχνίδια όπου πρώτα τοποθετείς σε σημεία που συνδέουν πολλές γραμμές πριν κυνηγήσεις πρώιμο μύλο.",
        "Δες μία ήττα και σημείωσε την πρώτη κίνηση όπου οι επιλογές σου έγιναν στενότερες από της AI.",
      ],
    },
    mistakes: {
      title: "Συνήθειες που πρέπει να κόψεις και να κρατήσεις",
      badTitle: "Κόψε αυτές τις συνήθειες",
      bad: [
        "Να αφαιρείς οποιοδήποτε πιόνι μόνο επειδή μπορείς.",
        "Να αμύνεσαι σε μία απειλή χωρίς να φτιάχνεις δεύτερη.",
        "Να στοιβάζεις πιόνια σε έναν δακτύλιο και να χάνεις ευελιξία.",
      ],
      goodTitle: "Κράτα αυτές τις συνήθειες",
      good: [
        "Μέτρα τις νόμιμες κινήσεις και για τις δύο πλευρές πριν στενέψει το ταμπλό.",
        "Προτίμησε σημεία που συνδέουν γραμμές και μελλοντικές απειλές.",
        "Δες το όριο των τριών πιονιών ως αλλαγή προτεραιοτήτων.",
      ],
      rememberTitle: "Μία πρόταση για να θυμάσαι",
      rememberText: "<strong>Μπορείς να χάσεις είτε αν πέσεις κάτω από τρία πιόνια είτε αν δεν έχεις καμία νόμιμη κίνηση.</strong>",
    },
    resources: {
      title: "Πόροι",
      externalTitle: "Εξωτερική πηγή στρατηγικής",
      externalBody: "Η σελίδα NMM Strategy συγκεντρώνει περισσότερο υλικό για ανοίγματα, δομή και φινάλε αν θέλεις να μελετήσεις βαθύτερα.",
      externalCta: "Άνοιγμα NMM Strategy",
      appTitle: "Συνέχισε να χρησιμοποιείς την εφαρμογή",
      appBody: "Το Sanmill παραμένει το καλύτερο μέρος για να δοκιμάζεις μία αλλαγή τη φορά. Τα σύντομα επαναλαμβανόμενα παιχνίδια κάνουν την πρόοδο ορατή.",
      repoCta: "Άνοιγμα αποθετηρίου Sanmill",
    },
    footer: {
      note: "Μια σύντομη εστιασμένη άσκηση είναι συχνά πιο χρήσιμη από ένα μεγάλο άρθρο. Πάρε μία ιδέα από εδώ και δοκίμασέ τη στο επόμενο παιχνίδι σου.",
    },
  },
  es: {
    meta: {
      title: "Sanmill | Notas de estrategia de Nine Men's Morris",
      description: "Notas cortas y ejercicios para jugadores de Nine Men's Morris en Sanmill.",
    },
    nav: {
      fixes: "Ajustes",
      drills: "Ejercicios",
      mistakes: "Hábitos",
      resources: "Recursos",
    },
    hero: {
      eyebrow: "Estrategia de Nine Men's Morris",
      title: "Juega con calma.<br>Crea dos amenazas.<br>Mantén vivos tus movimientos.",
      lead: "Esta página es para jugadores de Sanmill que quieren un plan corto, no un libro de teoría. Concéntrate en un solo cambio en tus próximas partidas.",
      rules: "<strong>Nota de reglas:</strong> El Nine Men's Morris estándar tiene una fase de colocación, una fase de movimiento a puntos adyacentes y vuelo cuando un lado tiene tres piezas.",
      primary: "Mostrar ajustes",
      secondary: "Abrir recursos",
    },
    tips: [
      "Cuenta los movimientos legales antes de contar el material.",
      "Pregunta si cada jugada crea una segunda amenaza.",
      "Cerca de tres piezas, mira primero las amenazas de vuelo.",
    ],
    fixes: {
      title: "Tres ajustes comunes",
      cards: [
        {
          title: "Ajuste A: Te quedas sin movimientos",
          body: "Esto es un problema de movilidad. En la fase de movimiento, prioriza la jugada que mantenga o aumente tus movimientos legales.",
        },
        {
          title: "Ajuste B: Nunca generas presión",
          body: "Esto es un problema de estructura. En la fase de colocación, prioriza los puntos conectores y reparte tus piezas entre anillos.",
        },
        {
          title: "Ajuste C: Tus molinos no cambian la partida",
          body: "Esto es un problema de tempo. No reabras el mismo molino automáticamente si la captura no mejora tu posición.",
        },
      ],
    },
    drills: {
      title: "Tres ejercicios cortos",
      items: [
        "Juega tres partidas y rechaza cualquier jugada que reduzca tus movimientos legales, salvo que gane material de inmediato.",
        "Juega tres partidas colocando primero en puntos que conectan varias líneas antes de perseguir un molino temprano.",
        "Revisa una derrota y marca el primer turno en el que tus opciones se hicieron más estrechas que las de la IA.",
      ],
    },
    mistakes: {
      title: "Hábitos que debes dejar y hábitos que debes mantener",
      badTitle: "Deja estos hábitos",
      bad: [
        "Capturar cualquier pieza solo porque puedes.",
        "Defender una amenaza sin crear otra.",
        "Amontonar piezas en un anillo y perder flexibilidad.",
      ],
      goodTitle: "Mantén estos hábitos",
      good: [
        "Cuenta los movimientos legales de ambos lados antes de que el tablero se cierre.",
        "Prefiere puntos que conecten líneas y amenazas futuras.",
        "Trata el umbral de tres piezas como un cambio de prioridades.",
      ],
      rememberTitle: "Una frase para recordar",
      rememberText: "<strong>Puedes perder por quedar con menos de tres piezas o por no tener ningún movimiento legal.</strong>",
    },
    resources: {
      title: "Recursos",
      externalTitle: "Referencia estratégica externa",
      externalBody: "La página NMM Strategy reúne material más amplio sobre aperturas, estructura y finales si quieres estudiar más a fondo.",
      externalCta: "Abrir NMM Strategy",
      appTitle: "Sigue usando la aplicación",
      appBody: "Sanmill sigue siendo el mejor lugar para probar un cambio a la vez. Las partidas cortas y repetibles hacen visible el progreso.",
      repoCta: "Abrir el repositorio de Sanmill",
    },
    footer: {
      note: "Un ejercicio corto y enfocado suele ser más útil que un artículo largo. Elige una idea aquí y pruébala en tu próxima partida.",
    },
  },
  fr: {
    meta: {
      title: "Sanmill | Notes de stratégie pour Nine Men's Morris",
      description: "Notes courtes et exercices pour les joueurs de Nine Men's Morris dans Sanmill.",
    },
    nav: {
      fixes: "Corrections",
      drills: "Exercices",
      mistakes: "Habitudes",
      resources: "Ressources",
    },
    hero: {
      eyebrow: "Stratégie Nine Men's Morris",
      title: "Joue plus calmement.<br>Crée deux menaces.<br>Garde des coups vivants.",
      lead: "Cette page s'adresse aux joueurs de Sanmill qui veulent un plan court, pas un livre de théorie. Concentre-toi sur un seul ajustement dans tes prochaines parties.",
      rules: "<strong>Note de règles :</strong> Le Nine Men's Morris standard a une phase de placement, une phase de déplacement vers des points adjacents et le vol quand un camp a trois pièces.",
      primary: "Montrer les corrections",
      secondary: "Ouvrir les ressources",
    },
    tips: [
      "Compte les coups légaux avant de compter le matériel.",
      "Demande-toi si chaque coup crée une deuxième menace.",
      "Près de trois pièces, regarde d'abord les menaces de vol.",
    ],
    fixes: {
      title: "Trois corrections fréquentes",
      cards: [
        {
          title: "Correction A : Tu manques de coups",
          body: "C'est un problème de mobilité. En phase de déplacement, privilégie le coup qui maintient ou augmente tes coups légaux.",
        },
        {
          title: "Correction B : Tu ne construis jamais de pression",
          body: "C'est un problème de structure. En phase de placement, privilégie les points de connexion et répartis tes pièces entre les anneaux.",
        },
        {
          title: "Correction C : Tes moulins ne changent pas la partie",
          body: "C'est un problème de tempo. Ne rouvre pas automatiquement le même moulin si la prise n'améliore pas ta position.",
        },
      ],
    },
    drills: {
      title: "Trois exercices courts",
      items: [
        "Joue trois parties et refuse tout coup qui réduit tes coups légaux, sauf s'il gagne immédiatement du matériel.",
        "Joue trois parties en plaçant d'abord sur des points qui relient plusieurs lignes avant de chasser un moulin rapide.",
        "Revois une défaite et marque le premier tour où tes options sont devenues plus étroites que celles de l'IA.",
      ],
    },
    mistakes: {
      title: "Habitudes à abandonner et habitudes à garder",
      badTitle: "Abandonne ces habitudes",
      bad: [
        "Prendre n'importe quelle pièce juste parce que c'est possible.",
        "Défendre une menace sans en créer une autre.",
        "Empiler les pièces sur un anneau et perdre de la souplesse.",
      ],
      goodTitle: "Garde ces habitudes",
      good: [
        "Compte les coups légaux des deux camps avant que le plateau ne se resserre.",
        "Préfère les points qui relient des lignes et des menaces futures.",
        "Traite le seuil des trois pièces comme un changement de priorités.",
      ],
      rememberTitle: "Une phrase à retenir",
      rememberText: "<strong>Tu peux perdre en tombant sous trois pièces ou en n'ayant plus aucun coup légal.</strong>",
    },
    resources: {
      title: "Ressources",
      externalTitle: "Référence stratégique externe",
      externalBody: "La page NMM Strategy rassemble du contenu plus large sur les ouvertures, la structure et les fins de partie si tu veux aller plus loin.",
      externalCta: "Ouvrir NMM Strategy",
      appTitle: "Continue à utiliser l'application",
      appBody: "Sanmill reste le meilleur endroit pour tester un seul changement à la fois. Les parties courtes et répétables rendent les progrès visibles.",
      repoCta: "Ouvrir le dépôt Sanmill",
    },
    footer: {
      note: "Un exercice court et ciblé est souvent plus utile qu'un long article. Prends une idée ici et essaie-la dans ta prochaine partie.",
    },
  },
  hi: {
    meta: {
      title: "Sanmill | Nine Men's Morris रणनीति नोट्स",
      description: "Sanmill के Nine Men's Morris खिलाड़ियों के लिए छोटे नोट्स और अभ्यास।",
    },
    nav: {
      fixes: "सुधार",
      drills: "अभ्यास",
      mistakes: "आदतें",
      resources: "संसाधन",
    },
    hero: {
      eyebrow: "Nine Men's Morris रणनीति",
      title: "शांत खेलें।<br>दो खतरे बनाएं।<br>अपनी चालें जीवित रखें।",
      lead: "यह पृष्ठ उन Sanmill खिलाड़ियों के लिए है जो सिद्धांत की किताब नहीं, एक छोटा व्यावहारिक प्लान चाहते हैं। अपनी अगली बाजियों में एक बदलाव पर ध्यान दें।",
      rules: "<strong>नियम नोट:</strong> मानक Nine Men's Morris में placing phase, adjacent point पर moving phase, और तीन pieces बचने पर flying होता है।",
      primary: "सुधार दिखाएँ",
      secondary: "संसाधन खोलें",
    },
    tips: [
      "material गिनने से पहले legal moves गिनें।",
      "पूछें कि क्या हर चाल दूसरा खतरा बनाती है।",
      "तीन pieces के पास पहुँचते ही पहले flying threats देखें।",
    ],
    fixes: {
      title: "तीन सामान्य सुधार",
      cards: [
        {
          title: "सुधार A: आपकी चालें खत्म हो जाती हैं",
          body: "यह mobility की समस्या है। moving phase में उस चाल को प्राथमिकता दें जो आपके legal moves को स्थिर रखे या बढ़ाए।",
        },
        {
          title: "सुधार B: आप दबाव नहीं बना पाते",
          body: "यह structure की समस्या है। placing phase में connector points लें और rings में फैलकर खेलें।",
        },
        {
          title: "सुधार C: आपकी mills खेल नहीं बदलतीं",
          body: "यह tempo की समस्या है। अगर capture आपकी स्थिति नहीं सुधारता, तो वही mill बार-बार न खोलें।",
        },
      ],
    },
    drills: {
      title: "तीन छोटे अभ्यास",
      items: [
        "तीन खेल खेलें और ऐसी कोई चाल न लें जो legal-move count घटाए, जब तक वह तुरंत material न दिलाए।",
        "तीन खेलों में early mill के पीछे भागने से पहले उन points पर रखें जो कई lines जोड़ते हैं।",
        "एक हार की समीक्षा करें और वह पहला turn चिन्हित करें जब आपके विकल्प AI से संकरे हो गए।",
      ],
    },
    mistakes: {
      title: "छोड़ने और रखने लायक आदतें",
      badTitle: "ये आदतें छोड़ें",
      bad: [
        "सिर्फ मौका होने पर कोई भी piece पकड़ लेना।",
        "एक खतरे को रोकना, लेकिन दूसरा खतरा न बनाना।",
        "एक ring पर pieces भर देना और flexibility खो देना।",
      ],
      goodTitle: "ये आदतें रखें",
      good: [
        "बोर्ड तंग होने से पहले दोनों पक्षों के legal moves गिनें।",
        "उन points को चुनें जो lines और future threats जोड़ते हैं।",
        "three-piece threshold को priorities के बदलाव की तरह देखें।",
      ],
      rememberTitle: "याद रखने के लिए एक वाक्य",
      rememberText: "<strong>आप तीन pieces से नीचे गिरने पर भी हार सकते हैं, और कोई legal move न होने पर भी।</strong>",
    },
    resources: {
      title: "संसाधन",
      externalTitle: "बाहरी रणनीति संदर्भ",
      externalBody: "अगर आप आगे पढ़ना चाहते हैं, तो NMM Strategy पृष्ठ openings, structure और endgames पर बड़ा संग्रह देता है।",
      externalCta: "NMM Strategy खोलें",
      appTitle: "ऐप का उपयोग जारी रखें",
      appBody: "एक बार में एक बदलाव जाँचने के लिए Sanmill अब भी सबसे अच्छी जगह है। छोटे दोहराए जा सकने वाले खेल प्रगति को दिखाते हैं।",
      repoCta: "Sanmill repository खोलें",
    },
    footer: {
      note: "अक्सर एक छोटा और केंद्रित अभ्यास, लंबे लेख से अधिक उपयोगी होता है। यहाँ से एक विचार लें और अगली बाजी में आज़माएँ।",
    },
  },
  hr: {
    meta: {
      title: "Sanmill | Bilješke strategije za Nine Men's Morris",
      description: "Kratke bilješke i vježbe za igrače Nine Men's Morris u Sanmillu.",
    },
    nav: {
      fixes: "Popravci",
      drills: "Vježbe",
      mistakes: "Navike",
      resources: "Resursi",
    },
    hero: {
      eyebrow: "Strategija za Nine Men's Morris",
      title: "Igraj mirnije.<br>Stvori dvije prijetnje.<br>Održi svoje poteze živima.",
      lead: "Ova je stranica za igrače Sanmilla koji žele kratak plan, a ne knjigu teorije. Usredotoči se na jednu promjenu u sljedećim partijama.",
      rules: "<strong>Napomena o pravilima:</strong> Standardni Nine Men's Morris ima fazu postavljanja, fazu pomicanja na susjedne točke i letenje kada strana ima tri figure.",
      primary: "Pokaži popravke",
      secondary: "Otvori resurse",
    },
    tips: [
      "Broji zakonite poteze prije nego što brojiš figure.",
      "Pitaj se stvara li svaki potez drugu prijetnju.",
      "Kad ostanu tri figure, prvo gledaj prijetnje letenja.",
    ],
    fixes: {
      title: "Tri česta popravka",
      cards: [
        {
          title: "Popravak A: Ostaješ bez poteza",
          body: "To je problem mobilnosti. U fazi pomicanja biraj potez koji održava ili povećava broj tvojih zakonitih poteza.",
        },
        {
          title: "Popravak B: Ne stvaraš pritisak",
          body: "To je problem strukture. U fazi postavljanja biraj spojne točke i rasporedi figure po prstenovima.",
        },
        {
          title: "Popravak C: Tvoji mlinovi ne mijenjaju partiju",
          body: "To je problem tempa. Nemoj automatski ponovno otvarati isti mlin ako uzimanje ne poboljšava tvoju poziciju.",
        },
      ],
    },
    drills: {
      title: "Tri kratke vježbe",
      items: [
        "Odigraj tri partije i odbij svaki potez koji smanjuje broj tvojih zakonitih poteza, osim ako odmah ne osvaja materijal.",
        "U tri partije prvo postavljaj na točke koje povezuju više linija prije nego što loviš rani mlin.",
        "Pregledaj jedan poraz i označi prvi potez kada su ti opcije postale uže od AI opcija.",
      ],
    },
    mistakes: {
      title: "Navike koje treba odbaciti i zadržati",
      badTitle: "Odbaci ove navike",
      bad: [
        "Uzeti bilo koju figuru samo zato što možeš.",
        "Braniti jednu prijetnju bez stvaranja druge.",
        "Nagurati figure na jedan prsten i izgubiti fleksibilnost.",
      ],
      goodTitle: "Zadrži ove navike",
      good: [
        "Broji zakonite poteze obje strane prije nego što se ploča stisne.",
        "Biraj točke koje povezuju linije i buduće prijetnje.",
        "Prag od tri figure tretiraj kao promjenu prioriteta.",
      ],
      rememberTitle: "Jedna rečenica za pamćenje",
      rememberText: "<strong>Možeš izgubiti ako padneš ispod tri figure ili ako nemaš nijedan zakonit potez.</strong>",
    },
    resources: {
      title: "Resursi",
      externalTitle: "Vanjska strateška referenca",
      externalBody: "Stranica NMM Strategy skuplja širi materijal o otvaranjima, strukturi i završnicama ako želiš dublje učiti.",
      externalCta: "Otvori NMM Strategy",
      appTitle: "Nastavi koristiti aplikaciju",
      appBody: "Sanmill je i dalje najbolje mjesto za testiranje jedne promjene odjednom. Kratke ponovljive partije jasno pokazuju napredak.",
      repoCta: "Otvori repozitorij Sanmilla",
    },
    footer: {
      note: "Kratka fokusirana vježba često je korisnija od dugog članka. Uzmi jednu ideju odavde i isprobaj je u sljedećoj partiji.",
    },
  },
  hu: {
    meta: {
      title: "Sanmill | Stratégiai jegyzetek a Nine Men's Morrishoz",
      description: "Rövid jegyzetek és gyakorlatok a Sanmill Nine Men's Morris játékosainak.",
    },
    nav: {
      fixes: "Javítások",
      drills: "Gyakorlatok",
      mistakes: "Szokások",
      resources: "Források",
    },
    hero: {
      eyebrow: "Nine Men's Morris stratégia",
      title: "Játssz nyugodtabban.<br>Építs két fenyegetést.<br>Tartsd életben a lépéseidet.",
      lead: "Ez az oldal azoknak a Sanmill-játékosoknak szól, akik rövid tervet akarnak, nem elméleti könyvet. A következő partijaidban egyetlen változtatásra figyelj.",
      rules: "<strong>Szabálymegjegyzés:</strong> A standard Nine Men's Morrisban van helyezési fázis, szomszédos pontokra történő mozgási fázis, és három korongnál repülés.",
      primary: "Mutasd a javításokat",
      secondary: "Források megnyitása",
    },
    tips: [
      "Előbb a legális lépéseket számold, csak utána az anyagot.",
      "Kérdezd meg, hogy minden lépés létrehoz-e egy második fenyegetést.",
      "Három korong közelében előbb a repülési fenyegetéseket nézd.",
    ],
    fixes: {
      title: "Három gyakori javítás",
      cards: [
        {
          title: "Javítás A: Elfogynak a lépéseid",
          body: "Ez mobilitási probléma. A mozgó fázisban azt a lépést válaszd, amely stabilan tartja vagy növeli a legális lépéseid számát.",
        },
        {
          title: "Javítás B: Nem építesz nyomást",
          body: "Ez szerkezeti probléma. A helyezési fázisban részesítsd előnyben a kapcsolódó pontokat, és oszd szét a korongokat a gyűrűk között.",
        },
        {
          title: "Javítás C: A malmaid nem változtatják meg a partit",
          body: "Ez tempóprobléma. Ne nyisd újra automatikusan ugyanazt a malmot, ha a levétel nem javítja az állásodat.",
        },
      ],
    },
    drills: {
      title: "Három rövid gyakorlat",
      items: [
        "Játssz három partit, és utasíts el minden olyan lépést, amely csökkenti a legális lépéseid számát, hacsak nem nyer azonnal anyagot.",
        "Három partiban előbb olyan pontokra helyezz, amelyek több vonalat kötnek össze, és csak utána üldözd a korai malmot.",
        "Nézz vissza egy vereséget, és jelöld meg azt az első kört, amikor a lehetőségeid szűkebbek lettek, mint az AI-é.",
      ],
    },
    mistakes: {
      title: "Szokások, amelyeket el kell hagyni és meg kell tartani",
      badTitle: "Ezeket hagyd el",
      bad: [
        "Bármelyik korong levétele csak azért, mert lehet.",
        "Egy fenyegetés védése új fenyegetés létrehozása nélkül.",
        "A korongok egy gyűrűre zsúfolása és a rugalmasság elvesztése.",
      ],
      goodTitle: "Ezeket tartsd meg",
      good: [
        "Számold mindkét fél legális lépéseit, mielőtt a tábla beszűkül.",
        "Részesítsd előnyben azokat a pontokat, amelyek vonalakat és jövőbeli fenyegetéseket kötnek össze.",
        "A három korongos küszöböt tekintsd prioritásváltásnak.",
      ],
      rememberTitle: "Egy mondat, amit érdemes megjegyezni",
      rememberText: "<strong>Úgy is veszíthetsz, hogy három korong alá csökkensz, és úgy is, hogy nincs egyetlen legális lépésed sem.</strong>",
    },
    resources: {
      title: "Források",
      externalTitle: "Külső stratégiai hivatkozás",
      externalBody: "Az NMM Strategy oldal szélesebb anyagot gyűjt a megnyitásokról, szerkezetről és végjátékokról, ha mélyebbre akarsz menni.",
      externalCta: "NMM Strategy megnyitása",
      appTitle: "Használd tovább az alkalmazást",
      appBody: "A Sanmill továbbra is a legjobb hely arra, hogy egyszerre csak egy változtatást tesztelj. A rövid ismételhető partik láthatóvá teszik a fejlődést.",
      repoCta: "A Sanmill tároló megnyitása",
    },
    footer: {
      note: "Egy rövid, fókuszált gyakorlat gyakran hasznosabb, mint egy hosszú cikk. Vigyél innen egy ötletet, és próbáld ki a következő partidban.",
    },
  },
  it: {
    meta: {
      title: "Sanmill | Note strategiche per Nine Men's Morris",
      description: "Note brevi ed esercizi per i giocatori di Nine Men's Morris su Sanmill.",
    },
    nav: {
      fixes: "Correzioni",
      drills: "Esercizi",
      mistakes: "Abitudini",
      resources: "Risorse",
    },
    hero: {
      eyebrow: "Strategia di Nine Men's Morris",
      title: "Gioca con calma.<br>Crea due minacce.<br>Tieni vive le tue mosse.",
      lead: "Questa pagina è per i giocatori di Sanmill che vogliono un piano breve, non un libro di teoria. Concentrati su un solo cambiamento nelle prossime partite.",
      rules: "<strong>Nota sulle regole:</strong> Il Nine Men's Morris standard ha una fase di piazzamento, una fase di movimento verso punti adiacenti e il volo quando un lato ha tre pezzi.",
      primary: "Mostra le correzioni",
      secondary: "Apri le risorse",
    },
    tips: [
      "Conta le mosse legali prima di contare il materiale.",
      "Chiediti se ogni mossa crea una seconda minaccia.",
      "Vicino ai tre pezzi, guarda prima le minacce di volo.",
    ],
    fixes: {
      title: "Tre correzioni comuni",
      cards: [
        {
          title: "Correzione A: Finisci le mosse",
          body: "È un problema di mobilità. Nella fase di movimento preferisci la mossa che mantiene stabili o aumenta le tue mosse legali.",
        },
        {
          title: "Correzione B: Non costruisci pressione",
          body: "È un problema di struttura. Nella fase di piazzamento preferisci i punti di collegamento e distribuisci i pezzi tra gli anelli.",
        },
        {
          title: "Correzione C: I tuoi mulini non cambiano la partita",
          body: "È un problema di tempo. Non riaprire automaticamente lo stesso mulino se la cattura non migliora la tua posizione.",
        },
      ],
    },
    drills: {
      title: "Tre esercizi brevi",
      items: [
        "Gioca tre partite e rifiuta ogni mossa che riduce il numero delle tue mosse legali, a meno che non vinca subito materiale.",
        "Gioca tre partite in cui piazzi prima sui punti che collegano più linee, prima di inseguire un mulino precoce.",
        "Rivedi una sconfitta e segna il primo turno in cui le tue opzioni sono diventate più strette di quelle della IA.",
      ],
    },
    mistakes: {
      title: "Abitudini da lasciare e abitudini da tenere",
      badTitle: "Lascia queste abitudini",
      bad: [
        "Catturare qualunque pezzo solo perché puoi.",
        "Difendere una minaccia senza crearne un'altra.",
        "Ammassare i pezzi su un anello e perdere flessibilità.",
      ],
      goodTitle: "Tieni queste abitudini",
      good: [
        "Conta le mosse legali di entrambi i lati prima che la posizione si stringa.",
        "Preferisci i punti che collegano linee e minacce future.",
        "Tratta la soglia dei tre pezzi come un cambio di priorità.",
      ],
      rememberTitle: "Una frase da ricordare",
      rememberText: "<strong>Puoi perdere sia scendendo sotto tre pezzi sia restando senza alcuna mossa legale.</strong>",
    },
    resources: {
      title: "Risorse",
      externalTitle: "Riferimento strategico esterno",
      externalBody: "La pagina NMM Strategy raccoglie materiale più ampio su aperture, struttura e finali se vuoi approfondire.",
      externalCta: "Apri NMM Strategy",
      appTitle: "Continua a usare l'app",
      appBody: "Sanmill resta il posto migliore per testare un cambiamento alla volta. Le partite brevi e ripetibili rendono visibili i progressi.",
      repoCta: "Apri il repository di Sanmill",
    },
    footer: {
      note: "Un esercizio breve e mirato è spesso più utile di un lungo articolo. Prendi un'idea da qui e provala nella prossima partita.",
    },
  },
  pl: {
    meta: {
      title: "Sanmill | Notatki strategiczne do Nine Men's Morris",
      description: "Krótkie notatki i ćwiczenia dla graczy Nine Men's Morris w Sanmill.",
    },
    nav: {
      fixes: "Poprawki",
      drills: "Ćwiczenia",
      mistakes: "Nawyki",
      resources: "Zasoby",
    },
    hero: {
      eyebrow: "Strategia Nine Men's Morris",
      title: "Graj spokojniej.<br>Twórz dwa zagrożenia.<br>Utrzymuj swoje ruchy przy życiu.",
      lead: "Ta strona jest dla graczy Sanmill, którzy chcą krótkiego planu, a nie książki z teorią. Skup się na jednej zmianie w najbliższych partiach.",
      rules: "<strong>Uwaga o zasadach:</strong> Standardowe Nine Men's Morris ma fazę stawiania, fazę ruchu do sąsiednich punktów i latanie, gdy strona ma trzy piony.",
      primary: "Pokaż poprawki",
      secondary: "Otwórz zasoby",
    },
    tips: [
      "Licz legalne ruchy, zanim policzysz materiał.",
      "Pytaj, czy każdy ruch tworzy drugie zagrożenie.",
      "Przy trzech pionach najpierw patrz na zagrożenia latania.",
    ],
    fixes: {
      title: "Trzy częste poprawki",
      cards: [
        {
          title: "Poprawka A: Kończą ci się ruchy",
          body: "To problem mobilności. W fazie ruchu wybieraj ruch, który utrzymuje lub zwiększa liczbę twoich legalnych ruchów.",
        },
        {
          title: "Poprawka B: Nie budujesz presji",
          body: "To problem struktury. W fazie stawiania wybieraj punkty łączące i rozkładaj piony między pierścieniami.",
        },
        {
          title: "Poprawka C: Twoje młyny nie zmieniają partii",
          body: "To problem tempa. Nie otwieraj automatycznie tego samego młyna, jeśli zbicie nie poprawia pozycji.",
        },
      ],
    },
    drills: {
      title: "Trzy krótkie ćwiczenia",
      items: [
        "Zagraj trzy partie i odrzuć każdy ruch, który zmniejsza liczbę twoich legalnych ruchów, chyba że natychmiast wygrywa materiał.",
        "Zagraj trzy partie, w których najpierw stawiasz na punktach łączących wiele linii, zanim zaczniesz gonić wczesny młyn.",
        "Przejrzyj jedną porażkę i zaznacz pierwszy ruch, gdy twoje opcje zrobiły się węższe niż opcje AI.",
      ],
    },
    mistakes: {
      title: "Nawyki do porzucenia i do zachowania",
      badTitle: "Porzuć te nawyki",
      bad: [
        "Zbijanie dowolnego pionu tylko dlatego, że możesz.",
        "Bronienie jednej groźby bez tworzenia drugiej.",
        "Upychanie pionów na jednym pierścieniu i tracenie elastyczności.",
      ],
      goodTitle: "Zachowaj te nawyki",
      good: [
        "Licz legalne ruchy obu stron, zanim pozycja się zamknie.",
        "Wybieraj punkty, które łączą linie i przyszłe groźby.",
        "Traktuj próg trzech pionów jako zmianę priorytetów.",
      ],
      rememberTitle: "Jedno zdanie do zapamiętania",
      rememberText: "<strong>Możesz przegrać, schodząc poniżej trzech pionów albo nie mając żadnego legalnego ruchu.</strong>",
    },
    resources: {
      title: "Zasoby",
      externalTitle: "Zewnętrzne źródło strategii",
      externalBody: "Strona NMM Strategy zbiera szersze materiały o otwarciach, strukturze i końcówkach, jeśli chcesz studiować głębiej.",
      externalCta: "Otwórz NMM Strategy",
      appTitle: "Korzystaj dalej z aplikacji",
      appBody: "Sanmill nadal jest najlepszym miejscem do testowania jednej zmiany naraz. Krótkie, powtarzalne partie pokazują postęp.",
      repoCta: "Otwórz repozytorium Sanmill",
    },
    footer: {
      note: "Krótki, skupiony trening jest często bardziej użyteczny niż długi artykuł. Weź stąd jeden pomysł i wypróbuj go w następnej partii.",
    },
  },
  ps: {
    meta: {
      title: "Sanmill | د Nine Men's Morris د ستراتېژۍ یادښتونه",
      description: "په Sanmill کې د Nine Men's Morris لوبغاړو لپاره لنډ یادښتونه او تمرینونه.",
    },
    nav: {
      fixes: "سمونونه",
      drills: "تمرینونه",
      mistakes: "عادتونه",
      resources: "سرچینې",
    },
    hero: {
      eyebrow: "د Nine Men's Morris ستراتېژي",
      title: "په ارامۍ ولوبېږه.<br>دوه ګواښونه جوړ کړه.<br>خپل حرکتونه ژوندي وساته.",
      lead: "دا پاڼه د هغو Sanmill لوبغاړو لپاره ده چې لنډ پلان غواړي، نه د نظريې کتاب. په خپلو راتلونکو لوبو کې پر یوه بدلون تمرکز وکړه.",
      rules: "<strong>د قاعدو یادونه:</strong> معیاري Nine Men's Morris د ایښودلو پړاو، د نږدې نقطو پر لور د حرکت پړاو، او د درې ټوټو په وخت کې الوتنه لري.",
      primary: "سمونونه وښیه",
      secondary: "سرچینې پرانیزه",
    },
    tips: [
      "له موادو مخکې قانوني حرکتونه وشمېره.",
      "وګوره چې هر حرکت دوهم ګواښ جوړوي که نه.",
      "د درې ټوټو په پوله کې لومړی د الوتنې ګواښونه وګوره.",
    ],
    fixes: {
      title: "درې عام سمونونه",
      cards: [
        {
          title: "سمون A: ستا حرکتونه ختمېږي",
          body: "دا د خوځښت ستونزه ده. د حرکت په پړاو کې هغه حرکت غوره کړه چې ستا قانوني حرکتونه ثابت وساتي یا زیات کړي.",
        },
        {
          title: "سمون B: فشار نه جوړوې",
          body: "دا د جوړښت ستونزه ده. د ایښودلو په پړاو کې د نښلونکو نقطو ته لومړیتوب ورکړه او پر کړیو خپور شه.",
        },
        {
          title: "سمون C: ستا درې-کرښې لوبه نه بدلوي",
          body: "دا د تمپو ستونزه ده. هماغه درې-کرښه بېځایه بیا مه خلاصوه، مګر که نیونه دې حالت ښه کوي.",
        },
      ],
    },
    drills: {
      title: "درې لنډ تمرینونه",
      items: [
        "درې لوبې وکړه او هر هغه حرکت رد کړه چې ستا قانوني حرکتونه کموي، مګر که سمدستي مواد نه ګټي.",
        "درې لوبې وکړه چې پکې د ژر درې-کرښې پر ځای لومړی په هغو نقطو کې کښېږدې چې څو کرښې نښلوي.",
        "یوه ماتې وګوره او هغه لومړی وار په نښه کړه چې ستا انتخابونه د AI له انتخابونو تنګ شول.",
      ],
    },
    mistakes: {
      title: "هغه عادتونه چې باید پرېښودل او ساتل شي",
      badTitle: "دا عادتونه پرېږده",
      bad: [
        "هره ټوټه یوازې ځکه اخستل چې کولی شې.",
        "یو ګواښ دفاع کول بې له دې چې بل ګواښ جوړ کړې.",
        "په یوه کړۍ کې د ټوټو راټولول او انعطاف له لاسه ورکول.",
      ],
      goodTitle: "دا عادتونه وساته",
      good: [
        "مخکې له دې چې تخته تنګه شي د دواړو خواوو قانوني حرکتونه وشمېره.",
        "هغو نقطو ته لومړیتوب ورکړه چې کرښې او راتلونکي ګواښونه نښلوي.",
        "د درې ټوټو پوله د لومړيتوبونو د بدلون په توګه وګڼه.",
      ],
      rememberTitle: "یوه جمله چې باید یاده وساتې",
      rememberText: "<strong>ته یا د درې ټوټو څخه په کمېدو بایللی شې او یا هم د قانوني حرکت د نه لرلو له امله.</strong>",
    },
    resources: {
      title: "سرچینې",
      externalTitle: "بهرنی ستراتېژیک مرجع",
      externalBody: "د NMM Strategy پاڼه د پرانیستو، جوړښت او پایلوبو په اړه پراخ مواد راټولوي که ژوره مطالعه غواړې.",
      externalCta: "NMM Strategy پرانیزه",
      appTitle: "د اپ کارولو ته دوام ورکړه",
      appBody: "Sanmill لا هم تر ټولو ښه ځای دی چې په یو وخت کې یوه بدلون وازمایې. لنډې تکرارېدونکې لوبې پرمختګ ښکاره کوي.",
      repoCta: "د Sanmill زېرمتون پرانیزه",
    },
    footer: {
      note: "لنډ تمرکز لرونکی تمرین ډېر وخت له اوږدې مقالې ګټور وي. له دې ځایه یوه مفکوره واخله او په راتلونکې لوبه کې یې وازمویه.",
    },
  },
  "pt-BR": {
    meta: {
      title: "Sanmill | Notas de estratégia de Nine Men's Morris",
      description: "Notas curtas e exercícios para jogadores de Nine Men's Morris no Sanmill.",
    },
    nav: {
      fixes: "Ajustes",
      drills: "Treinos",
      mistakes: "Hábitos",
      resources: "Recursos",
    },
    hero: {
      eyebrow: "Estratégia de Nine Men's Morris",
      title: "Jogue com calma.<br>Crie duas ameaças.<br>Mantenha seus lances vivos.",
      lead: "Esta página é para jogadores de Sanmill que querem um plano curto, não um livro de teoria. Foque em um único ajuste nas próximas partidas.",
      rules: "<strong>Nota de regras:</strong> O Nine Men's Morris padrão tem fase de colocação, fase de movimento para pontos adjacentes e voo quando um lado tem três peças.",
      primary: "Mostrar ajustes",
      secondary: "Abrir recursos",
    },
    tips: [
      "Conte os lances legais antes de contar o material.",
      "Pergunte se cada lance cria uma segunda ameaça.",
      "Perto de três peças, veja primeiro as ameaças de voo.",
    ],
    fixes: {
      title: "Três ajustes comuns",
      cards: [
        {
          title: "Ajuste A: Seus lances acabam",
          body: "Isso é um problema de mobilidade. Na fase de movimento, prefira o lance que mantém ou aumenta seus lances legais.",
        },
        {
          title: "Ajuste B: Você não cria pressão",
          body: "Isso é um problema de estrutura. Na fase de colocação, priorize pontos conectores e espalhe suas peças pelos anéis.",
        },
        {
          title: "Ajuste C: Seus moinhos não mudam a partida",
          body: "Isso é um problema de tempo. Não reabra o mesmo moinho automaticamente se a captura não melhora sua posição.",
        },
      ],
    },
    drills: {
      title: "Três treinos curtos",
      items: [
        "Jogue três partidas e recuse qualquer lance que reduza sua contagem de lances legais, a menos que ganhe material imediatamente.",
        "Jogue três partidas em que você coloque primeiro em pontos que conectam várias linhas antes de perseguir um moinho cedo demais.",
        "Revise uma derrota e marque o primeiro turno em que suas opções ficaram mais estreitas do que as da IA.",
      ],
    },
    mistakes: {
      title: "Hábitos para largar e hábitos para manter",
      badTitle: "Largue estes hábitos",
      bad: [
        "Capturar qualquer peça só porque pode.",
        "Defender uma ameaça sem criar outra.",
        "Amontoar peças em um único anel e perder flexibilidade.",
      ],
      goodTitle: "Mantenha estes hábitos",
      good: [
        "Conte os lances legais dos dois lados antes de o tabuleiro apertar.",
        "Prefira pontos que conectam linhas e ameaças futuras.",
        "Trate o limite de três peças como uma mudança de prioridades.",
      ],
      rememberTitle: "Uma frase para lembrar",
      rememberText: "<strong>Você pode perder ao ficar com menos de três peças ou ao não ter nenhum lance legal.</strong>",
    },
    resources: {
      title: "Recursos",
      externalTitle: "Referência externa de estratégia",
      externalBody: "A página NMM Strategy reúne material mais amplo sobre aberturas, estrutura e finais se você quiser estudar mais.",
      externalCta: "Abrir NMM Strategy",
      appTitle: "Continue usando o app",
      appBody: "Sanmill ainda é o melhor lugar para testar uma mudança de cada vez. Partidas curtas e repetíveis deixam o progresso visível.",
      repoCta: "Abrir o repositório do Sanmill",
    },
    footer: {
      note: "Um treino curto e focado costuma ser mais útil do que um artigo longo. Escolha uma ideia aqui e teste na sua próxima partida.",
    },
  },
  ro: {
    meta: {
      title: "Sanmill | Note strategice pentru Nine Men's Morris",
      description: "Note scurte și exerciții pentru jucătorii de Nine Men's Morris din Sanmill.",
    },
    nav: {
      fixes: "Ajustări",
      drills: "Exerciții",
      mistakes: "Obiceiuri",
      resources: "Resurse",
    },
    hero: {
      eyebrow: "Strategie Nine Men's Morris",
      title: "Joacă mai calm.<br>Creează două amenințări.<br>Păstrează-ți mutările vii.",
      lead: "Această pagină este pentru jucătorii Sanmill care vor un plan scurt, nu o carte de teorie. Concentrează-te pe o singură schimbare în următoarele partide.",
      rules: "<strong>Notă de reguli:</strong> Nine Men's Morris standard are fază de plasare, fază de mutare pe puncte adiacente și zbor când o parte are trei piese.",
      primary: "Arată ajustările",
      secondary: "Deschide resursele",
    },
    tips: [
      "Numără mutările legale înainte să numeri materialul.",
      "Întreabă-te dacă fiecare mutare creează a doua amenințare.",
      "Aproape de trei piese, uită-te întâi la amenințările de zbor.",
    ],
    fixes: {
      title: "Trei ajustări comune",
      cards: [
        {
          title: "Ajustarea A: Rămâi fără mutări",
          body: "Aceasta este o problemă de mobilitate. În faza de mutare, preferă mutarea care îți păstrează sau îți crește numărul de mutări legale.",
        },
        {
          title: "Ajustarea B: Nu construiești presiune",
          body: "Aceasta este o problemă de structură. În faza de plasare, preferă punctele de legătură și răspândește piesele pe inele.",
        },
        {
          title: "Ajustarea C: Moarele tale nu schimbă partida",
          body: "Aceasta este o problemă de tempo. Nu redeschide automat aceeași moară dacă scoaterea nu îți îmbunătățește poziția.",
        },
      ],
    },
    drills: {
      title: "Trei exerciții scurte",
      items: [
        "Joacă trei partide și refuză orice mutare care îți reduce numărul de mutări legale, cu excepția celor care câștigă imediat material.",
        "Joacă trei partide în care pui mai întâi pe puncte care conectează mai multe linii înainte să urmărești o moară timpurie.",
        "Revizuiește o înfrângere și marchează primul tur în care opțiunile tale au devenit mai înguste decât ale AI-ului.",
      ],
    },
    mistakes: {
      title: "Obiceiuri de lăsat și obiceiuri de păstrat",
      badTitle: "Lasă aceste obiceiuri",
      bad: [
        "Să scoți orice piesă doar pentru că poți.",
        "Să aperi o amenințare fără să creezi alta.",
        "Să înghesui piesele pe un singur inel și să pierzi flexibilitatea.",
      ],
      goodTitle: "Păstrează aceste obiceiuri",
      good: [
        "Numără mutările legale ale ambelor părți înainte ca poziția să se strângă.",
        "Preferă punctele care conectează linii și amenințări viitoare.",
        "Tratează pragul de trei piese ca pe o schimbare de priorități.",
      ],
      rememberTitle: "O propoziție de ținut minte",
      rememberText: "<strong>Poți pierde fie coborând sub trei piese, fie rămânând fără nicio mutare legală.</strong>",
    },
    resources: {
      title: "Resurse",
      externalTitle: "Referință strategică externă",
      externalBody: "Pagina NMM Strategy adună materiale mai ample despre deschideri, structură și finaluri dacă vrei să studiezi mai adânc.",
      externalCta: "Deschide NMM Strategy",
      appTitle: "Continuă să folosești aplicația",
      appBody: "Sanmill rămâne cel mai bun loc pentru a testa o singură schimbare odată. Partidele scurte și repetabile fac progresul vizibil.",
      repoCta: "Deschide depozitul Sanmill",
    },
    footer: {
      note: "Un exercițiu scurt și concentrat este adesea mai util decât un articol lung. Ia o singură idee de aici și încearc-o în următoarea partidă.",
    },
  },
  sk: {
    meta: {
      title: "Sanmill | Strategické poznámky k Nine Men's Morris",
      description: "Krátke poznámky a cvičenia pre hráčov Nine Men's Morris v Sanmill.",
    },
    nav: {
      fixes: "Úpravy",
      drills: "Cvičenia",
      mistakes: "Návyky",
      resources: "Zdroje",
    },
    hero: {
      eyebrow: "Stratégia Nine Men's Morris",
      title: "Hraj pokojnejšie.<br>Vytvor dve hrozby.<br>Udrž si svoje ťahy živé.",
      lead: "Táto stránka je pre hráčov Sanmill, ktorí chcú krátky plán, nie knihu teórie. V ďalších hrách sa sústreď na jednu zmenu.",
      rules: "<strong>Poznámka k pravidlám:</strong> Štandardný Nine Men's Morris má fázu kladenia, fázu pohybu na susedné body a lietanie, keď má strana tri kamene.",
      primary: "Ukáž úpravy",
      secondary: "Otvoriť zdroje",
    },
    tips: [
      "Najprv počítaj legálne ťahy, potom materiál.",
      "Pýtaj sa, či každý ťah vytvára druhú hrozbu.",
      "Pri troch kameňoch sleduj najprv hrozby lietania.",
    ],
    fixes: {
      title: "Tri bežné úpravy",
      cards: [
        {
          title: "Úprava A: Dochádzajú ti ťahy",
          body: "To je problém mobility. V pohybovej fáze uprednostni ťah, ktorý udrží alebo zvýši počet tvojich legálnych ťahov.",
        },
        {
          title: "Úprava B: Nevyvíjaš tlak",
          body: "To je problém štruktúry. Vo fáze kladenia uprednostni spojovacie body a rozlož kamene medzi prstence.",
        },
        {
          title: "Úprava C: Tvoje mlyny nemenia partiu",
          body: "To je problém tempa. Neotváraj automaticky ten istý mlyn, ak braním nezlepšíš svoju pozíciu.",
        },
      ],
    },
    drills: {
      title: "Tri krátke cvičenia",
      items: [
        "Zahraj tri partie a odmietni každý ťah, ktorý znižuje počet tvojich legálnych ťahov, pokiaľ hneď nezískava materiál.",
        "V troch partiách najprv klaď na body, ktoré spájajú viac línií, a až potom naháňaj skorý mlyn.",
        "Pozri si jednu prehru a označ prvé kolo, v ktorom sa tvoje možnosti zúžili viac než možnosti AI.",
      ],
    },
    mistakes: {
      title: "Návyky, ktoré máš zahodiť a nechať si",
      badTitle: "Zahoď tieto návyky",
      bad: [
        "Brať ľubovoľný kameň len preto, že môžeš.",
        "Brániť jednu hrozbu bez vytvorenia druhej.",
        "Naskladať kamene na jeden prstenec a stratiť pružnosť.",
      ],
      goodTitle: "Nechaj si tieto návyky",
      good: [
        "Počítaj legálne ťahy oboch strán skôr, než sa pozícia zúži.",
        "Uprednostni body, ktoré spájajú línie a budúce hrozby.",
        "Prah troch kameňov ber ako zmenu priorít.",
      ],
      rememberTitle: "Jedna veta na zapamätanie",
      rememberText: "<strong>Môžeš prehrať buď pádom pod tri kamene, alebo tým, že nebudeš mať žiadny legálny ťah.</strong>",
    },
    resources: {
      title: "Zdroje",
      externalTitle: "Externý strategický zdroj",
      externalBody: "Stránka NMM Strategy zhromažďuje širší materiál o otvoreniach, štruktúre a koncovkách, ak chceš ísť hlbšie.",
      externalCta: "Otvoriť NMM Strategy",
      appTitle: "Pokračuj v používaní aplikácie",
      appBody: "Sanmill je stále najlepšie miesto na testovanie jednej zmeny naraz. Krátke opakovateľné partie robia pokrok viditeľným.",
      repoCta: "Otvoriť repozitár Sanmill",
    },
    footer: {
      note: "Krátke sústredené cvičenie je často užitočnejšie než dlhý článok. Vezmi si odtiaľto jednu myšlienku a skús ju v ďalšej partii.",
    },
  },
  sq: {
    meta: {
      title: "Sanmill | Shënime strategjie për Nine Men's Morris",
      description: "Shënime të shkurtra dhe ushtrime për lojtarët e Nine Men's Morris në Sanmill.",
    },
    nav: {
      fixes: "Ndreqje",
      drills: "Ushtrime",
      mistakes: "Zakone",
      resources: "Burime",
    },
    hero: {
      eyebrow: "Strategjia e Nine Men's Morris",
      title: "Luaj më qetë.<br>Krijo dy kërcënime.<br>Mbaji të gjalla lëvizjet e tua.",
      lead: "Kjo faqe është për lojtarët e Sanmill që duan një plan të shkurtër, jo një libër teorie. Përqendrohu te një ndryshim në ndeshjet e ardhshme.",
      rules: "<strong>Shënim rregullash:</strong> Nine Men's Morris standard ka fazën e vendosjes, fazën e lëvizjes në pika ngjitur dhe fluturimin kur njëra palë ka tre gurë.",
      primary: "Shfaq ndreqjet",
      secondary: "Hap burimet",
    },
    tips: [
      "Numëro lëvizjet ligjore para se të numërosh materialin.",
      "Pyet nëse çdo lëvizje krijon një kërcënim të dytë.",
      "Pranë tre gurëve, shiko së pari kërcënimet e fluturimit.",
    ],
    fixes: {
      title: "Tre ndreqje të zakonshme",
      cards: [
        {
          title: "Ndreqja A: Të mbarojnë lëvizjet",
          body: "Ky është problem mobiliteti. Në fazën e lëvizjes jepi përparësi lëvizjes që mban ose rrit numrin e lëvizjeve të tua ligjore.",
        },
        {
          title: "Ndreqja B: Nuk krijon presion",
          body: "Ky është problem strukture. Në fazën e vendosjes jepi përparësi pikave lidhëse dhe shpërndaji gurët nëpër unaza.",
        },
        {
          title: "Ndreqja C: Mullinjtë e tu nuk e ndryshojnë lojën",
          body: "Ky është problem tempi. Mos e rihap automatikisht të njëjtin mulli nëse kapja nuk ta përmirëson pozitën.",
        },
      ],
    },
    drills: {
      title: "Tre ushtrime të shkurtra",
      items: [
        "Luaj tri ndeshje dhe refuzo çdo lëvizje që ul numrin e lëvizjeve të tua ligjore, përveç nëse fiton menjëherë material.",
        "Luaj tri ndeshje ku vendos fillimisht në pika që lidhin disa linja përpara se të ndjekësh një mulli të hershëm.",
        "Rishiko një humbje dhe shëno turin e parë kur opsionet e tua u bënë më të ngushta se ato të AI-së.",
      ],
    },
    mistakes: {
      title: "Zakone për t'i lënë dhe për t'i mbajtur",
      badTitle: "Lëri këto zakone",
      bad: [
        "Të kapësh çdo gur vetëm sepse mundesh.",
        "Të mbrosh një kërcënim pa krijuar një tjetër.",
        "Të grumbullosh gurët në një unazë dhe të humbasësh fleksibilitetin.",
      ],
      goodTitle: "Mbaji këto zakone",
      good: [
        "Numëro lëvizjet ligjore të të dy palëve para se tabela të ngushtohet.",
        "Zgjidh pika që lidhin linja dhe kërcënime të ardhshme.",
        "Shihe pragun e tre gurëve si ndryshim përparësish.",
      ],
      rememberTitle: "Një fjali për ta mbajtur mend",
      rememberText: "<strong>Mund të humbësh duke rënë nën tre gurë ose duke mos pasur asnjë lëvizje ligjore.</strong>",
    },
    resources: {
      title: "Burime",
      externalTitle: "Referencë e jashtme strategjie",
      externalBody: "Faqja NMM Strategy mbledh material më të gjerë për hapje, strukturë dhe fundlojë nëse dëshiron të studiosh më thellë.",
      externalCta: "Hap NMM Strategy",
      appTitle: "Vazhdo ta përdorësh aplikacionin",
      appBody: "Sanmill mbetet vendi më i mirë për të testuar nga një ndryshim çdo herë. Lojërat e shkurtra dhe të përsëritshme e bëjnë përparimin të dukshëm.",
      repoCta: "Hap depozitën e Sanmill",
    },
    footer: {
      note: "Një ushtrim i shkurtër dhe i përqendruar është shpesh më i dobishëm se një artikull i gjatë. Merr një ide këtu dhe provoje në ndeshjen tënde të radhës.",
    },
  },
  sr: {
    meta: {
      title: "Sanmill | Стратешке белешке за Nine Men's Morris",
      description: "Кратке белешке и вежбе за играче Nine Men's Morris у Sanmill-у.",
    },
    nav: {
      fixes: "Исправке",
      drills: "Вежбе",
      mistakes: "Навике",
      resources: "Ресурси",
    },
    hero: {
      eyebrow: "Стратегија за Nine Men's Morris",
      title: "Играј мирније.<br>Створи две претње.<br>Одржи своје потезе живима.",
      lead: "Ова страница је за играче Sanmill-а који желе кратак план, а не књигу теорије. Усредсреди се на једну промену у наредним партијама.",
      rules: "<strong>Напомена о правилима:</strong> Стандардни Nine Men's Morris има фазу постављања, фазу кретања на суседне тачке и летење када страна има три фигуре.",
      primary: "Прикажи исправке",
      secondary: "Отвори ресурсе",
    },
    tips: [
      "Број легалне потезе пре него што бројиш материјал.",
      "Питај се да ли сваки потез ствара другу претњу.",
      "Код три фигуре прво гледај претње летења.",
    ],
    fixes: {
      title: "Три честе исправке",
      cards: [
        {
          title: "Исправка A: Остајеш без потеза",
          body: "То је проблем мобилности. У фази кретања дај предност потезу који чува или повећава број твојих легалних потеза.",
        },
        {
          title: "Исправка B: Не ствараш притисак",
          body: "То је проблем структуре. У фази постављања бирај повезујуће тачке и распореди фигуре по прстеновима.",
        },
        {
          title: "Исправка C: Твоји млинови не мењају партију",
          body: "То је проблем темпа. Не отварај аутоматски исти млин ако узимање не побољшава твоју позицију.",
        },
      ],
    },
    drills: {
      title: "Три кратке вежбе",
      items: [
        "Одиграј три партије и одбиј сваки потез који смањује број твојих легалних потеза, осим ако одмах не добија материјал.",
        "Одиграј три партије у којима прво постављаш на тачке које повезују више линија пре него што јуриш рани млин.",
        "Прегледај један пораз и означи први потез када су ти опције постале уже од AI опција.",
      ],
    },
    mistakes: {
      title: "Навике које треба одбацити и задржати",
      badTitle: "Одбаци ове навике",
      bad: [
        "Узети било коју фигуру само зато што можеш.",
        "Бранити једну претњу без стварања друге.",
        "Натрпати фигуре на један прстен и изгубити флексибилност.",
      ],
      goodTitle: "Задржи ове навике",
      good: [
        "Број легалне потезе обе стране пре него што се табла стегне.",
        "Бирај тачке које повезују линије и будуће претње.",
        "Праг од три фигуре схвати као промену приоритета.",
      ],
      rememberTitle: "Једна реченица за памћење",
      rememberText: "<strong>Можеш изгубити или падом испод три фигуре или тако што нећеш имати ниједан легалан потез.</strong>",
    },
    resources: {
      title: "Ресурси",
      externalTitle: "Спољна стратешка референца",
      externalBody: "Страница NMM Strategy окупља шири материјал о отварањима, структури и завршницама ако желиш дубље да учиш.",
      externalCta: "Отвори NMM Strategy",
      appTitle: "Настави да користиш апликацију",
      appBody: "Sanmill је и даље најбоље место за тестирање једне промене одједном. Кратке поновљиве партије чине напредак видљивим.",
      repoCta: "Отвори Sanmill репозиторијум",
    },
    footer: {
      note: "Кратка усредсређена вежба је често кориснија од дугог чланка. Узми једну идеју одавде и испробај је у следећој партији.",
    },
  },
  tr: {
    meta: {
      title: "Sanmill | Nine Men's Morris strateji notları",
      description: "Sanmill içindeki Nine Men's Morris oyuncuları için kısa notlar ve alıştırmalar.",
    },
    nav: {
      fixes: "Düzeltmeler",
      drills: "Alıştırmalar",
      mistakes: "Alışkanlıklar",
      resources: "Kaynaklar",
    },
    hero: {
      eyebrow: "Nine Men's Morris stratejisi",
      title: "Daha sakin oyna.<br>İki tehdit kur.<br>Hamlelerini canlı tut.",
      lead: "Bu sayfa, teori kitabı değil kısa bir plan isteyen Sanmill oyuncuları içindir. Önümüzdeki oyunlarda tek bir değişikliğe odaklan.",
      rules: "<strong>Kural notu:</strong> Standart Nine Men's Morris; yerleştirme evresi, bitişik noktalara hareket evresi ve bir taraf üç taş kaldığında uçma kuralı içerir.",
      primary: "Düzeltmeleri göster",
      secondary: "Kaynakları aç",
    },
    tips: [
      "Taş saymadan önce yasal hamleleri say.",
      "Her hamlenin ikinci bir tehdit oluşturup oluşturmadığını sor.",
      "Üç taş civarında önce uçma tehditlerine bak.",
    ],
    fixes: {
      title: "Üç yaygın düzeltme",
      cards: [
        {
          title: "Düzeltme A: Hamlelerin tükeniyor",
          body: "Bu bir hareketlilik sorunu. Hareket evresinde, yasal hamle sayını koruyan ya da artıran hamleyi tercih et.",
        },
        {
          title: "Düzeltme B: Baskı kuramıyorsun",
          body: "Bu bir yapı sorunu. Yerleştirme evresinde bağlantı noktalarını seç ve taşlarını halkalara yay.",
        },
        {
          title: "Düzeltme C: Değirmenlerin oyunu değiştirmiyor",
          body: "Bu bir tempo sorunu. Alma işlemi konumunu iyileştirmiyorsa aynı değirmeni otomatik olarak yeniden açma.",
        },
      ],
    },
    drills: {
      title: "Üç kısa alıştırma",
      items: [
        "Üç oyun oyna ve anında malzeme kazandırmıyorsa yasal hamle sayını düşüren her hamleyi reddet.",
        "Üç oyunda, erken değirmen kovalamadan önce birden fazla çizgiyi bağlayan noktalara yerleştir.",
        "Bir yenilgiyi gözden geçir ve seçeneklerinin AI seçeneklerinden daha dar hâle geldiği ilk turu işaretle.",
      ],
    },
    mistakes: {
      title: "Bırakılacak ve korunacak alışkanlıklar",
      badTitle: "Bu alışkanlıkları bırak",
      bad: [
        "Sırf yapabildiğin için herhangi bir taşı almak.",
        "Başka bir tehdit oluşturmadan tek bir tehdidi savunmak.",
        "Taşları tek halkada toplamak ve esnekliği kaybetmek.",
      ],
      goodTitle: "Bu alışkanlıkları koru",
      good: [
        "Tahta daralmadan önce iki tarafın da yasal hamlelerini say.",
        "Çizgileri ve gelecekteki tehditleri bağlayan noktaları tercih et.",
        "Üç taş eşiğini öncelik değişimi olarak gör.",
      ],
      rememberTitle: "Hatırlanacak tek cümle",
      rememberText: "<strong>Üç taşın altına düşerek de, hiç yasal hamlen kalmayarak da kaybedebilirsin.</strong>",
    },
    resources: {
      title: "Kaynaklar",
      externalTitle: "Harici strateji kaynağı",
      externalBody: "Daha derin çalışmak istersen, NMM Strategy sayfası açılışlar, yapı ve oyun sonları hakkında daha geniş materyal toplar.",
      externalCta: "NMM Strategy aç",
      appTitle: "Uygulamayı kullanmaya devam et",
      appBody: "Sanmill hâlâ aynı anda tek değişiklik denemek için en iyi yer. Kısa ve tekrarlanabilir oyunlar ilerlemeyi görünür kılar.",
      repoCta: "Sanmill deposunu aç",
    },
    footer: {
      note: "Kısa ve odaklı bir alıştırma, uzun bir makaleden daha yararlı olabilir. Buradan bir fikir al ve sonraki oyunda dene.",
    },
  },
  ur: {
    meta: {
      title: "Sanmill | Nine Men's Morris حکمتِ عملی نوٹس",
      description: "Sanmill میں Nine Men's Morris کھلاڑیوں کے لیے مختصر نوٹس اور مشقیں۔",
    },
    nav: {
      fixes: "اصلاحات",
      drills: "مشقیں",
      mistakes: "عادتیں",
      resources: "وسائل",
    },
    hero: {
      eyebrow: "Nine Men's Morris حکمتِ عملی",
      title: "پرسکون کھیلیں۔<br>دو خطرے بنائیں۔<br>اپنی چالیں زندہ رکھیں۔",
      lead: "یہ صفحہ اُن Sanmill کھلاڑیوں کے لیے ہے جو تھیوری کی کتاب نہیں بلکہ مختصر منصوبہ چاہتے ہیں۔ اپنی اگلی بازیوں میں ایک ہی تبدیلی پر توجہ دیں۔",
      rules: "<strong>قواعد نوٹ:</strong> معیاری Nine Men's Morris میں placing phase، adjacent points پر moving phase، اور تین pieces رہ جانے پر flying شامل ہے۔",
      primary: "اصلاحات دکھائیں",
      secondary: "وسائل کھولیں",
    },
    tips: [
      "material گننے سے پہلے legal moves گنیں۔",
      "پوچھیں کہ کیا ہر چال دوسرا خطرہ بناتی ہے۔",
      "تین pieces کے قریب پہلے flying threats دیکھیں۔",
    ],
    fixes: {
      title: "تین عام اصلاحات",
      cards: [
        {
          title: "اصلاح A: آپ کی چالیں ختم ہو جاتی ہیں",
          body: "یہ mobility کا مسئلہ ہے۔ moving phase میں وہ چال ترجیح دیں جو آپ کے legal moves کو برقرار رکھے یا بڑھائے۔",
        },
        {
          title: "اصلاح B: آپ دباؤ نہیں بنا پاتے",
          body: "یہ structure کا مسئلہ ہے۔ placing phase میں connector points لیں اور اپنی pieces کو rings میں پھیلائیں۔",
        },
        {
          title: "اصلاح C: آپ کی mills کھیل نہیں بدلتی",
          body: "یہ tempo کا مسئلہ ہے۔ اگر capture آپ کی پوزیشن بہتر نہیں کرتا تو وہی mill بار بار نہ کھولیں۔",
        },
      ],
    },
    drills: {
      title: "تین مختصر مشقیں",
      items: [
        "تین کھیل کھیلیں اور ایسی ہر چال رد کریں جو legal-move count کم کرے، جب تک کہ وہ فوراً material نہ جتائے۔",
        "تین کھیلوں میں early mill کے پیچھے بھاگنے سے پہلے اُن points پر رکھیں جو کئی lines کو جوڑتے ہیں۔",
        "ایک ہار کا جائزہ لیں اور وہ پہلا turn نشان زد کریں جب آپ کے اختیارات AI سے زیادہ تنگ ہو گئے۔",
      ],
    },
    mistakes: {
      title: "چھوڑنے اور رکھنے والی عادتیں",
      badTitle: "یہ عادتیں چھوڑ دیں",
      bad: [
        "صرف اس لیے کوئی بھی piece پکڑ لینا کہ موقع ہے۔",
        "ایک خطرے کا دفاع کرنا مگر دوسرا خطرہ نہ بنانا۔",
        "pieces کو ایک ہی ring میں بھر دینا اور flexibility کھو دینا۔",
      ],
      goodTitle: "یہ عادتیں رکھیں",
      good: [
        "بورڈ تنگ ہونے سے پہلے دونوں طرف کے legal moves گنیں۔",
        "ایسے points چنیں جو lines اور future threats کو جوڑتے ہوں۔",
        "three-piece threshold کو priorities کی تبدیلی سمجھیں۔",
      ],
      rememberTitle: "یاد رکھنے کے لیے ایک جملہ",
      rememberText: "<strong>آپ تین pieces سے کم رہ جانے پر بھی ہار سکتے ہیں، اور کسی legal move کے بغیر بھی۔</strong>",
    },
    resources: {
      title: "وسائل",
      externalTitle: "بیرونی حکمتِ عملی حوالہ",
      externalBody: "اگر آپ مزید گہرائی میں جانا چاہتے ہیں تو NMM Strategy صفحہ openings، structure اور endgames پر زیادہ مواد جمع کرتا ہے۔",
      externalCta: "NMM Strategy کھولیں",
      appTitle: "ایپ استعمال کرتے رہیں",
      appBody: "Sanmill اب بھی ایک وقت میں ایک تبدیلی آزمانے کے لیے بہترین جگہ ہے۔ مختصر اور دہرائے جا سکنے والے کھیل پیش رفت واضح کرتے ہیں۔",
      repoCta: "Sanmill repository کھولیں",
    },
    footer: {
      note: "مختصر اور مرکوز مشق اکثر لمبے مضمون سے زیادہ مفید ہوتی ہے۔ یہاں سے ایک خیال لیں اور اگلے کھیل میں آزمائیں۔",
    },
  },
  "zh-CN": {
    meta: {
      title: "Sanmill | Nine Men's Morris 策略笔记",
      description: "面向 Sanmill Nine Men's Morris 玩家 的简明策略笔记与练习。",
    },
    nav: {
      fixes: "修正方向",
      drills: "练习",
      mistakes: "习惯",
      resources: "资源",
    },
    hero: {
      eyebrow: "Nine Men's Morris 策略",
      title: "下得更稳。<br>制造两个威胁。<br>让自己的着法始终活着。",
      lead: "这个页面面向想要短计划、而不是长篇理论的 Sanmill 玩家。接下来几盘棋，只专注修正一个问题。",
      rules: "<strong>规则说明：</strong>标准 Nine Men's Morris 包含摆子阶段、沿线走到相邻点的走子阶段，以及一方只剩三枚棋子时的飞子规则。",
      primary: "查看修正方向",
      secondary: "打开资源",
    },
    tips: [
      "先数合法着法，再数棋子数量。",
      "每一步都问自己：这步能不能制造第二个威胁？",
      "接近三枚棋子时，先看飞子威胁。",
    ],
    fixes: {
      title: "三个常见修正方向",
      cards: [
        {
          title: "修正 A：你的着法越来越少",
          body: "这是机动性问题。进入走子阶段后，优先选择能让自己合法着法保持稳定或增加的着法。",
        },
        {
          title: "修正 B：你很难持续施压",
          body: "这是结构问题。摆子阶段优先占据连接点，并把棋子分布到不同的环上。",
        },
        {
          title: "修正 C：你形成三连却没改变局面",
          body: "这是节奏问题。如果吃子不能改善局面，就不要机械地反复拆开再重组三连。",
        },
      ],
    },
    drills: {
      title: "三个短练习",
      items: [
        "连续下三盘棋。除非能立刻赚子，否则拒绝任何会让自己合法着法减少的着法。",
        "连续下三盘棋。先抢占能连接多条线的点，再考虑追求过早的三连。",
        "复盘一盘败局，标出你可选着法比 AI 更早变窄的那个回合。",
      ],
    },
    mistakes: {
      title: "该丢掉的习惯与该保留的习惯",
      badTitle: "丢掉这些习惯",
      bad: [
        "只因为能吃子就随便吃。",
        "只顾着补一个威胁，却没有制造新的威胁。",
        "把棋子都堆在同一环上，失去弹性。",
      ],
      goodTitle: "保留这些习惯",
      good: [
        "在局面变紧之前，先数双方的合法着法。",
        "优先占据能连接线与后续威胁的点。",
        "把三枚棋子的门槛视为优先级变化，而不只是子数变化。",
      ],
      rememberTitle: "记住这一句话",
      rememberText: "<strong>你既可能因为被打到少于三枚棋子而输，也可能因为没有合法着法而输。</strong>",
    },
    resources: {
      title: "资源",
      externalTitle: "外部策略参考",
      externalBody: "如果你想继续深入，NMM Strategy 页面汇集了开局、结构和残局方面的更完整资料。",
      externalCta: "打开 NMM Strategy",
      appTitle: "继续使用应用练习",
      appBody: "Sanmill 仍然是一次只验证一个改动的最佳场所。短而可重复的对局最容易看出进步。",
      repoCta: "打开 Sanmill 仓库",
    },
    footer: {
      note: "一个短而聚焦的练习，往往比一篇长文章更有用。先从这里挑一个想法，在下一盘棋里试一试。",
    },
  },
  "zh-TW": {
    meta: {
      title: "Sanmill | Nine Men's Morris 策略筆記",
      description: "面向 Sanmill Nine Men's Morris 玩家 的精簡策略筆記與練習。",
    },
    nav: {
      fixes: "修正方向",
      drills: "練習",
      mistakes: "習慣",
      resources: "資源",
    },
    hero: {
      eyebrow: "Nine Men's Morris 策略",
      title: "下得更穩。<br>製造兩個威脅。<br>讓自己的著法一直活著。",
      lead: "這個頁面面向想要短計畫、而不是長篇理論的 Sanmill 玩家。接下來幾盤棋，只專注修正一個問題。",
      rules: "<strong>規則說明：</strong>標準 Nine Men's Morris 包含擺子階段、沿線走到相鄰點的走子階段，以及一方只剩三枚棋子時的飛子規則。",
      primary: "查看修正方向",
      secondary: "打開資源",
    },
    tips: [
      "先數合法著法，再數棋子數量。",
      "每一步都問自己：這步能不能製造第二個威脅？",
      "接近三枚棋子時，先看飛子威脅。",
    ],
    fixes: {
      title: "三個常見修正方向",
      cards: [
        {
          title: "修正 A：你的著法越來越少",
          body: "這是機動性問題。進入走子階段後，優先選擇能讓自己合法著法保持穩定或增加的著法。",
        },
        {
          title: "修正 B：你很難持續施壓",
          body: "這是結構問題。擺子階段優先佔據連接點，並把棋子分布到不同的環上。",
        },
        {
          title: "修正 C：你形成三連卻沒改變局面",
          body: "這是節奏問題。如果吃子不能改善局面，就不要機械地反覆拆開再重組三連。",
        },
      ],
    },
    drills: {
      title: "三個短練習",
      items: [
        "連續下三盤棋。除非能立刻賺子，否則拒絕任何會讓自己合法著法減少的著法。",
        "連續下三盤棋。先搶佔能連接多條線的點，再考慮追求過早的三連。",
        "複盤一盤敗局，標出你可選著法比 AI 更早變窄的那個回合。",
      ],
    },
    mistakes: {
      title: "該丟掉的習慣與該保留的習慣",
      badTitle: "丟掉這些習慣",
      bad: [
        "只因為能吃子就隨便吃。",
        "只顧補一個威脅，卻沒有製造新的威脅。",
        "把棋子都堆在同一環上，失去彈性。",
      ],
      goodTitle: "保留這些習慣",
      good: [
        "在局面變緊之前，先數雙方的合法著法。",
        "優先佔據能連接線與後續威脅的點。",
        "把三枚棋子的門檻視為優先級變化，而不只是子數變化。",
      ],
      rememberTitle: "記住這一句話",
      rememberText: "<strong>你既可能因為被打到少於三枚棋子而輸，也可能因為沒有合法著法而輸。</strong>",
    },
    resources: {
      title: "資源",
      externalTitle: "外部策略參考",
      externalBody: "如果你想繼續深入，NMM Strategy 頁面彙集了開局、結構與殘局方面的更完整資料。",
      externalCta: "打開 NMM Strategy",
      appTitle: "繼續使用應用練習",
      appBody: "Sanmill 仍然是一次只驗證一個改動的最佳場所。短而可重複的對局最容易看出進步。",
      repoCta: "打開 Sanmill 倉庫",
    },
    footer: {
      note: "一個短而聚焦的練習，往往比一篇長文章更有用。先從這裡挑一個想法，在下一盤棋裡試一試。",
    },
  },
};
const PAGE_CONFIGS = {
  home: HOME,
  strategy: STRATEGY,
};

function buildTranslations(pageId, locale) {
  return {
    common: COMMON[locale],
    ...PAGE_CONFIGS[pageId][locale],
  };
}

function populateLanguageSelectors(locale, onChange) {
  document.querySelectorAll("[data-locale-switcher]").forEach((select) => {
    select.innerHTML = "";
    select.onchange = (event) => {
      onChange(event.target.value);
    };
    for (const optionLocale of SUPPORTED_LOCALES) {
      const option = document.createElement("option");
      option.value = optionLocale;
      option.textContent = LOCALE_LABELS[optionLocale];
      option.selected = optionLocale === locale;
      select.appendChild(option);
    }
  });
}

function validatePageShapes() {
  for (const [pageId, locales] of Object.entries(PAGE_CONFIGS)) {
    const reference = locales.en;
    for (const locale of SUPPORTED_LOCALES) {
      assert(locale in locales, `Missing locale ${locale} for ${pageId}`);
      compareShape(reference, locales[locale], `${pageId}.${locale}`);
    }
  }
}

validatePageShapes();

export function initLocalizedPage(pageId) {
  assert(pageId in PAGE_CONFIGS, `Unknown localized page: ${pageId}`);

  const applyLocale = (requestedLocale) => {
    const locale = normalizeLocale(requestedLocale) ?? "en";
    const translations = buildTranslations(pageId, locale);

    document.documentElement.lang = locale;
    document.documentElement.dir = RTL_LOCALES.has(locale) ? "rtl" : "ltr";
    document.body.dataset.locale = locale;
    document.title = translations.meta.title;
    applyTranslations(translations);
    window.localStorage.setItem(STORAGE_KEY, locale);
    populateLanguageSelectors(locale, applyLocale);
  };

  applyLocale(getPreferredLocale());
}
