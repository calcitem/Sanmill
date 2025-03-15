// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// moves_list_page.dart

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../generated/intl/l10n.dart';
import '../../shared/database/database.dart';
import '../../shared/themes/app_theme.dart';
import '../../shared/widgets/snackbars/scaffold_messenger.dart';
import '../services/import_export/pgn.dart';
import '../services/mill.dart';
import 'mini_board.dart';

/// Defines possible view layouts for this MovesListPage.
enum MovesViewLayout {
  large,
  medium,
  small,
  list,
  details,
}

/// MovesListPage can display PGN nodes in different layouts.
/// The user can pick from a set of layout options via a single active icon which,
/// when tapped, reveals a row of layout icons.
class MovesListPage extends StatefulWidget {
  const MovesListPage({super.key});

  @override
  MovesListPageState createState() => MovesListPageState();
}

class MovesListPageState extends State<MovesListPage> {
  /// A flat list of all PGN nodes (collected recursively).
  final List<PgnNode<ExtMove>> _allNodes = <PgnNode<ExtMove>>[];

  /// Whether to reverse the order of the nodes.
  bool _isReversedOrder = false;

  /// ScrollController to control the scrolling of the ListView or GridView.
  final ScrollController _scrollController = ScrollController();

  /// Current layout selection, defaulting to 'medium' (original).
  MovesViewLayout _currentLayout = MovesViewLayout.medium;

  @override
  void initState() {
    super.initState();
    // Collect all nodes from the PGN tree into _allNodes.
    // For example:
    // final PgnNode<ExtMove> root = GameController().gameRecorder.pgnRoot;
    // _collectAllNodes(root);
    _refreshAllNodes();
  }

  // Uncomment if you want a fully recursive collecting method.
  // void _collectAllNodes(PgnNode<ExtMove> node) {
  //   _allNodes.add(node);
  //   for (final PgnNode<ExtMove> child in node.children) {
  //     _collectAllNodes(child);
  //   }
  // }

  /// Clears and refreshes _allNodes from the game recorder.
  void _refreshAllNodes() {
    _allNodes
      ..clear()
      ..addAll(GameController().gameRecorder.mainlineNodes);

    int currentMoveIndex = 0; // Initialize move index for the first node
    int currentRound = 1; // Initialize round number starting at 1
    PieceColor?
        lastNonRemoveSide; // To track the side of the last non-remove move

    for (int i = 0; i < _allNodes.length; i++) {
      final PgnNode<ExtMove> node = _allNodes[i];

      // Set moveIndex as before
      if (i == 0) {
        // First node always gets moveIndex 0
        node.data?.moveIndex = currentMoveIndex;
      } else if (node.data?.type == MoveType.remove) {
        // If it's a remove type, use the previous node's moveIndex
        node.data?.moveIndex = _allNodes[i - 1].data?.moveIndex;
      } else {
        // Otherwise, increment the previous node's moveIndex
        currentMoveIndex = (_allNodes[i - 1].data?.moveIndex ?? 0) + 1;
        node.data?.moveIndex = currentMoveIndex;
      }

      // Calculate and assign roundIndex for each move
      if (node.data != null) {
        if (node.data!.type == MoveType.remove) {
          // For remove moves, assign the same round as the last non-remove move
          node.data!.roundIndex = currentRound;
        } else {
          // For non-remove moves:
          // If the last non-remove move was made by Black and current move is by White,
          // it indicates a new round should start.
          if (lastNonRemoveSide == PieceColor.black &&
              node.data!.side == PieceColor.white) {
            currentRound++;
          }
          node.data!.roundIndex = currentRound;
          lastNonRemoveSide =
              node.data!.side; // Update last non-remove move side
        }
      }
    }
  }

  /// Helper method to load a game, then refresh.
  Future<void> _loadGame() async {
    await GameController.load(context, shouldPop: false);
    // Wait briefly, then refresh our list of nodes.
    await Future<void>.delayed(const Duration(milliseconds: 500));
    setState(_refreshAllNodes);
  }

