// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// branch_graph_page.dart

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
    //final PgnNode<ExtMove> root = GameController().gameRecorder.pgnRoot;
    //_collectAllNodes(root);
    _allNodes
      ..clear()
      ..addAll(GameController().gameRecorder.mainlineNodes);
  }

  /// Recursively walk the PGN tree and add each node to `_allNodes`.
  //void _collectAllNodes(PgnNode<ExtMove> node) {
  //  _allNodes.add(node);
  //  node.children.forEach(_collectAllNodes);
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
    // Wait for the next frame to ensure that the list's maxScrollExtent is updated.
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
            onSelected: (String value) {
              // Handle scroll action based on menu selection.
              switch (value) {
                case 'top':
                  _scrollToTop();
                  break;
                case 'bottom':
                  _scrollToBottom();
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

/// _NodeListItem displays a single PGN node in a row:
/// Left side (38.2% of width): small Nine Men's Morris board.
/// Right side (61.8% of width): notation (top) and comment (bottom).
class _NodeListItem extends StatelessWidget {
  const _NodeListItem({required this.node});

  final PgnNode<ExtMove> node;

  @override
  Widget build(BuildContext context) {
    // Retrieve notation, comment, and board layout from node.data.
    final ExtMove? moveData = node.data;
    final String notation = moveData?.notation ?? "";
    final String boardLayout = moveData?.boardLayout ?? "";

    // Retrieve comment from either 'comments' or 'startingComments'.
    String comment = "";
    if (moveData?.comments != null && moveData!.comments!.isNotEmpty) {
      comment = moveData.comments!.join(" ");
    } else if (moveData?.startingComments != null &&
        moveData!.startingComments!.isNotEmpty) {
      comment = moveData.startingComments!.join(" ");
    }

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
            /// Left side: ~38.2% for the board.
            Expanded(
              flex: 382, // 38.2%
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

            /// Right side: ~61.8% for notation and comment.
            Expanded(
              flex: 618, // 61.8%
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

                    // Comment at the bottom.
                    Text(
                      comment.isEmpty ? "No comment" : comment,
                      style: TextStyle(
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                        color: DB().colorSettings.messageColor,
                      ),
                      softWrap: true,
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
}
