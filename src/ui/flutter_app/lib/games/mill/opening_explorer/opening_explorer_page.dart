// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../game_platform/game_session.dart';
import '../../../general_settings/models/general_settings.dart';
import '../../../generated/intl/l10n.dart';
import '../../../rule_settings/models/rule_settings.dart';
import '../../../shared/database/database.dart' show DB;
import '../../../shared/services/human_database_service.dart';
import '../../../shared/services/snackbar_service.dart';
import '../../../shared/themes/app_styles.dart';
import '../../../shared/widgets/lichess_list_section.dart';
import '../../../src/rust/api/simple.dart' as tgf;
import '../mill_action_codec.dart';
import '../mill_human_database_provider.dart';
import '../mill_opening_book_symmetry.dart';
import '../native_mill_game_session.dart';
import '../opening_book/opening_book_repository.dart';

class OpeningExplorerPage extends StatefulWidget {
  const OpeningExplorerPage({super.key, this.session});

  final GameSession? session;

  @override
  State<OpeningExplorerPage> createState() => _OpeningExplorerPageState();
}

class _OpeningExplorerPageState extends State<OpeningExplorerPage> {
  late final Future<void> _openingBookLoad = OpeningBookRepository.instance
      .ensureLoaded();

  @override
  Widget build(BuildContext context) {
    final S strings = S.of(context);
    final GameSession? session = widget.session;

    return Scaffold(
      appBar: AppBar(title: Text(strings.openingExplorer)),
      body: session is NativeMillGameSession
          ? ValueListenableBuilder<GameStateSnapshot>(
              valueListenable: session.state,
              builder:
                  (BuildContext context, GameStateSnapshot _, Widget? child) {
                    return FutureBuilder<void>(
                      future: _openingBookLoad,
                      builder: (BuildContext context, AsyncSnapshot<void> _) {
                        final _OpeningExplorerSnapshot snapshot =
                            _OpeningExplorerSnapshot.fromSession(
                              session: session,
                              ruleSettings: DB().ruleSettings,
                              generalSettings: DB().generalSettings,
                            );
                        return _OpeningExplorerContent(snapshot: snapshot);
                      },
                    );
                  },
            )
          : _OpeningExplorerMessage(
              message: strings.openingExplorerUnavailable,
            ),
    );
  }
}

class _OpeningExplorerContent extends StatelessWidget {
  const _OpeningExplorerContent({required this.snapshot});

  final _OpeningExplorerSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final S strings = S.of(context);

    return ListTileTheme.merge(
      iconColor: Theme.of(context).colorScheme.primary,
      child: ListView(
        key: const Key('opening_explorer_list'),
        padding: const EdgeInsets.only(top: 16, bottom: 24),
        children: <Widget>[
          if (!snapshot.isRuleSupported)
            _OpeningExplorerMessage(
              message: strings.openingExplorerRuleUnsupported,
              inList: true,
            ),
          _PositionSection(snapshot: snapshot),
          if (snapshot.moves.isEmpty)
            _OpeningExplorerMessage(
              message: strings.openingExplorerNoData,
              inList: true,
            )
          else
            LichessListSection(
              header: Text(strings.openingExplorerMoves),
              cardKey: const Key('opening_explorer_moves_card'),
              children: <Widget>[
                for (final _OpeningExplorerMove move in snapshot.moves)
                  _OpeningMoveTile(move: move),
              ],
            ),
        ],
      ),
    );
  }
}

class _PositionSection extends StatelessWidget {
  const _PositionSection({required this.snapshot});

  final _OpeningExplorerSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final S strings = S.of(context);
    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    return LichessListSection(
      header: Text(strings.openingExplorerCurrentPosition),
      cardKey: const Key('opening_explorer_position_card'),
      children: <Widget>[
        ListTile(
          key: const Key('opening_explorer_position_fen'),
          leading: const Icon(Icons.location_searching_rounded),
          title: Text(strings.copyFen),
          subtitle: Text(
            snapshot.fen,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: colorScheme.onSurfaceVariant.withValues(
                alpha: AppStyles.subtitleOpacity,
              ),
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
          onTap: () async {
            await Clipboard.setData(ClipboardData(text: snapshot.fen));
            SnackBarService.showRootSnackBar(strings.fenCopiedToClipboard);
          },
        ),
        ListTile(
          key: const Key('opening_explorer_position_sources'),
          leading: const Icon(Icons.data_object_rounded),
          title: Text(strings.openingExplorerSources),
          subtitle: Text(snapshot.sourceSummary(strings)),
        ),
      ],
    );
  }
}

