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
      ]),
      builder: (BuildContext context, Widget? child) {
        if (!DB().generalSettings.showGameTips) {
          return const SizedBox.shrink(key: Key('game_header_hidden'));
        }

        final PieceColor side =
            controller.activeSessionSideToMove ??
            controller.activeBoardView.sideToMove;
        final String playerLabel = switch (side) {
          PieceColor.white => S.of(context).white,
          PieceColor.black => S.of(context).black,
          _ => S.of(context).none,
        };
        final String message = controller.headerTipNotifier.message.isEmpty
            ? S.of(context).welcome
            : controller.headerTipNotifier.message;
        return SizedBox(
          key: const Key('game_header_contextual_row'),
          height: widget.preferredSize.height,
          child: Padding(
            key: const Key('game_header_padding'),
            padding: const EdgeInsets.fromLTRB(12, 4, 12, AppTheme.boardMargin),
            child: Row(
              children: <Widget>[
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
      return aiMoveTypeIcons[controller.aiMoveType] ??
          FluentIcons.bot_24_filled;
    }
    return FluentIcons.person_24_filled;
  }
}

/// A compact, accessible speech bubble for a contextual game tip.
///
/// The surrounding player row supplies the avatar, so this widget deliberately
/// focuses on the message. Long opening names and rule-specific guidance stay
/// available through the standard long-press tooltip instead of forcing the
/// board layout to grow.
class GameTipBubble extends StatelessWidget {
  const GameTipBubble({super.key, required this.message, this.maxLines = 2})
    : assert(maxLines > 0, 'Game-tip bubbles need at least one line.');

  final String message;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final TextStyle textStyle =
        Theme.of(context).textTheme.bodySmall?.copyWith(
          color: colorScheme.onSecondaryContainer,
          height: 1.15,
        ) ??
        TextStyle(color: colorScheme.onSecondaryContainer, height: 1.15);

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
              // the visual bubble rather than overflowing the board layout;
              // the live-region label remains available to assistive tech.
              if (constraints.hasBoundedWidth && constraints.maxWidth < 48) {
                return const SizedBox.shrink();
              }
              final bool compact =
                  constraints.hasBoundedWidth && constraints.maxWidth < 84;
              return DecoratedBox(
                decoration: BoxDecoration(
                  color: colorScheme.secondaryContainer,
                  border: Border.all(color: colorScheme.outlineVariant),
                  borderRadius: BorderRadius.circular(AppTheme.boardMargin),
                ),
                child: Padding(
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
                            color: colorScheme.onSecondaryContainer,
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
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
