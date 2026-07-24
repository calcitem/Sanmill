// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// game_header.dart

part of 'game_page.dart';

class GameHeader extends StatefulWidget implements PreferredSizeWidget {
  const GameHeader({super.key});

  static const double contextualHeight = kToolbarHeight + AppTheme.boardMargin;

  @override
  Size get preferredSize => const Size.fromHeight(contextualHeight);

  @override
  State<GameHeader> createState() => _GameHeaderState();
}

class _GameHeaderState extends State<GameHeader> {
  @override
  Widget build(BuildContext context) {
    final GameController controller = GameController();
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[
        controller.headerTipNotifier,
        controller.headerIconsNotifier,
        controller.gameResultNotifier,
        if (controller.remoteCoordinator != null)
          controller.remoteCoordinator!.stateNotifier,
      ]),
      builder: (BuildContext context, Widget? child) {
        final bool showGameTips = DB().generalSettings.showGameTips;
        if (!showGameTips && !controller.isRemoteGameMode) {
          return const SizedBox.shrink(key: Key('game_header_hidden'));
        }

        final PieceColor side =
            controller.activeSessionSideToMove ??
            controller.activeBoardView.sideToMove;
        final String playerLabel = showGameTips
            ? switch (side) {
                PieceColor.white => S.of(context).white,
                PieceColor.black => S.of(context).black,
                _ => S.of(context).none,
              }
            : '';
        final NativeMillGameSession? session =
            controller.activeNativeMillSession;
        final String message = showGameTips
            ? controller.headerTipNotifier.message.isEmpty
                  ? session == null
                        ? S.of(context).welcome
                        : controller.nativeSessionTurnTip(context, session) ??
                              S.of(context).welcome
                  : controller.headerTipNotifier.message
            : '';
        return SizedBox(
          key: const Key('game_header_contextual_row'),
          height: widget.preferredSize.height,
          child: Padding(
            key: const Key('game_header_padding'),
            padding: const EdgeInsets.fromLTRB(12, 4, 12, AppTheme.boardMargin),
            child: Row(
              children: <Widget>[
                if (showGameTips) ...<Widget>[
                  Semantics(
                    image: true,
                    label: playerLabel,
                    child: ExcludeSemantics(
                      child: SizedBox.square(
                        dimension: 44,
                        child: Icon(
                          _activePlayerIcon(controller, side),
                          key: const Key('game_header_active_player_avatar'),
                          size: 32,
                          color: DB().colorSettings.messageColor,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: GameTipBubble(
                      key: const Key('game_header_contextual_tip'),
                      message: message,
                    ),
                  ),
                ],
                if (controller.isRemoteGameMode) ...<Widget>[
                  if (showGameTips) const SizedBox(width: 8),
                  if (showGameTips)
                    _RemoteEloSummary(controller: controller)
                  else
                    Expanded(
                      child: Align(
                        alignment: Alignment.center,
                        child: _RemoteEloSummary(controller: controller),
                      ),
                    ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  IconData _activePlayerIcon(GameController controller, PieceColor side) {
    if (side != PieceColor.white && side != PieceColor.black) {
      return controller.activeSideToMoveIcon;
    }
    if (controller.isRemoteGameMode) {
      if (side == controller.getLocalColor()) {
        return FluentIcons.person_24_filled;
      }
      return switch (controller.gameInstance.gameMode) {
        GameMode.humanVsBluetooth => FluentIcons.bluetooth_24_filled,
        GameMode.humanVsCloud => FluentIcons.cloud_24_filled,
        GameMode.humanVsLAN ||
        GameMode.testViaLAN => FluentIcons.wifi_1_24_filled,
        _ => FluentIcons.person_24_filled,
      };
    }
    if (controller.gameInstance.getPlayerByColor(side).isAi) {
      // The robot remains the computer-opponent identity. Optional move
      // sources are shown as an adjacent badge where the UI can attribute a
      // completed computer turn without ambiguity.
      return FluentIcons.bot_24_filled;
    }
    return FluentIcons.person_24_filled;
  }
}

class _RemoteEloSummary extends StatelessWidget {
  const _RemoteEloSummary({required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    final int localRating = DB().statsSettings.humanStats.rating;
    final int? opponentRating = controller.remoteOpponentEloRating;
    final PieceColor localColor = controller.getLocalColor();
    final int? whiteRating = switch (localColor) {
      PieceColor.white => localRating,
      PieceColor.black => opponentRating,
      _ => null,
    };
    final int? blackRating = switch (localColor) {
      PieceColor.white => opponentRating,
      PieceColor.black => localRating,
      _ => null,
    };
    final List<String> ratingLines = <String>[
      if (whiteRating != null)
        S.of(context).remotePlayerElo(S.of(context).white, whiteRating),
      if (blackRating != null)
        S.of(context).remotePlayerElo(S.of(context).black, blackRating),
    ];
    if (ratingLines.isEmpty) {
      return const SizedBox.shrink(key: Key('game_header_remote_elo_hidden'));
    }

    final TextStyle style =
        Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: DB().colorSettings.messageColor,
          fontWeight: FontWeight.w600,
          height: 1.15,
        ) ??
        TextStyle(
          color: DB().colorSettings.messageColor,
          fontWeight: FontWeight.w600,
          height: 1.15,
        );
    return Semantics(
      key: const Key('game_header_remote_elo'),
      container: true,
      label: ratingLines.join(', '),
      child: ExcludeSemantics(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 160),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              for (int i = 0; i < ratingLines.length; i++)
                Text(
                  ratingLines[i],
                  key: Key(
                    i == 0
                        ? 'game_header_remote_elo_first'
                        : 'game_header_remote_elo_second',
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: style,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A compact, accessible contextual game tip.
///
/// The surrounding player row supplies the avatar. The tip stays visually
/// integrated with the board by using the same foreground as its player labels
/// without adding a separate background strip. Long opening names and
/// rule-specific guidance remain available through the standard tooltip.
class GameTipBubble extends StatelessWidget {
  const GameTipBubble({super.key, required this.message, this.maxLines = 2})
    : assert(maxLines > 0, 'Game-tip bubbles need at least one line.');

  final String message;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final Color contentColor = DB().colorSettings.messageColor.withValues(
      alpha: 0.78,
    );
    final TextStyle textStyle =
        Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: contentColor, height: 1.15) ??
        TextStyle(color: contentColor, height: 1.15);

    return Semantics(
      container: true,
      liveRegion: true,
      label: message,
      child: Tooltip(
        message: message,
        child: ExcludeSemantics(
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              // A very narrow side panel cannot show a meaningful tip. Hide
              // the visual message rather than overflowing the board layout;
              // the live-region label remains available to assistive tech.
              if (constraints.hasBoundedWidth && constraints.maxWidth < 48) {
                return const SizedBox.shrink();
              }
              final bool compact =
                  constraints.hasBoundedWidth && constraints.maxWidth < 84;
              return Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: compact ? 4 : 8,
                  vertical: 5,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    if (!compact) ...<Widget>[
                      Padding(
                        padding: const EdgeInsets.only(top: 1),
                        child: Icon(
                          Icons.chat_bubble_outline,
                          size: 14,
                          color: contentColor,
                        ),
                      ),
                      const SizedBox(width: 5),
                    ],
                    Flexible(
                      child: Text(
                        message,
                        maxLines: maxLines,
                        overflow: TextOverflow.ellipsis,
                        style: textStyle,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
