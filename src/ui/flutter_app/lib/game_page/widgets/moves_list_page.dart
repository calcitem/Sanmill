// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// moves_list_page.dart

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../../generated/intl/l10n.dart';
import '../../shared/database/database.dart';
import '../../shared/themes/app_theme.dart';
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

/// MovesListPage now displays PGN nodes in potentially different layouts.
/// The user can pick from a set of layout options via a single active icon which,
/// when tapped, reveals a horizontal row of layout icons.
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

    int currentMoveIndex = 0; // Initialize moveIndex for the first node

    for (int i = 0; i < _allNodes.length; i++) {
      final PgnNode<ExtMove> node = _allNodes[i];

      if (i == 0) {
        // First node always gets moveIndex 0
        node.data?.moveIndex = currentMoveIndex;
      } else if (node.data?.type == MoveType.remove) {
        // TODO: WAR: If it's a remove type, use the previous node's moveIndex
        node.data?.moveIndex = _allNodes[i - 1].data?.moveIndex;
      } else {
        // Otherwise, increment the previous node's moveIndex
        currentMoveIndex = (_allNodes[i - 1].data?.moveIndex ?? 0) + 1;
        node.data?.moveIndex = currentMoveIndex;
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

  /// Builds the main body widget according to the chosen view layout.
  Widget _buildBody() {
    if (_allNodes.isEmpty) {
      // If there are no moves, show two large icons: Load and Import.
      return _buildEmptyState();
    }

    switch (_currentLayout) {
      case MovesViewLayout.large:
      case MovesViewLayout.medium:
      case MovesViewLayout.details:
        // For these three, use a single-column ListView.
        return ListView.builder(
          controller: _scrollController,
          itemCount: _allNodes.length,
          itemBuilder: (BuildContext context, int index) {
            final PgnNode<ExtMove> node = _allNodes[index];
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
            childAspectRatio: 0.9, // Adjust as desired
          ),
          itemCount: _allNodes.length,
          itemBuilder: (BuildContext context, int index) {
            return MoveListItem(
              node: _allNodes[index],
              layout: _currentLayout,
            );
          },
        );

      case MovesViewLayout.list:
        // For list layout, 2 columns, notation only.
        return GridView.builder(
          controller: _scrollController,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            childAspectRatio: 4.0, // Tweak for desired spacing
          ),
          itemCount: _allNodes.length,
          itemBuilder: (BuildContext context, int index) {
            return MoveListItem(
              node: _allNodes[index],
              layout: _currentLayout,
            );
          },
        );
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
          // Reverse Order Icon
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
                _isReversedOrder = !_isReversedOrder;
                final List<PgnNode<ExtMove>> reversedNodes =
                    _allNodes.reversed.toList();
                _allNodes
                  ..clear()
                  ..addAll(reversedNodes);
              });
            },
          ),
          // Layout selection: one active icon in the AppBar.
          // Tapping it opens a popup with a horizontal row of icons.
          PopupMenuButton<void>(
            icon: Icon(_iconForLayout(_currentLayout)),
            color: DB().colorSettings.mainToolbarBackgroundColor,
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
                          color: isSelected
                              ? DB()
                                  .colorSettings
                                  .mainToolbarIconColor
                                  .withValues(alpha: 1)
                              : DB()
                                  .colorSettings
                                  .mainToolbarIconColor
                                  .withValues(alpha: 0.8),
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
          // The existing "three vertical dots" menu.
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
            ],
            icon: const Icon(FluentIcons.more_vertical_24_regular),
          ),
        ],
      ),
      body: _buildBody(),
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

  /// Retrieve comment from node.data, joined if multiple.
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

    // If side is white, use white color; if black, use black color.
    final Color sideColor = (moveData?.side == PieceColor.white)
        ? DB().colorSettings.whitePieceColor
        : (moveData?.side == PieceColor.black)
            ? DB().colorSettings.blackPieceColor
            : Colors.yellow;

    switch (widget.layout) {
      case MovesViewLayout.large:
        return _buildLargeLayout(notation, boardLayout, sideColor);
      case MovesViewLayout.medium:
        return _buildMediumLayout(notation, boardLayout, sideColor);
      case MovesViewLayout.small:
        return _buildSmallLayout(notation, boardLayout, sideColor);
      case MovesViewLayout.list:
        return _buildListLayout(notation, sideColor);
      case MovesViewLayout.details:
        return _buildDetailsLayout(notation, sideColor);
    }
  }

  /// Large boards: single column, large board on top, then notation, then comment.
  Widget _buildLargeLayout(
      String notation, String boardLayout, Color sideColor) {
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
            Text(
              notation,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color:
                    sideColor, // If side is white, text is white; if side is black, text is black.
              ),
            ),
            const SizedBox(height: 6),
            _buildEditableComment(
              TextStyle(
                fontSize: 12,
                fontStyle: FontStyle.normal,
                color: DB().colorSettings.messageColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Medium boards: board on the left, notation & comment on the right.
  Widget _buildMediumLayout(
      String notation, String boardLayout, Color sideColor) {
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
            // Left side: mini board
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
            // Right side: notation and comment
            Expanded(
              flex: 618,
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      notation,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color:
                            sideColor, // If side is white => white, black => black
                      ),
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

  /// Small boards: grid with 3 or 5 columns, each cell has mini board on top, notation below, no comment.
  Widget _buildSmallLayout(
      String notation, String boardLayout, Color sideColor) {
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
              notation,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color:
                    sideColor, // If side is white => white, if black => black
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  /// List layout: 2 columns, show notation only (no board, no comment).
  Widget _buildListLayout(String notation, Color sideColor) {
    return Card(
      color: DB().colorSettings.darkBackgroundColor,
      margin: const EdgeInsets.all(6.0),
      child: Center(
        child: Text(
          notation,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: sideColor, // If side is white => white, if black => black
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  /// Details layout: single row, notation on the left, comment on the right, no board.
  Widget _buildDetailsLayout(String notation, Color sideColor) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Container(
        decoration: BoxDecoration(
          color: DB().colorSettings.darkBackgroundColor,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          children: <Widget>[
            // Notation on the left
            Expanded(
              child: Text(
                notation,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color:
                      sideColor, // If side is white => white, if black => black
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Editable comment on the right
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
    // If not editing, update comment if it has changed in the node.
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