class _OpeningMoveTile extends StatelessWidget {
  const _OpeningMoveTile({required this.move});

  final _OpeningExplorerMove move;

  @override
  Widget build(BuildContext context) {
    final S strings = S.of(context);
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final TextStyle subtitleStyle =
        theme.textTheme.bodySmall?.copyWith(
          color: colorScheme.onSurfaceVariant.withValues(
            alpha: AppStyles.subtitleOpacity,
          ),
          letterSpacing: 0,
        ) ??
        AppStyles.tileSubtitle.copyWith(
          color: colorScheme.onSurfaceVariant.withValues(
            alpha: AppStyles.subtitleOpacity,
          ),
        );

    return ListTile(
      key: Key('opening_explorer_move_${move.notation}'),
      leading: _MoveNotationBadge(notation: move.notation),
      title: Wrap(
        spacing: 6,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: <Widget>[
          Text(move.notation, style: theme.textTheme.titleMedium),
          if (move.isPerfectMove)
            _SourceBadge(
              label: strings.perfectDatabaseSettings,
              color: colorScheme.primary,
            ),
          if (move.bookRank != null)
            _SourceBadge(
              label: strings.openingBookSettings,
              color: colorScheme.tertiary,
            ),
          if (move.humanStats != null)
            _SourceBadge(
              label: strings.humanGameDatabaseSettings,
              color: colorScheme.secondary,
            ),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: move.humanStats == null
            ? Text(_sourceOnlySubtitle(strings, move), style: subtitleStyle)
            : _HumanStatsSummary(stats: move.humanStats!),
      ),
    );
  }

  static String _sourceOnlySubtitle(S strings, _OpeningExplorerMove move) {
    if (move.isPerfectMove && move.bookRank != null) {
      return '${strings.openingExplorerPerfectMove} · '
          '${strings.openingExplorerBookMove} #${move.bookRank! + 1}';
    }
    if (move.isPerfectMove) {
      return strings.openingExplorerPerfectMove;
    }
    if (move.bookRank != null) {
      return '${strings.openingExplorerBookMove} #${move.bookRank! + 1}';
    }
    return strings.openingExplorerNoData;
  }
}

class _MoveNotationBadge extends StatelessWidget {
  const _MoveNotationBadge({required this.notation});

  final String notation;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: 48,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppStyles.compactRadius),
      ),
      child: Text(
        notation,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: colorScheme.onSurface,
          fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class _SourceBadge extends StatelessWidget {
  const _SourceBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppStyles.compactRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w600,
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }
}

class _HumanStatsSummary extends StatelessWidget {
  const _HumanStatsSummary({required this.stats});

  final _HumanMoveStats stats;

  @override
  Widget build(BuildContext context) {
    final S strings = S.of(context);
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final TextStyle style =
        theme.textTheme.bodySmall?.copyWith(
          color: colorScheme.onSurfaceVariant.withValues(
            alpha: AppStyles.subtitleOpacity,
          ),
          letterSpacing: 0,
        ) ??
        AppStyles.tileSubtitle.copyWith(
          color: colorScheme.onSurfaceVariant.withValues(
            alpha: AppStyles.subtitleOpacity,
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _HumanStatsBar(stats: stats),
        const SizedBox(height: 6),
        Text(
          '${strings.gamesPlayed}: ${stats.total} · '
          '${strings.wins}: ${stats.wins} · '
          '${strings.draws}: ${stats.draws} · '
          '${strings.losses}: ${stats.losses} · '
          'Δ ${stats.scoreDelta.toStringAsFixed(3)}',
          style: style,
        ),
      ],
    );
  }
}

class _HumanStatsBar extends StatelessWidget {
  const _HumanStatsBar({required this.stats});

