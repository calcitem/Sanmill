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

@visibleForTesting
class HeaderTip extends StatefulWidget {
  const HeaderTip({super.key});

  @override
  HeaderTipState createState() => HeaderTipState();
}

class HeaderTipState extends State<HeaderTip> {
  final ValueNotifier<String> _messageNotifier = ValueNotifier<String>("");

  /// Indicates whether the tip is being edited.
  bool _isEditing = false;

  /// FocusNode to detect taps outside the editable area to exit editing mode.
  late final FocusNode _focusNode;

  /// Controller for the editable text field.
  late final TextEditingController _editingController;

  @override
  void initState() {
    super.initState();
    GameController().headerTipNotifier.addListener(_showTip);

    // Initialize the FocusNode and controller.
    _focusNode = FocusNode();
    _focusNode.addListener(_handleFocusChange);
    _editingController = SafeTextEditingController(
      text: _messageNotifier.value,
    );
  }

  /// Displays a tip message from the notifier.
  void _showTip() {
    final HeaderTipNotifier headerTipNotifier =
        GameController().headerTipNotifier;

    if (headerTipNotifier.showSnackBar) {
      rootScaffoldMessengerKey.currentState!.showSnackBarClear(
        headerTipNotifier.message,
      );
    }

    final bool messageUnchanged =
        _messageNotifier.value == headerTipNotifier.message;
    // Sync _messageNotifier with the new tip.
    _messageNotifier.value = headerTipNotifier.message;
    if (messageUnchanged && mounted) {
      setState(() {});
    }
    // If currently editing, also update the editing controller text.
    if (_isEditing) {
      _editingController.text = headerTipNotifier.message;
    }
  }

  /// Called when focus changes; if editing loses focus, finalize the edit.
  void _handleFocusChange() {
    if (!_focusNode.hasFocus && _isEditing) {
      _finalizeEditing();
    }
  }

