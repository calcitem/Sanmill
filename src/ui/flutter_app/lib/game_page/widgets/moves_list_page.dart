// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// moves_list_page.dart

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

/// BranchGraphPage now displays PGN nodes in potentially different layouts.
/// The user can pick from a set of layout options via the "View" button.
class MovesListPage extends StatefulWidget {
  const MovesListPage({super.key});

  @override
  MovesListPageState createState() => MovesListPageState();
}

class MovesListPageState extends State<MovesListPage> {
  /// A flat list of all PGN nodes (collected recursively).
  final List<PgnNode<ExtMove>> _allNodes = <PgnNode<ExtMove>>[];

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
    _allNodes
      ..clear()
      ..addAll(GameController().gameRecorder.mainlineNodes);
  }

  /// Recursively walk the PGN tree and add each node to `_allNodes`.
  // void _collectAllNodes(PgnNode<ExtMove> node) {
  //   _allNodes.add(node);
  //   for (final PgnNode<ExtMove> child in node.children) {
  //     _collectAllNodes(child);
  //   }
  // }

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

  /// Builds a simple empty-state page with two large icons: Load game and Import game.
  Widget _buildEmptyState() {
    return Center(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          // Load Game
          InkWell(
            onTap: () async {
              await GameController.load(context, shouldPop: false);
              // Wait briefly, then refresh our list of nodes.
              await Future<void>.delayed(const Duration(milliseconds: 500));
              setState(() {
                _allNodes
                  ..clear()
                  ..addAll(GameController().gameRecorder.mainlineNodes);
              });
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  Icons.folder_open,
                  size: 64,
                  color: DB().colorSettings.messageColor,
                ),
                const SizedBox(height: 8),
                Text(
                  S.of(context).loadGame,
                  style: TextStyle(color: DB().colorSettings.messageColor),
                ),
              ],
            ),
          ),
          const SizedBox(width: 40),
          // Import Game
          InkWell(
            onTap: () async {
              await GameController.import(context, shouldPop: false);
              // Wait briefly, then refresh our list of nodes.
              await Future<void>.delayed(const Duration(milliseconds: 500));
              setState(() {
                _allNodes
                  ..clear()
                  ..addAll(GameController().gameRecorder.mainlineNodes);
              });
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  Icons.file_upload,
                  size: 64,
                  color: DB().colorSettings.messageColor,
                ),
                const SizedBox(height: 8),
                Text(
                  S.of(context).importGame,
                  style: TextStyle(color: DB().colorSettings.messageColor),
                ),
              ],
            ),
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
          // Reverse Order Icon (Moved to the left)
          IconButton(
            icon: const Icon(Icons.swap_vert),
            tooltip: 'Reverse Order',
            onPressed: () {
              setState(() {
                final List<PgnNode<ExtMove>> reversedNodes =
                    _allNodes.reversed.toList();
                _allNodes
                  ..clear()
                  ..addAll(reversedNodes);
              });
            },
          ),
          // "View" button to choose a layout.
          PopupMenuButton<MovesViewLayout>(
            icon: const Icon(Icons.view_list),
            // The "several horizontal lines" icon
            onSelected: (MovesViewLayout layout) {
              setState(() {
                _currentLayout = layout;
              });
            },
            itemBuilder: (BuildContext context) =>
                <PopupMenuEntry<MovesViewLayout>>[
              const PopupMenuItem<MovesViewLayout>(
                value: MovesViewLayout.large,
                child: Text('Large boards'),
              ),
              const PopupMenuItem<MovesViewLayout>(
                value: MovesViewLayout.medium,
                child: Text('Medium boards'),
              ),
              const PopupMenuItem<MovesViewLayout>(
                value: MovesViewLayout.small,
                child: Text('Small boards'),
              ),
              const PopupMenuItem<MovesViewLayout>(
                value: MovesViewLayout.list,
                child: Text('List'),
              ),
              const PopupMenuItem<MovesViewLayout>(
                value: MovesViewLayout.details,
                child: Text('Details'),
              ),
            ],
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
                  GameController.save(context, shouldPop: false);
                  break;
                case 'load_game':
                  await GameController.load(context, shouldPop: false);
                  await Future<void>.delayed(const Duration(milliseconds: 500));
                  setState(() {
                    _allNodes
                      ..clear()
                      ..addAll(GameController().gameRecorder.mainlineNodes);
                  });
                  break;
                case 'import_game':
                  await GameController.import(context, shouldPop: false);
                  await Future<void>.delayed(const Duration(milliseconds: 500));
                  setState(() {
                    _allNodes
                      ..clear()
                      ..addAll(GameController().gameRecorder.mainlineNodes);
                  });
                  break;
                case 'export_game':
                  GameController.export(context, shouldPop: false);
                  break;
              }
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              const PopupMenuItem<String>(
                value: 'top',
                child: Row(
                  children: <Widget>[
                    Icon(Icons.arrow_upward, color: Colors.black54),
                    SizedBox(width: 8),
                    Text('Scroll to Top'),
                  ],
                ),
              ),
              const PopupMenuItem<String>(
                value: 'bottom',
                child: Row(
                  children: <Widget>[
                    Icon(Icons.arrow_downward, color: Colors.black54),
                    SizedBox(width: 8),
                    Text('Scroll to Bottom'),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem<String>(
                value: 'save_game',
                child: Row(
                  children: <Widget>[
                    const Icon(Icons.save, color: Colors.black54),
                    const SizedBox(width: 8),
                    Text(S.of(context).saveGame),
                  ],
                ),
              ),
              PopupMenuItem<String>(
                value: 'load_game',
                child: Row(
                  children: <Widget>[
                    const Icon(Icons.folder_open, color: Colors.black54),
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
                    const Icon(Icons.file_upload, color: Colors.black54),
                    const SizedBox(width: 8),
                    Text(S.of(context).importGame),
                  ],
                ),
              ),
              PopupMenuItem<String>(
                value: 'export_game',
                child: Row(
                  children: <Widget>[
                    const Icon(Icons.file_download, color: Colors.black54),
                    const SizedBox(width: 8),
                    Text(S.of(context).exportGame),
                  ],
                ),
              ),
            ],
            icon: const Icon(Icons.more_vert),
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

  /// Builds the appropriate widget based on [widget.layout].
  @override
  Widget build(BuildContext context) {
    final ExtMove? moveData = widget.node.data;
    final String notation = moveData?.notation ?? "";
    final String boardLayout = moveData?.boardLayout ?? "";

    switch (widget.layout) {
      case MovesViewLayout.large:
        return _buildLargeLayout(notation, boardLayout);

      case MovesViewLayout.medium:
        return _buildMediumLayout(notation, boardLayout);

      case MovesViewLayout.small:
        return _buildSmallLayout(notation, boardLayout);

      case MovesViewLayout.list:
        return _buildListLayout(notation);

      case MovesViewLayout.details:
        return _buildDetailsLayout(notation);
    }
  }

  /// Large boards: single column, large board on top, then notation, then comment.
  Widget _buildLargeLayout(String notation, String boardLayout) {
    final bool hasComment = _comment.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Container(
        color: DB().colorSettings.darkBackgroundColor,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // Large board
            if (boardLayout.isNotEmpty)
              AspectRatio(
                aspectRatio: 1.0,
                child: MiniBoard(
                  boardLayout: boardLayout,
                  extMove: widget.node.data,
                ),
              ),
            const SizedBox(height: 8),
            // Notation
            Text(
              notation,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: DB().colorSettings.messageColor,
              ),
            ),
            const SizedBox(height: 6),
            // Comment area
            if (_isEditing)
              TextField(
                focusNode: _focusNode,
                controller: _editingController,
                style: TextStyle(
                  fontSize: 12,
                  fontStyle: FontStyle.normal,
                  color: DB().colorSettings.messageColor,
                ),
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
              )
            else
              GestureDetector(
                onTap: () {
                  setState(() {
                    _isEditing = true;
                    _editingController.text = hasComment ? _comment : "";
                  });
                },
                child: hasComment
                    ? Text(
                        _comment,
                        style: TextStyle(
                          fontSize: 12,
                          fontStyle: FontStyle.normal,
                          color: DB().colorSettings.messageColor,
                        ),
                      )
                    : Icon(
                        Icons.edit,
                        size: 16,
                        color: DB().colorSettings.messageColor.withAlpha(120),
                      ),
              ),
          ],
        ),
      ),
    );
  }

  /// Medium boards (the original layout): board on the left, notation & comment on the right.
  Widget _buildMediumLayout(String notation, String boardLayout) {
    final bool hasComment = _comment.isNotEmpty;
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
                        color: DB().colorSettings.messageColor,
                      ),
                      softWrap: true,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    if (_isEditing)
                      TextField(
                        focusNode: _focusNode,
                        controller: _editingController,
                        style: TextStyle(
                          fontSize: 12,
                          color: DB().colorSettings.messageColor,
                        ),
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
                      )
                    else
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            _isEditing = true;
                            _editingController.text =
                                hasComment ? _comment : "";
                          });
                        },
                        child: hasComment
                            ? Text(
                                _comment,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: DB().colorSettings.messageColor,
                                ),
                                softWrap: true,
                              )
                            : Icon(
                                Icons.edit,
                                size: 16,
                                color: DB()
                                    .colorSettings
                                    .messageColor
                                    .withAlpha(120),
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
  Widget _buildSmallLayout(String notation, String boardLayout) {
    return Padding(
      padding: const EdgeInsets.all(6.0),
      child: Container(
        color: DB().colorSettings.darkBackgroundColor,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            if (boardLayout.isNotEmpty)
              Expanded(
                // Keep it square-ish:
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
                color: DB().colorSettings.messageColor,
              ),
              textAlign: TextAlign.center,
            ),
            // No comment displayed in Small layout.
          ],
        ),
      ),
    );
  }

  /// List layout: 2 columns, show notation only (no board, no comment).
  Widget _buildListLayout(String notation) {
    return Card(
      color: DB().colorSettings.darkBackgroundColor,
      margin: const EdgeInsets.all(6.0),
      child: Center(
        child: Text(
          notation,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: DB().colorSettings.messageColor,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  /// Details layout: single column, each row has notation on the left, comment on the right, no board.
  Widget _buildDetailsLayout(String notation) {
    final bool hasComment = _comment.isNotEmpty;
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
                  color: DB().colorSettings.messageColor,
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Comment (editable) on the right
            Expanded(
              child: _isEditing
                  ? TextField(
                      focusNode: _focusNode,
                      controller: _editingController,
                      style: TextStyle(
                        fontSize: 12,
                        color: DB().colorSettings.messageColor,
                      ),
                      keyboardType: TextInputType.multiline,
                      decoration: const InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                      ),
                      onEditingComplete: () {
                        _finalizeEditing();
                        FocusScope.of(context).unfocus();
                      },
                    )
                  : GestureDetector(
                      onTap: () {
                        setState(() {
                          _isEditing = true;
                          _editingController.text = hasComment ? _comment : "";
                        });
                      },
                      child: hasComment
                          ? Text(
                              _comment,
                              style: TextStyle(
                                fontSize: 12,
                                color: DB().colorSettings.messageColor,
                              ),
                            )
                          : Icon(
                              Icons.edit,
                              size: 16,
                              color: DB()
                                  .colorSettings
                                  .messageColor
                                  .withAlpha(120),
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