  final _HumanMoveStats stats;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final double total = stats.total <= 0 ? 1 : stats.total.toDouble();

    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: SizedBox(
        height: 6,
        child: Row(
          children: <Widget>[
            Expanded(
              flex: _barFlex(stats.wins, total),
              child: ColoredBox(color: colorScheme.primary),
            ),
            Expanded(
              flex: _barFlex(stats.draws, total),
              child: ColoredBox(color: colorScheme.outlineVariant),
            ),
            Expanded(
              flex: _barFlex(stats.losses, total),
              child: ColoredBox(color: colorScheme.error),
            ),
          ],
        ),
      ),
    );
  }

  int _barFlex(int count, double total) {
    final int flex = (count * 1000 / total).round();
    return flex <= 0 ? 1 : flex;
  }
}

class _OpeningExplorerMessage extends StatelessWidget {
  const _OpeningExplorerMessage({required this.message, this.inList = false});

  final String message;
  final bool inList;

  @override
  Widget build(BuildContext context) {
    final Widget child = Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );

    if (inList) {
      return LichessListSection(hasLeading: false, children: <Widget>[child]);
    }
    return child;
  }
}

class _OpeningExplorerSnapshot {
  const _OpeningExplorerSnapshot({
    required this.fen,
    required this.isRuleSupported,
    required this.openingBookMoveCount,
    required this.humanDatabaseMoveCount,
    required this.perfectMoveAvailable,
    required this.moves,
  });

  factory _OpeningExplorerSnapshot.fromSession({
    required NativeMillGameSession session,
    required RuleSettings ruleSettings,
    required GeneralSettings generalSettings,
  }) {
    final String fen = session.getFen();
    final bool isRuleSupported =
        ruleSettings.isLikelyNineMensMorris() || ruleSettings.isLikelyElFilja();
    final Map<String, GameAction> legalActions = <String, GameAction>{};
    for (final GameAction action in session.legalActions) {
      final String? notation = MillActionCodec.moveStringFrom(action);
      if (notation != null && notation.isNotEmpty) {
        legalActions.putIfAbsent(notation, () => action);
      }
    }

    final Map<String, _OpeningExplorerMove> moves =
        <String, _OpeningExplorerMove>{};
    _OpeningExplorerMove ensureMove(String notation) {
      assert(
        legalActions.containsKey(notation),
        'Opening explorer move must map to a legal action.',
      );
      return moves.putIfAbsent(
        notation,
        () => _OpeningExplorerMove(notation: notation),
      );
    }

    int openingBookMoveCount = 0;
    if (isRuleSupported && session.state.value.phase == 'placing') {
      final Map<String, List<String>> book = OpeningBookRepository.instance
          .oracleFor(isElFilja: ruleSettings.isLikelyElFilja());
      final List<String>? bookMoves = lookupCanonicalOpeningBook(
        book,
        normalizeOpeningBookFen(fen),
      );
      if (bookMoves != null) {
        for (int i = 0; i < bookMoves.length; i++) {
          final String notation = bookMoves[i];
          if (!legalActions.containsKey(notation)) {
            continue;
          }
          openingBookMoveCount++;
          ensureMove(notation).bookRank ??= i;
        }
      }
    }

    int humanDatabaseMoveCount = 0;
    if (_canQueryHumanDatabase(session, ruleSettings, generalSettings)) {
      final HumanDatabaseReadyResult ready = HumanDatabaseService.instance
          .ensureReadySync(generalSettings.humanDatabaseFilePath);
      if (ready.ready) {
        final tgf.MillHumanDatabaseQuery query = tgf.millHumanDbQuery(
          fen: fen,
          maxMoves: 24,
          minSamples: MillHumanDatabaseProvider.minSamplesForSkill(
            generalSettings.skillLevel,
          ),
        );
        if (query.available) {
          for (final tgf.MillHumanDatabaseMove humanMove in query.moves) {
            final String notation = _baseMoveFromHumanDatabase(
              humanMove.notation,
            );
            if (!legalActions.containsKey(notation)) {
              continue;
            }
            humanDatabaseMoveCount++;
            ensureMove(notation).humanStats = _HumanMoveStats(
              wins: humanMove.wins,
              losses: humanMove.losses,
              draws: humanMove.draws,
              total: humanMove.total,
              scoreDelta: humanMove.scoreDelta,
            );
          }
        }
      }
    }

    bool perfectMoveAvailable = false;
    // ignore: deprecated_member_use
    if (generalSettings.usePerfectDatabase) {
      final GameAction? perfectAction = session.perfectDatabaseBestAction(
        engineSettings: generalSettings,
      );
      if (perfectAction != null) {
        final String? notation = MillActionCodec.moveStringFrom(perfectAction);
        if (notation != null && legalActions.containsKey(notation)) {
          perfectMoveAvailable = true;
          ensureMove(notation).isPerfectMove = true;
        }
      }
    }

    final List<_OpeningExplorerMove> sortedMoves = moves.values.toList();
    sortedMoves.sort(_compareExplorerMoves);

    return _OpeningExplorerSnapshot(
      fen: fen,
      isRuleSupported: isRuleSupported,
      openingBookMoveCount: openingBookMoveCount,
      humanDatabaseMoveCount: humanDatabaseMoveCount,
      perfectMoveAvailable: perfectMoveAvailable,
      moves: sortedMoves,
    );
  }

