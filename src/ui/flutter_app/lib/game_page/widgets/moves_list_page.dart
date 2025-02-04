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

/// BranchGraphPage now displays PGN nodes in a vertical list.
/// Each list item shows:
/// - A left section (~38.2% width) for a small Nine Men's Morris board.
/// - A right section (~61.8% width) for notation (top) and comment (bottom).
class MovesListPage extends StatefulWidget {
  const MovesListPage({super.key});

  @override
  MovesListPageState createState() => MovesListPageState();
}

class MovesListPageState extends State<MovesListPage> {
  /// A flat list of all PGN nodes (collected recursively).
  final List<PgnNode<ExtMove>> _allNodes = <PgnNode<ExtMove>>[];

  /// ScrollController to control the scrolling of the ListView.
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // Collect all nodes from the PGN tree into _allNodes.
    // Example:
    // final PgnNode<ExtMove> root = GameController().gameRecorder.pgnRoot;
    // _collectAllNodes(root);
    _allNodes
      ..clear()
      ..addAll(GameController().gameRecorder.mainlineNodes);
  }

  /// Recursively walk the PGN tree and add each node to `_allNodes`.
  //void _collectAllNodes(PgnNode<ExtMove> node) {
  //  _allNodes.add(node);
  //  for (final PgnNode<ExtMove> child in node.children) {
  //   _collectAllNodes(child);
  //  }
  //}

  /// Scrolls the list to the top with an animation.
  void _scrollToTop() {
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  /// Scrolls the list to the bottom with an animation.
  void _scrollToBottom() {
    // Wait for the next frame to ensure the list's maxScrollExtent is correct.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          S.of(context).moveList,
          style: AppTheme.appBarTheme.titleTextStyle,
        ),
        actions: <Widget>[
          PopupMenuButton<String>(
            onSelected: (String value) async {
              // Handle actions based on menu selection.
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
                  // Refresh the list with new data.
                  setState(() {
                    _allNodes
                      ..clear()
                      ..addAll(GameController().gameRecorder.mainlineNodes);
                  });
                  break;
                case 'import_game':
                  await GameController.import(context, shouldPop: false);
                  await Future<void>.delayed(const Duration(milliseconds: 500));
                  // Refresh the list with new data.
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
              // Group 1: Scroll options
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
              // Divider between scroll and game management options
              const PopupMenuDivider(),
              // Group 2: Save and Load game options
              const PopupMenuItem<String>(
                value: 'save_game',
                child: Row(
                  children: <Widget>[
                    Icon(Icons.save, color: Colors.black54),
                    SizedBox(width: 8),
                    Text('Save game'),
                  ],
                ),
              ),
              const PopupMenuItem<String>(
                value: 'load_game',
                child: Row(
                  children: <Widget>[
                    Icon(Icons.folder_open, color: Colors.black54),
                    SizedBox(width: 8),
                    Text('Load game'),
                  ],
                ),
              ),
              // Divider between Save/Load and Import/Export options
              const PopupMenuDivider(),
              // Group 3: Import and Export game options
              const PopupMenuItem<String>(
                value: 'import_game',
                child: Row(
                  children: <Widget>[
                    Icon(Icons.file_upload, color: Colors.black54),
                    SizedBox(width: 8),
                    Text('Import game'),
                  ],
                ),
              ),
              const PopupMenuItem<String>(
                value: 'export_game',
                child: Row(
                  children: <Widget>[
                    Icon(Icons.file_download, color: Colors.black54),
                    SizedBox(width: 8),
                    Text('Export game'),
                  ],
                ),
              ),
            ],
            icon: const Icon(Icons.more_vert), // Three vertical dots icon.
          ),
        ],
      ),
      body: ListView.builder(
        controller: _scrollController,
        itemCount: _allNodes.length,
        itemBuilder: (BuildContext context, int index) {
          final PgnNode<ExtMove> node = _allNodes[index];
          return _NodeListItem(node: node);
        },
      ),
    );
  }
}

/// _NodeListItem now supports editing the comment field in-place,
/// similar to how the HeaderTip widget handles comment editing.
class _NodeListItem extends StatefulWidget {
  const _NodeListItem({required this.node});

  final PgnNode<ExtMove> node;

  @override
  _NodeListItemState createState() => _NodeListItemState();
}

class _NodeListItemState extends State<_NodeListItem> {
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

    // Extract the comment from node.data.
    _comment = _retrieveComment(widget.node);

    _editingController = TextEditingController(text: _comment);
  }

  /// Retrieve comment from node.data, joined if multiple.
  String _retrieveComment(PgnNode<ExtMove> node) {
    if (node.data?.comments != null && node.data!.comments!.isNotEmpty) {
      return node.data!.comments!.join(" ");
    } else if (node.data?.startingComments != null &&
        node.data!.startingComments!.isNotEmpty) {
      return node.data!.startingComments!.join(" ");
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

      // Store the final text from _editingController.
      final String newComment = _editingController.text.trim();
      _comment = newComment.isEmpty ? "No comment" : newComment;

      // Replace or set node.data.comments with unbraced text.
      widget.node.data?.comments ??= <String>[];
      widget.node.data?.comments!.clear();
      if (newComment.isNotEmpty && newComment != "No comment") {
        widget.node.data?.comments!.add(newComment);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Retrieve notation, boardLayout, etc.
    final ExtMove? moveData = widget.node.data;
    final String notation = moveData?.notation ?? "";
    final String boardLayout = moveData?.boardLayout ?? "";

    // Determine the text to display for the comment.
    final String displayComment = _comment.isEmpty ? "No comment" : _comment;
    // If the comment is "No comment", display it semi-transparent.
    final bool isNoComment = displayComment == "No comment";

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
            // Left side: ~38.2% for the board.
            Expanded(
              flex: 382,
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: boardLayout.isNotEmpty
                    ? MiniBoard(
                        boardLayout: boardLayout,
                        extMove: moveData,
                      )
                    : const SizedBox.shrink(),
              ),
            ),

            // Right side: ~61.8% for notation and comment.
            Expanded(
              flex: 618,
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    // Notation at the top.
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

                    // Comment at the bottom (tap to edit).
                    GestureDetector(
                      onTap: () {
                        if (!_isEditing) {
                          setState(() {
                            _isEditing = true;
                            // Restore text in the editor.
                            _editingController.text =
                                (displayComment == "No comment")
                                    ? ""
                                    : displayComment;
                          });
                        }
                      },
                      child: _isEditing
                          ? TextField(
                              focusNode: _focusNode,
                              controller: _editingController,
                              style: TextStyle(
                                fontSize: 12,
                                fontStyle: FontStyle.normal,
                                color: DB().colorSettings.messageColor,
                              ),
                              decoration: const InputDecoration(
                                isDense: true,
                                contentPadding: EdgeInsets.zero,
                                border: InputBorder.none,
                              ),
                              onEditingComplete: () {
                                // Finalize editing and hide keyboard.
                                _finalizeEditing();
                                FocusScope.of(context).unfocus();
                              },
                            )
                          : Text(
                              displayComment,
                              style: TextStyle(
                                fontSize: 12,
                                fontStyle: FontStyle.normal,
                                // Use semi-transparent color if "No comment", otherwise default color.
                                color: isNoComment
                                    ? DB()
                                        .colorSettings
                                        .messageColor
                                        .withValues(alpha: 0.5)
                                    : DB().colorSettings.messageColor,
                              ),
                              softWrap: true,
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

  @override
  void dispose() {
    _focusNode.dispose();
    _editingController.dispose();
    super.dispose();
  }
}