  /// Finalizes editing, updates the displayed text,
  /// and stores the text as a comment in the active PGN node.
  void _finalizeEditing() {
    setState(() {
      _isEditing = false;
      final String rawText = _editingController.text;

      // 1) **No longer add braces** to _messageNotifier.value.
      _messageNotifier.value = rawText;

      // 2) Retrieve current PGN node and update its comments with unbraced text.
      final PgnNode<ExtMove>? activeNode =
          GameController().gameRecorder.activeNode;
      if (activeNode?.data != null) {
        activeNode!.data!.comments ??= <String>[];
        activeNode.data!.comments!.clear();
        // 3) We store unbraced text in the comment.
        activeNode.data!.comments!.add(rawText);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      key: const Key('header_tip_value_listenable_builder'),
      valueListenable: _messageNotifier,
      builder: (BuildContext context, String currentDisplay, Widget? child) {
        if (!DB().generalSettings.showGameTips) {
          return const SizedBox.shrink(key: Key('header_tip_hidden'));
        }
        // Retrieve the active node's comment, if any.
        final PgnNode<ExtMove>? activeNode =
            GameController().gameRecorder.activeNode;
        // Join all comments for display. (If you only need the first, adjust accordingly.)
        final String nodeComment =
            (activeNode?.data?.comments?.isNotEmpty ?? false)
            ? activeNode!.data!.comments!.join(' ')
            : "";

        final bool isOpeningInfo =
            GameController().headerTipNotifier.kind ==
            HeaderTipKind.openingInfo;
        // Opening recognition is an explicit header signal; do not hide it
        // behind a PGN comment stored on the current move.
        final bool hasNodeComment = nodeComment.isNotEmpty && !isOpeningInfo;
        final String textToShow = hasNodeComment
            ? nodeComment // **Do not add braces**
            : (currentDisplay.isEmpty ? S.of(context).welcome : currentDisplay);

        // Decide the color: yellow if PGN node has a comment, otherwise normal.
        final Color displayColor = hasNodeComment
            ? Colors.yellow
            : DB().colorSettings.messageColor;

        // Now build UI. If editing, show a TextField. If not, show static text.
        return Semantics(
          key: const Key('header_tip_semantics'),
          enabled: true,
          child: GestureDetector(
            onTap: () {
              // 3) If tapped and we are NOT editing, enter edit mode.
              if (!_isEditing) {
                setState(() {
                  _isEditing = true;

                  // Compare the text currently visible vs. nodeComment.
                  final String visibleRaw = textToShow;
                  if (visibleRaw != nodeComment) {
                    // If they differ, clear the editor.
                    _editingController.text = "";
                  } else {
                    // Otherwise, keep the node comment.
                    _editingController.text = nodeComment;
                  }
                });
              }
            },
            child: SizedBox(
              key: const Key('header_tip_sized_box'),
              height: 24 * DB().displaySettings.fontScale,
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  if (_isEditing) {
                    // Editing mode
                    return TextField(
                      key: const Key('header_tip_textfield'),
                      controller: _editingController,
                      focusNode: _focusNode,
                      style: TextStyle(
                        color: displayColor,
                        fontSize: AppTheme.textScaler.scale(
                          AppTheme.defaultFontSize,
                        ),
                        fontFeatures: const <FontFeature>[
                          FontFeature.tabularFigures(),
                        ],
                      ),
                      onEditingComplete: () {
                        _finalizeEditing();
                        // Hide the keyboard
                        FocusScope.of(context).unfocus();
                      },
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                        border: InputBorder.none,
                      ),
                    );
                  } else {
                    // Read-only mode
                    final TextStyle textStyle = TextStyle(
                      color: displayColor,
                      fontSize: AppTheme.textScaler.scale(
                        AppTheme.defaultFontSize,
                      ),
                      fontFeatures: const <FontFeature>[
                        FontFeature.tabularFigures(),
                      ],
                    );
                    final TextSpan span = TextSpan(
                      text: textToShow,
                      style: textStyle,
                    );
                    final TextPainter tp = TextPainter(
                      text: span,
                      maxLines: 1,
                      textDirection: TextDirection.ltr,
                    );
                    tp.layout(maxWidth: constraints.maxWidth);

                    if (!tp.didExceedMaxLines) {
                      return Text(
                        textToShow,
                        key: const Key('header_tip_text'),
                        maxLines: 1,
                        textAlign: TextAlign.center,
                        style: textStyle,
                      );
                    }

                    return Marquee(
                      key: const Key('header_tip_marquee'),
                      text: textToShow,
                      style: TextStyle(
                        color: displayColor,
                        fontSize: AppTheme.textScaler.scale(
                          AppTheme.defaultFontSize,
                        ),
                        fontFeatures: const <FontFeature>[
                          FontFeature.tabularFigures(),
                        ],
                      ),
                      blankSpace: 40.0,
                      velocity: 30.0,
                      pauseAfterRound: const Duration(seconds: 1),
                    );
                  }
                },
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    GameController().headerTipNotifier.removeListener(_showTip);
    _focusNode.dispose();
    _editingController.dispose();
    super.dispose();
  }
}

@visibleForTesting
class HeaderIcons extends StatefulWidget {
  const HeaderIcons({super.key});

  @override
  HeaderStateIcons createState() => HeaderStateIcons();
}

class HeaderStateIcons extends State<HeaderIcons> {
  final ValueNotifier<IconData> _iconDataNotifier = ValueNotifier<IconData>(
    GameController().activeSideToMoveIcon,
  );

  // Last AI move source rendered by the header. The bot glyph in build() is
  // derived from GameController.aiMoveType, which the side-to-move
  // ValueNotifier does not track, so the header must rebuild when it changes.
  Object? _lastAiMoveType = GameController().aiMoveType;

  @override
  void initState() {
    super.initState();
    GameController().headerIconsNotifier.addListener(_updateIcons);
  }

  void _updateIcons() {
    final GameController controller = GameController();
    _iconDataNotifier.value = controller.activeSideToMoveIcon;

    // The AI bot glyph (left/right header icon) is read from
    // GameController.aiMoveType in build(), but the side-to-move ValueNotifier
    // only rebuilds the header when the turn icon changes. Rebuild explicitly
    // when the move source changes so the icon updates on the same turn the AI
    // plays the move instead of on a later turn.
    final Object? botType = controller.aiMoveType;
    if (mounted && botType != _lastAiMoveType) {
      _lastAiMoveType = botType;
      setState(() {});
    }
  }

  (IconData, IconData) _getModeIcons() {
    final GameController controller = GameController();
    if (controller.isRemoteGameMode) {
      const IconData humanIcon = FluentIcons.person_24_filled;
      final IconData remoteIcon =
          controller.gameInstance.gameMode == GameMode.humanVsBluetooth
          ? FluentIcons.bluetooth_24_filled
          : FluentIcons.wifi_1_24_filled;
      return controller.getLocalColor() == PieceColor.white
          ? (humanIcon, remoteIcon)
          : (remoteIcon, humanIcon);
    }

    // Non-LAN mode fallback
    return (
      controller.gameInstance.gameMode.leftHeaderIcon,
      controller.gameInstance.gameMode.rightHeaderIcon,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<IconData>(
      key: const Key('header_icons_value_listenable_builder'),
      valueListenable: _iconDataNotifier,
      builder: (BuildContext context, IconData turnIcon, Widget? child) {
        final (IconData leftIcon, IconData rightIcon) = _getModeIcons();

        return IconTheme(
          key: const Key('header_icons_icon_theme'),
          data: IconThemeData(color: DB().colorSettings.messageColor),
          child: Row(
            key: const Key('header_icon_row'),
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(leftIcon, key: const Key('left_header_icon')),
              Padding(
                padding: EdgeInsets.zero, // Spacing around the center icon
                child: Icon(turnIcon, key: const Key('current_side_icon')),
              ),
              Icon(rightIcon, key: const Key('right_header_icon')),
            ],
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    GameController().headerIconsNotifier.removeListener(_updateIcons);
    super.dispose();
  }
}