  final String fen;
  final bool isRuleSupported;
  final int openingBookMoveCount;
  final int humanDatabaseMoveCount;
  final bool perfectMoveAvailable;
  final List<_OpeningExplorerMove> moves;

  String sourceSummary(S strings) {
    final List<String> parts = <String>[
      '${strings.openingBookSettings}: $openingBookMoveCount',
      '${strings.humanGameDatabaseSettings}: $humanDatabaseMoveCount',
      '${strings.perfectDatabaseSettings}: ${perfectMoveAvailable ? strings.openingExplorerAvailable : strings.openingExplorerNoDataShort}',
    ];
    return parts.join(' · ');
  }

  static bool _canQueryHumanDatabase(
    NativeMillGameSession session,
    RuleSettings ruleSettings,
    GeneralSettings generalSettings,
  ) {
    if (!generalSettings.humanDatabaseEnabled ||
        generalSettings.humanDatabaseFilePath.trim().isEmpty ||
        session.outcome.isTerminal) {
      return false;
    }
    if (!_supportsHumanDatabaseRules(ruleSettings)) {
      return false;
    }
    return !session.legalActions.any(
      (GameAction action) => action.type == MillActionTypes.remove,
    );
  }

  static bool _supportsHumanDatabaseRules(RuleSettings ruleSettings) {
    return ruleSettings.isLikelyNineMensMorris() &&
        ruleSettings.flyPieceCount == 3 &&
        ruleSettings.mayFly &&
        !ruleSettings.mayRemoveMultiple &&
        !ruleSettings.mayRemoveFromMillsAlways;
  }

  static String _baseMoveFromHumanDatabase(String notation) {
    final int captureIndex = notation.indexOf('x');
    if (captureIndex < 0) {
      return notation;
    }
    final String baseMove = notation.substring(0, captureIndex);
    assert(
      baseMove.isNotEmpty,
      'Human Database move notation must include a base move.',
    );
    return baseMove;
  }

  static int _compareExplorerMoves(
    _OpeningExplorerMove a,
    _OpeningExplorerMove b,
  ) {
    if (a.isPerfectMove != b.isPerfectMove) {
      return a.isPerfectMove ? -1 : 1;
    }
    final int bookCompare = _compareNullableRank(a.bookRank, b.bookRank);
    if (bookCompare != 0) {
      return bookCompare;
    }
    final int humanTotalCompare = (b.humanStats?.total ?? 0).compareTo(
      a.humanStats?.total ?? 0,
    );
    if (humanTotalCompare != 0) {
      return humanTotalCompare;
    }
    final int humanScoreCompare = (b.humanStats?.scoreDelta ?? 0).compareTo(
      a.humanStats?.scoreDelta ?? 0,
    );
    if (humanScoreCompare != 0) {
      return humanScoreCompare;
    }
    return a.notation.compareTo(b.notation);
  }

  static int _compareNullableRank(int? a, int? b) {
    if (a == null && b == null) {
      return 0;
    }
    if (a == null) {
      return 1;
    }
    if (b == null) {
      return -1;
    }
    return a.compareTo(b);
  }
}

class _OpeningExplorerMove {
  _OpeningExplorerMove({required this.notation});

  final String notation;
  int? bookRank;
  _HumanMoveStats? humanStats;
  bool isPerfectMove = false;
}

class _HumanMoveStats {
  const _HumanMoveStats({
    required this.wins,
    required this.losses,
    required this.draws,
    required this.total,
    required this.scoreDelta,
  });

  final int wins;
  final int losses;
  final int draws;
  final int total;
  final double scoreDelta;
}
