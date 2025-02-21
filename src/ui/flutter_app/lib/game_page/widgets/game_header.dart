// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// game_header.dart

part of 'game_page.dart';

@visibleForTesting
class GameHeader extends StatefulWidget implements PreferredSizeWidget {
  GameHeader({super.key});

  @override
  final Size preferredSize = Size.fromHeight(
    kToolbarHeight + DB().displaySettings.boardTop + AppTheme.boardMargin,
  );

  @override
  State<GameHeader> createState() => _GameHeaderState();
}

class _GameHeaderState extends State<GameHeader> {
  ScrollNotificationObserverState? _scrollNotificationObserver;
  bool _scrolledUnder = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateScrollObserver();
    _validatePosition();
  }

  void _updateScrollObserver() {
    if (_scrollNotificationObserver != null) {
      _scrollNotificationObserver!.removeListener(_handleScrollNotification);
    }
    _scrollNotificationObserver = ScrollNotificationObserver.of(context);
    if (_scrollNotificationObserver != null) {
      _scrollNotificationObserver!.addListener(_handleScrollNotification);
    }
  }

  void _validatePosition() {
    final String? fen = GameController().position.fen;
    if (fen == null || !GameController().position.validateFen(fen)) {
      GameController().headerTipNotifier.showTip(S.of(context).invalidPosition);
    }
  }

  @override
  void dispose() {
    _removeScrollObserver();
    super.dispose();
  }

  void _removeScrollObserver() {
    if (_scrollNotificationObserver != null) {
      _scrollNotificationObserver!.removeListener(_handleScrollNotification);
      _scrollNotificationObserver = null;
    }
  }

  void _handleScrollNotification(ScrollNotification notification) {
    if (notification is ScrollUpdateNotification) {
      final bool oldScrolledUnder = _scrolledUnder;
      _scrolledUnder = notification.depth == 0 &&
          notification.metrics.extentBefore > 0 &&
          notification.metrics.axis == Axis.vertical;
      if (_scrolledUnder != oldScrolledUnder) {
        setState(() {
          // React to a change in MaterialState.scrolledUnder
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      key: const Key('game_header_align'),
      alignment: Alignment.topCenter,
      child: BlockSemantics(
        key: const Key('game_header_block_semantics'),
        child: Center(
          key: const Key('game_header_center'),
          child: Padding(
            key: const Key('game_header_padding'),
            padding: EdgeInsets.only(top: DB().displaySettings.boardTop),
            child: Column(
              key: const Key('game_header_column'),
              children: <Widget>[
                const HeaderIcons(key: Key('header_icons')),
                _buildDivider(),
                const HeaderTip(key: Key('header_tip')),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDivider() {
    if (DB().displaySettings.isPositionalAdvantageIndicatorShown) {
      return _buildPositionalAdvantageDivider();
    } else {
      return _buildDefaultDivider();
    }
  }

  Widget _buildPositionalAdvantageDivider() {
    int value =
        GameController().value == null ? 0 : int.parse(GameController().value!);
    const double opacity = 1;
    const int valueLimit = 100;

    if ((value == valueUnique || value == -valueUnique) ||
        GameController().gameInstance.gameMode == GameMode.humanVsHuman) {
      value = valueEachPiece * GameController().position.pieceCountDiff();
    }

    value = (value * 2).clamp(-valueLimit, valueLimit);

    final num dividerWhiteLength = valueLimit + value;
    final num dividerBlackLength = valueLimit - value;

    return Container(
      key: const Key('positional_advantage_divider'),
      height: 2,
      width: valueLimit * 2,
      margin: const EdgeInsets.only(bottom: AppTheme.boardMargin),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(2),
      ),
      child: Row(
        key: const Key('positional_advantage_row'),
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Container(
            key: const Key('divider_white_container'),
            height: 2,
            width: dividerWhiteLength.toDouble(),
            color:
                DB().colorSettings.whitePieceColor.withValues(alpha: opacity),
          ),
          Container(
            key: const Key('divider_black_container'),
            height: 2,
            width: dividerBlackLength.toDouble(),
            color:
                DB().colorSettings.blackPieceColor.withValues(alpha: opacity),
          ),
        ],
      ),
    );
  }

  Widget _buildDefaultDivider() {
    const double opacity = 1;
    return Container(
      key: const Key('default_divider'),
      height: 2,
      width: 180,
      margin: const EdgeInsets.only(bottom: AppTheme.boardMargin),
      decoration: BoxDecoration(
        color: (DB().colorSettings.darkBackgroundColor == Colors.white ||
                DB().colorSettings.darkBackgroundColor ==
                    const Color.fromARGB(1, 255, 255, 255))
            ? DB().colorSettings.messageColor.withValues(alpha: opacity)
            : DB()
                .colorSettings
                .boardBackgroundColor
                .withValues(alpha: opacity),
        borderRadius: BorderRadius.circular(2),
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
    _editingController = TextEditingController(text: _messageNotifier.value);
  }

  /// Displays a tip message from the notifier.
  void _showTip() {
    final HeaderTipNotifier headerTipNotifier =
        GameController().headerTipNotifier;

    if (headerTipNotifier.showSnackBar) {
      rootScaffoldMessengerKey.currentState!
          .showSnackBarClear(headerTipNotifier.message);
    }

    // Sync _messageNotifier with the new tip.
    _messageNotifier.value = headerTipNotifier.message;
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
        // Retrieve the active node’s comment, if any.
        final PgnNode<ExtMove>? activeNode =
            GameController().gameRecorder.activeNode;
        // Join all comments for display. (If you only need the first, adjust accordingly.)
        final String nodeComment =
            (activeNode?.data?.comments?.isNotEmpty ?? false)
                ? activeNode!.data!.comments!.join(' ')
                : "";

        // If there’s an existing comment in the PGN node, show it in yellow.
        // Otherwise, use _messageNotifier.value with original color.
        final bool hasNodeComment = nodeComment.isNotEmpty;
        final String textToShow = hasNodeComment
            ? nodeComment // **Do not add braces**
            : (currentDisplay.isEmpty ? S.of(context).welcome : currentDisplay);

        // Decide the color: yellow if PGN node has a comment, otherwise normal.
        final Color displayColor =
            hasNodeComment ? Colors.yellow : DB().colorSettings.messageColor;

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
                        fontSize:
                            AppTheme.textScaler.scale(AppTheme.defaultFontSize),
                        fontFeatures: const <FontFeature>[
                          FontFeature.tabularFigures()
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
                    final TextSpan span = TextSpan(
                      text: textToShow,
                      style: TextStyle(
                        color: displayColor,
                        fontSize:
                            AppTheme.textScaler.scale(AppTheme.defaultFontSize),
                        fontFeatures: const <FontFeature>[
                          FontFeature.tabularFigures()
                        ],
                      ),
                    );
                    final TextPainter tp = TextPainter(
                      text: span,
                      maxLines: 1,
                      textDirection: TextDirection.ltr,
                    );
                    tp.layout(maxWidth: constraints.maxWidth);

                    // If text doesn't exceed max width, center it; otherwise left-align.
                    final bool fits = !tp.didExceedMaxLines;

                    return Text(
                      textToShow,
                      key: const Key('header_tip_text'),
                      maxLines: 1,
                      textAlign: fits ? TextAlign.center : TextAlign.left,
                      style: TextStyle(
                        color: displayColor,
                        fontSize:
                            AppTheme.textScaler.scale(AppTheme.defaultFontSize),
                        fontFeatures: const <FontFeature>[
                          FontFeature.tabularFigures()
                        ],
                      ),
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
  final ValueNotifier<IconData> _iconDataNotifier =
      ValueNotifier<IconData>(GameController().position.sideToMove.icon);

  // Add ValueNotifier for lanHostPlaysWhite
  final ValueNotifier<bool?> _lanHostPlaysWhiteNotifier =
      ValueNotifier<bool?>(GameController().lanHostPlaysWhite);

  @override
  void initState() {
    super.initState();
    GameController().headerIconsNotifier.addListener(_updateIcons);
    // Listen to changes in lanHostPlaysWhite via a custom method or direct property observation
    _refreshLanHostPlaysWhite();
  }

  void _updateIcons() {
    _iconDataNotifier.value = GameController().position.sideToMove.icon;
    _refreshLanHostPlaysWhite();
  }

  void _refreshLanHostPlaysWhite() {
    _lanHostPlaysWhiteNotifier.value = GameController().lanHostPlaysWhite;
  }

// In game_header.dart, HeaderStateIcons class
  (IconData, IconData) _getLanModeIcons() {
    final GameController controller = GameController();
    if (controller.gameInstance.gameMode == GameMode.humanVsLAN) {
      const IconData humanIcon = FluentIcons.person_24_filled;
      const IconData wifiIcon = FluentIcons.wifi_1_24_filled;
      final bool amIHost = controller.networkService?.isHost ?? false;

      if (amIHost) {
        // Host: White, Left=Person, Right=Wi-Fi
        return (humanIcon, wifiIcon);
      } else {
        // Client: Black, Left=Wi-Fi, Right=Person
        return (wifiIcon, humanIcon);
      }
    }

    // Non-LAN mode fallback
    return (
      controller.gameInstance.gameMode.leftHeaderIcon,
      controller.gameInstance.gameMode.rightHeaderIcon
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<IconData>(
      key: const Key('header_icons_value_listenable_builder'),
      valueListenable: _iconDataNotifier,
      builder: (BuildContext context, IconData turnIcon, Widget? child) {
        // Remove lanHostPlaysWhite dependency since it's always true
        final (IconData leftIcon, IconData rightIcon) = _getLanModeIcons();
        return IconTheme(
          key: const Key('header_icons_icon_theme'),
          data: IconThemeData(color: DB().colorSettings.messageColor),
          child: Row(
            key: const Key('header_icon_row'),
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(leftIcon, key: const Key('left_header_icon')),
              Icon(turnIcon, key: const Key('current_side_icon')),
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
