# Nine Men's Morris Localization Glossary

This glossary standardizes wording for the `gh-pages` Nine Men's Morris study
pages.

It is primarily aligned with the existing `Sanmill` localization files:

- `D:/Repo/Sanmill/src/ui/flutter_app/lib/l10n/intl_en.arb`
- `D:/Repo/Sanmill/src/ui/flutter_app/lib/l10n/intl_zh.arb`
- `D:/Repo/Sanmill/src/ui/flutter_app/lib/l10n/intl_de.arb`
- `D:/Repo/Sanmill/src/ui/flutter_app/lib/l10n/intl_hu.arb`

The goal is not to mirror every in-app label literally. The goal is to keep web
copy:

- semantically consistent
- easy for players to understand
- easy to translate across languages
- stable across future localized study pages

## Core Terms

| English | Chinese | German | Hungarian | Notes |
| --- | --- | --- | --- | --- |
| piece / pieces | 棋子 | Stein / Steine or Stück / Stücke | korong / korongok or darab / darabok | Prefer `piece / pieces` in English instead of `man / men`. App strings already use `pieces`. |
| point / points | 点 | Punkt / Punkte | pont / pontok | Use for board intersections. Do not use `squares`. |
| empty point | 空点 | leerer Punkt | üres pont | Aligned with `emptyPoint`. |
| move | 着法 | Zug | lépés | Use as a noun. |
| to move | 行棋 / 走棋 | ziehen | lépni | Use a verb form in running text. |
| placing phase | 摆子阶段 | Setzphase | Helyezési fázis | Align with app phase names. |
| moving phase | 走子阶段 | Bewegungsphase | Mozgó fázis | Preferred English source term for phase 2. |
| flying phase | 飞子阶段 | Flugphase | Repülő fázis | Keep as a distinct optional phase. |
| flying | 飞子 | Fliegen | ugrás | The rule that lets a side on three pieces move to any empty point. |
| mill | 三连 | Mühle | malom | Use one stable term per language. |
| form a mill | 形成三连 | eine Mühle bilden | malmot alkotni | Preferred phrase in explanatory copy. |
| break a mill | 拆开三连 | eine Mühle aufbrechen | malmot megbontani | Use for tactic explanations. |
| remake a mill | 重新形成三连 | eine Mühle erneut bilden | malmot újraalkotni | Use for repeated-mill discussions. |
| legal move(s) | 合法着法 | legale Züge | legális lépések | Preferred rules term in study pages. |
| no legal move | 无合法着法 | kein legaler Zug | nincs legális lépés | Use in win/loss conditions. |
| capture / remove a piece | 吃子 / 吃掉一枚棋子 | einen Stein schlagen / entfernen | korongot levenni / eltávolítani | Player-facing web copy can be more natural than raw UI labels. |
| adjacent point | 相邻点 | angrenzender Punkt | szomszédos pont | Use when explaining phase 2 movement. |
| move to an adjacent point | 移到相邻点 | auf einen angrenzenden Punkt ziehen | egy szomszédos pontra lépni | Prefer full wording over overloaded shorthand. |
| move to any empty point | 飞到任意空点 | auf einen beliebigen freien Punkt ziehen | bármely üres pontra ugrani | Use for flying explanations. |
| board | 棋盘 | Spielbrett | tábla | Standard board term. |
| ring | 环 | Ring | gyűrű | Use only when board geometry matters. |
| connector point | 连接点 | Verbindungspunkt | kapcsolódó pont | Prefer a player-friendly term, not a graph-theory term. |
| threat | 威胁 | Drohung | fenyegetés | Standard strategy term. |
| mobility | 机动性 | Mobilität | mobilitás | Strategy term, not a replacement for `legal moves`. |
| piece count | 棋子数量 | Steinanzahl | korongszám | Important in loss conditions and flying rules. |

## English Source Style