  /// Helper method to import a game, then refresh.
  Future<void> _importGame() async {
    await GameController.import(context, shouldPop: false);
    // Wait briefly, then refresh our list of nodes.
    await Future<void>.delayed(const Duration(milliseconds: 500));
    setState(_refreshAllNodes);
  }

  void _saveGame() {
    GameController.save(context, shouldPop: false);
  }

  void _exportGame() {
    GameController.export(context, shouldPop: false);
  }

  /// Copies the moveListPrompt (a special format for LLM) into the clipboard.
  /// Displays a SnackBar indicating success or if there's no prompt data.
  Future<void> _copyLLMPrompt() async {
    final String prompt = GameController().gameRecorder.moveListPrompt;
    if (prompt.isEmpty) {
      rootScaffoldMessengerKey.currentState!.showSnackBar(
          SnackBar(content: Text(S.of(context).noLlmPromptAvailable)));
      return;
    }
    await Clipboard.setData(ClipboardData(text: prompt));

    if (!mounted) {
      return;
    }
    rootScaffoldMessengerKey.currentState!
        .showSnackBarClear(S.of(context).llmPromptCopiedToClipboard);
  }

  /// Scrolls the list/grid to the top with an animation.
  void _scrollToTop() {
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  /// Scrolls the list/grid to the bottom with an animation.
  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  /// Builds a single large icon with a label, used in the empty state.
  Widget _emptyStateIcon({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            icon,
            size: 64,
            color: DB().colorSettings.messageColor,
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(color: DB().colorSettings.messageColor),
          ),
        ],
      ),
    );
  }

  /// Builds a simple empty-state page with two large icons: Load game and Import game.
  Widget _buildEmptyState() {
    return Center(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          _emptyStateIcon(
            icon: FluentIcons.folder_open_24_regular,
            label: S.of(context).loadGame,
            onTap: _loadGame,
          ),
          const SizedBox(width: 40),
          _emptyStateIcon(
            icon: FluentIcons.clipboard_paste_24_regular,
            label: S.of(context).importGame,
            onTap: _importGame,
          ),
        ],
      ),
    );
  }

  /// Builds the "3-column list layout": Round, White, Black.
  Widget _buildThreeColumnListLayout() {
    // 1. Group all moves by round.
    final Map<int, List<PgnNode<ExtMove>>> roundMap =
        <int, List<PgnNode<ExtMove>>>{};
    for (final PgnNode<ExtMove> node in _allNodes) {
      final ExtMove? data = node.data;
      if (data == null) {
        continue;
      }
      final int roundIndex = data.roundIndex ?? 0;
      roundMap.putIfAbsent(roundIndex, () => <PgnNode<ExtMove>>[]).add(node);
    }

    // Get sorted round indexes in ascending order.
    final List<int> sortedRoundsAsc = roundMap.keys.toList()..sort();
    // Use reversed order if _isReversedOrder is true.
    final List<int> sortedRounds =
        _isReversedOrder ? sortedRoundsAsc.reversed.toList() : sortedRoundsAsc;

    return SingleChildScrollView(
      child: Column(
        children: sortedRounds.map((int roundIndex) {
          final List<PgnNode<ExtMove>> nodesOfRound = roundMap[roundIndex]!;

          // 2. Separate moves into white vs black.
          final List<String> whites = <String>[];
          final List<String> blacks = <String>[];

          for (final PgnNode<ExtMove> n in nodesOfRound) {
            final PieceColor? side = n.data?.side;
            final String notation = n.data?.notation ?? '';
            if (side == PieceColor.white) {
              // Remove the "X." prefix, e.g. "5. e4" -> "e4"
              final String cleaned =
                  notation.replaceAll(RegExp(r'^\d+\.\s*'), '');
              whites.add(cleaned);
            } else if (side == PieceColor.black) {
              // Remove the "X..." prefix, e.g. "5... c5" -> "c5"
              final String cleaned =
                  notation.replaceAll(RegExp(r'^\d+\.\.\.\s*'), '');
              blacks.add(cleaned);
            }
          }

          final String whiteMoves = whites.join();
          final String blackMoves = blacks.join();

          return Card(
            color: DB().colorSettings.darkBackgroundColor,
            margin: const EdgeInsets.all(6.0),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
              child: Row(
                children: <Widget>[
                  SizedBox(
                    width: 30,
                    child: Text(
                      "$roundIndex. ",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: DB().colorSettings.messageColor),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      whiteMoves,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: DB().colorSettings.messageColor),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      blackMoves,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: DB().colorSettings.messageColor),
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  /// Builds the main body widget according to the chosen view layout.
  Widget _buildBody() {
    if (_allNodes.isEmpty) {
      return _buildEmptyState();
    }

    switch (_currentLayout) {
      case MovesViewLayout.large:
      case MovesViewLayout.medium:
      case MovesViewLayout.details:
        // Single-column ListView of MoveListItem with reversed index if needed.
        return ListView.builder(
          controller: _scrollController,
          itemCount: _allNodes.length,
          itemBuilder: (BuildContext context, int index) {
            final int idx =
                _isReversedOrder ? (_allNodes.length - 1 - index) : index;
            final PgnNode<ExtMove> node = _allNodes[idx];
            return MoveListItem(
              node: node,
              layout: _currentLayout,
            );
          },
        );

      case MovesViewLayout.small:
        // For small boards, display a grid with 3 or 5 columns.
        final bool isPortrait =
            MediaQuery.of(context).orientation == Orientation.portrait;
        final int crossAxisCount = isPortrait ? 3 : 5;

        return GridView.builder(
          controller: _scrollController,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            childAspectRatio: 0.9,
          ),
          itemCount: _allNodes.length,
          itemBuilder: (BuildContext context, int index) {
            final int idx =
                _isReversedOrder ? (_allNodes.length - 1 - index) : index;
            return MoveListItem(
              node: _allNodes[idx],
              layout: _currentLayout,
            );
          },
        );

      case MovesViewLayout.list:
        // Now replaced with 3-column layout: Round / White / Black.
        return _buildThreeColumnListLayout();
    }
  }

  /// Maps each layout to its corresponding Fluent icon.
  IconData _iconForLayout(MovesViewLayout layout) {
    switch (layout) {
      case MovesViewLayout.large:
        return FluentIcons.square_24_regular;
      case MovesViewLayout.medium:
        return FluentIcons.apps_list_24_regular;
      case MovesViewLayout.small:
        return FluentIcons.grid_24_regular;
      case MovesViewLayout.list:
        return FluentIcons.text_column_two_24_regular;
      case MovesViewLayout.details:
        return FluentIcons.text_column_two_left_24_regular;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.appBarTheme.backgroundColor,
      appBar: AppBar(
        title: Text(
          S.of(context).moveList,
          style: AppTheme.appBarTheme.titleTextStyle,
        ),
        actions: <Widget>[
          // Reverse order icon.
          IconButton(
            icon: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              transitionBuilder: (Widget child, Animation<double> anim) =>
                  ScaleTransition(scale: anim, child: child),
              child: _isReversedOrder
                  ? const Icon(
                      FluentIcons.arrow_sort_up_24_regular,
                      key: ValueKey<String>('descending'),
                    )
                  : const Icon(
                      FluentIcons.arrow_sort_down_24_regular,
                      key: ValueKey<String>('ascending'),
                    ),
            ),
            onPressed: () {
              setState(() {
                // Only toggle the flag; do not physically reverse _allNodes.
                _isReversedOrder = !_isReversedOrder;
              });
            },
          ),
          // Layout selection: one active icon in the AppBar.
          // Tapping it opens a popup with a horizontal row of icons.
          PopupMenuButton<void>(
            icon: Icon(_iconForLayout(_currentLayout)),
            // color: DB().colorSettings.mainToolbarBackgroundColor,
            onSelected: (_) {},
            itemBuilder: (BuildContext context) {
              return <PopupMenuEntry<void>>[
                PopupMenuItem<void>(
                  // Disable direct selection so that only the icons inside react.
                  enabled: false,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children:
                        MovesViewLayout.values.map((MovesViewLayout layout) {
                      final bool isSelected = layout == _currentLayout;
                      return IconButton(
                        icon: Icon(
                          _iconForLayout(layout),
                          color: isSelected ? Colors.black : Colors.black87,
                        ),
                        onPressed: () {
                          setState(() {
                            _currentLayout = layout;
                          });
                          Navigator.pop(context);
                        },
                      );
                    }).toList(),
                  ),
                ),
              ];
            },
          ),
          // The "three vertical dots" menu with multiple PopupMenuItem.
          PopupMenuButton<String>(
            onSelected: (String value) async {
              switch (value) {
                case 'top':
                  _scrollToTop();
                  break;
                case 'bottom':
                  _scrollToBottom();
                  break;
                case 'save_game':
                  _saveGame();
                  break;
                case 'load_game':
                  await _loadGame();
                  break;
                case 'import_game':
                  await _importGame();
                  break;
                case 'export_game':
                  _exportGame();
                  break;
                case 'copy_llm_prompt':
                  await _copyLLMPrompt();
                  break;
              }
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              PopupMenuItem<String>(
                value: 'top',
                child: Row(
                  children: <Widget>[
                    const Icon(FluentIcons.arrow_upload_24_regular,
                        color: Colors.black54),
                    const SizedBox(width: 8),
                    Text(S.of(context).top),
                  ],
                ),
              ),
              PopupMenuItem<String>(
                value: 'bottom',
                child: Row(
                  children: <Widget>[
                    const Icon(FluentIcons.arrow_download_24_regular,
                        color: Colors.black54),
                    const SizedBox(width: 8),
                    Text(S.of(context).bottom),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem<String>(
                value: 'save_game',
                child: Row(
                  children: <Widget>[
                    const Icon(FluentIcons.save_24_regular,
                        color: Colors.black54),
                    const SizedBox(width: 8),
                    Text(S.of(context).saveGame),
                  ],
                ),
              ),
              PopupMenuItem<String>(
                value: 'load_game',
                child: Row(
                  children: <Widget>[
                    const Icon(FluentIcons.folder_open_24_regular,
                        color: Colors.black54),
                    const SizedBox(width: 8),
                    Text(S.of(context).loadGame),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem<String>(
                value: 'import_game',
                child: Row(
                  children: <Widget>[
                    const Icon(FluentIcons.clipboard_paste_24_regular,
                        color: Colors.black54),
                    const SizedBox(width: 8),
                    Text(S.of(context).importGame),
                  ],
                ),
              ),
              PopupMenuItem<String>(
                value: 'export_game',
                child: Row(
                  children: <Widget>[
                    const Icon(FluentIcons.copy_24_regular,
                        color: Colors.black54),
                    const SizedBox(width: 8),
                    Text(S.of(context).exportGame),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem<String>(
                value: 'copy_llm_prompt',
                child: Row(
                  children: <Widget>[
                    const Icon(FluentIcons.text_grammar_wand_24_regular,
                        color: Colors.black54),
                    const SizedBox(width: 8),
                    Text(S.of(context).llmPrompt),
                  ],
                ),
              ),
            ],
            icon: const Icon(FluentIcons.more_vertical_24_regular),
          ),
        ],
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () {
          // Hide any active mini board and dismiss keyboard.
          MiniBoardState.hideActiveBoard();
          FocusScope.of(context).unfocus();
        },
        child: _buildBody(),
      ),
    );
  }
}

/// A single item in the move list.
/// It adapts its layout depending on [layout].
class MoveListItem extends StatefulWidget {
  const MoveListItem({
    required this.node,
    required this.layout,
    super.key,
  });

  final PgnNode<ExtMove> node;
  final MovesViewLayout layout;

  @override
  MoveListItemState createState() => MoveListItemState();
}

class MoveListItemState extends State<MoveListItem> {
  /// Whether the comment is in editing mode.
  bool _isEditing = false;

  /// FocusNode to handle tap outside the TextField.
  late final FocusNode _focusNode;

  /// Controller for editing the comment text.
  late final TextEditingController _editingController;

  /// Cached comment text displayed in read-only mode.
  String _comment = "";

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    _focusNode.addListener(_handleFocusChange);
    _comment = _retrieveComment(widget.node);
    _editingController = TextEditingController(text: _comment);
  }

  /// Retrieves comment from node.data, joined if multiple.
  String _retrieveComment(PgnNode<ExtMove> node) {
    final ExtMove? data = node.data;
    if (data?.comments != null && data!.comments!.isNotEmpty) {
      return data.comments!.join(" ");
    } else if (data?.startingComments != null &&
        data!.startingComments!.isNotEmpty) {
      return data.startingComments!.join(" ");
    }
    return "";
  }

  /// Handle losing focus. If editing, finalize the edit.
  void _handleFocusChange() {
    if (!_focusNode.hasFocus && _isEditing) {
      _finalizeEditing();
    }
  }

  /// Saves the edited comment back into the PGN node.
  void _finalizeEditing() {
    setState(() {
      _isEditing = false;
      final String newComment = _editingController.text.trim();
      _comment = newComment;

      widget.node.data?.comments ??= <String>[];
      widget.node.data?.comments!.clear();
      if (newComment.isNotEmpty) {
        widget.node.data?.comments!.add(newComment);
      }
    });
  }

  /// Builds a reusable widget that either shows a comment or a TextField to edit it.
  Widget _buildEditableComment(TextStyle style) {
    final bool hasComment = _comment.isNotEmpty;
    if (_isEditing) {
      return TextField(
        focusNode: _focusNode,
        controller: _editingController,
        style: style,
        maxLines: null,
        keyboardType: TextInputType.multiline,
        decoration: const InputDecoration(
          isDense: true,
          border: InputBorder.none,
        ),
        onEditingComplete: () {
          _finalizeEditing();
          FocusScope.of(context).unfocus();
        },
      );
    } else {
      return GestureDetector(
        onTap: () {
          setState(() {
            _isEditing = true;
            _editingController.text = hasComment ? _comment : "";
          });
          _focusNode.requestFocus();
        },
        child: hasComment
            ? Text(
                _comment,
                style: style,
              )
            : Icon(
                FluentIcons.edit_16_regular,
                size: 16,
                color: style.color?.withAlpha(120),
              ),
      );
    }
  }

  /// Builds the appropriate widget based on [widget.layout].
  @override
  Widget build(BuildContext context) {
    final ExtMove? moveData = widget.node.data;
    final String notation = moveData?.notation ?? "";
    final String boardLayout = moveData?.boardLayout ?? "";
    // Determine side: used to decide how to show "roundIndex..."
    final bool isWhite = (moveData?.side == PieceColor.white);
    final int? roundIndex = moveData?.roundIndex;
    final String roundNotation = (roundIndex != null)
        ? (isWhite ? "$roundIndex. " : "$roundIndex... ")
        : "";

    // Common text style.
    final TextStyle combinedStyle = TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.bold,
      color: DB().colorSettings.messageColor,
    );

    switch (widget.layout) {
      case MovesViewLayout.large:
        return _buildLargeLayout(
            notation, boardLayout, roundNotation, combinedStyle);
      case MovesViewLayout.medium:
        return _buildMediumLayout(
            notation, boardLayout, roundNotation, combinedStyle);
      case MovesViewLayout.small:
        return _buildSmallLayout(
            notation, boardLayout, roundNotation, combinedStyle);
      case MovesViewLayout.list:
        // The "list" layout is now handled in MovesListPageState._buildThreeColumnListLayout()
        // so we can return an empty container here.
        return const SizedBox.shrink();
      case MovesViewLayout.details:
        return _buildDetailsLayout(notation, roundNotation, combinedStyle);
    }
  }

  /// Large boards: single column, board on top, then "roundNotation + notation", then comment.
  Widget _buildLargeLayout(
    String notation,
    String boardLayout,
    String roundNotation,
    TextStyle combinedStyle,
  ) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Container(
        color: DB().colorSettings.darkBackgroundColor,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (boardLayout.isNotEmpty)
              AspectRatio(
                aspectRatio: 1.0,
                child: MiniBoard(
                  boardLayout: boardLayout,
                  extMove: widget.node.data,
                ),
              ),
            const SizedBox(height: 8),
            Text(roundNotation + notation, style: combinedStyle),
            const SizedBox(height: 6),
            _buildEditableComment(
              TextStyle(
                fontSize: 12,
                color: DB().colorSettings.messageColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Medium boards: board on the left, "roundNotation + notation" and comment on the right.
  Widget _buildMediumLayout(
    String notation,
    String boardLayout,
    String roundNotation,
    TextStyle combinedStyle,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6.0),
      child: Container(
        decoration: BoxDecoration(
          color: DB().colorSettings.darkBackgroundColor,
          borderRadius: BorderRadius.circular(4),
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: Colors.black26,
              blurRadius: 2,
              offset: Offset(2, 2),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // Left: mini board.
            Expanded(
              flex: 382,
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: boardLayout.isNotEmpty
                    ? MiniBoard(
                        boardLayout: boardLayout,
                        extMove: widget.node.data,
                      )
                    : const SizedBox.shrink(),
              ),
            ),
            // Right: text.
            Expanded(
              flex: 618,
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      roundNotation + notation,
                      style: combinedStyle,
                      softWrap: true,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    _buildEditableComment(
                      TextStyle(
                        fontSize: 12,
                        color: DB().colorSettings.messageColor,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Small boards: grid cells with board on top, then "roundNotation + notation".
  Widget _buildSmallLayout(
    String notation,
    String boardLayout,
    String roundNotation,
    TextStyle combinedStyle,
  ) {
    return Padding(
      padding: const EdgeInsets.all(6.0),
      child: Container(
        color: DB().colorSettings.darkBackgroundColor,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            if (boardLayout.isNotEmpty)
              Expanded(
                child: AspectRatio(
                  aspectRatio: 1.0,
                  child: MiniBoard(
                    boardLayout: boardLayout,
                    extMove: widget.node.data,
                  ),
                ),
              )
            else
              const Expanded(child: SizedBox.shrink()),
            const SizedBox(height: 4),
            Text(
              roundNotation + notation,
              style: combinedStyle.copyWith(fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  /// Details layout: single row: "roundNotation + notation" on the left, comment on the right.
  Widget _buildDetailsLayout(
    String notation,
    String roundNotation,
    TextStyle combinedStyle,
  ) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Container(
        decoration: BoxDecoration(
          color: DB().colorSettings.darkBackgroundColor,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          children: <Widget>[
            // Left side.
            Expanded(
              child: Text(roundNotation + notation, style: combinedStyle),
            ),
            const SizedBox(width: 8),
            // Right side: editable comment.
            Expanded(
              child: _buildEditableComment(
                TextStyle(
                  fontSize: 12,
                  color: DB().colorSettings.messageColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void didUpdateWidget(covariant MoveListItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If not editing, sync comment if the node changed.
    if (!_isEditing) {
      final String newComment = _retrieveComment(widget.node);
      if (newComment != _comment) {
        setState(() {
          _comment = newComment;
          _editingController.text = newComment;
        });
      }
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _editingController.dispose();
    super.dispose();
  }
}