| Prefer | Avoid | Why |
| --- | --- | --- |
| `pieces` | `men` | More neutral and easier to localize consistently. |
| `points` | `nodes`, `squares` | `points` matches Morris terminology better. `squares` is incorrect. |
| `moving phase` | `movement phase` | `moving phase` reads more naturally and matches the app. |
| `legal moves` | using `mobility` as a rules term | `mobility` is good for strategy, not for formal rule statements. |
| `move along lines to adjacent points` | using `slide` everywhere | `slide` is too phase-specific to be the default wording. |
| `three pieces` | `three men` | Keeps the terminology system consistent. |

## Language Notes

### Chinese

- Use `棋子` for `piece / pieces`.
- Use `点`, `空点`, and `相邻点` for board locations.
- Use `三连` consistently for `mill`.
- In player-facing study pages, prefer `吃子` over a more mechanical `移除`.
- Keep the phase names aligned with the app: `摆子阶段`, `走子阶段`,
  `飞子阶段`.

### German

- `Mühle` is the stable term for `mill`.
- `Setzphase`, `Bewegungsphase`, and `Flugphase` are the current app terms.
- For board locations, prefer `Punkt / Punkte` in study copy, even if some app
  strings use broader wording in specific contexts.
- For player-facing instructions, `einen gegnerischen Stein nehmen` or
  `schlagen` may read more naturally than overly technical phrasing.

### Hungarian

- `malom` is the stable term for `mill`.
- The current app uses `Helyezési fázis`, `Mozgó fázis`, and `Repülő fázis`.
- `pont` is preferred for board points in study copy.
- For player-facing instructions, `levenni egy ellenfél-korongot` is often more
  natural than a dry literal equivalent of `remove`.

## Constraints For Web Copy

When writing `gh-pages` study pages, follow these rules:

1. Do not use `men` in English. Use `piece` / `pieces`.
2. Do not use `nodes` or `squares` for board intersections. Use `points`.
3. Use `placing phase`, `moving phase`, and `flying phase` as the default phase
   names in English.
4. Prefer fully explicit movement wording such as `move to an adjacent point`
   instead of relying on `slide` throughout the page.
5. For loss conditions, prefer `reduced below three pieces` and `no legal move`.
6. In Chinese web copy, translate `mill` as `三连`.
7. In player-facing Chinese study pages, prefer `吃子` over `移除` unless the
   text is explicitly mirroring an existing UI setting.

## Reusable Phrases

| English | Chinese | German | Hungarian |
| --- | --- | --- | --- |
| Place pieces on vacant points. | 在空点上摆子。 | Setze Steine auf freie Punkte. | Helyezz korongokat üres pontokra. |
| Move pieces to adjacent points. | 将棋子移动到相邻点。 | Ziehe Steine auf angrenzende Punkte. | Lépj a korongokkal szomszédos pontokra. |
| A side on three pieces may fly. | 一方只剩三枚棋子时可以飞子。 | Eine Seite mit drei Steinen darf fliegen. | A három koronggal maradt fél ugrhat. |
| Count your legal moves first. | 先数自己的合法着法。 | Zähle zuerst deine legalen Züge. | Először számold meg a legális lépéseidet. |
| You can lose by having no legal move. | 无合法着法也会判负。 | Du kannst verlieren, wenn du keinen legalen Zug hast. | Akkor is veszíthetsz, ha nincs legális lépésed. |
| Forming a mill lets you remove one opponent piece. | 形成三连后可以吃掉对手一枚棋子。 | Eine Mühle erlaubt dir, einen gegnerischen Stein zu nehmen. | A malom után levehetsz egy ellenfél-korongot. |
| Prefer points that connect multiple lines. | 优先占据连接多条线的点。 | Bevorzuge Punkte, die mehrere Linien verbinden. | Részesítsd előnyben azokat a pontokat, amelyek több vonalat kötnek össze. |

## Maintenance Notes

- This glossary is for `gh-pages` study-page copy. It does not need to mirror
  every app button label exactly.
- If future study pages add more rule explanations, extend this glossary rather
  than inventing new wording ad hoc.
- If the main project updates its `l10n` terminology, review this glossary too.
