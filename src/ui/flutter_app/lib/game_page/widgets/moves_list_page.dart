// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// branch_graph_page.dart

import 'package:flutter/material.dart';

import '../../shared/database/database.dart';
import '../services/import_export/pgn.dart';
import '../services/mill.dart';
import 'mini_board.dart';

/// BranchGraphPage now displays PGN nodes in a vertical list.
/// Each list item shows:
/// - A left section (~38.2% width) for a small Nine Men's Morris board
/// - A right section (~61.8% width) for notation (top) and comment (bottom)
class MovesListPage extends StatefulWidget {
  const MovesListPage({super.key});

  @override
  MovesListPageState createState() => MovesListPageState();
}

class MovesListPageState extends State<MovesListPage> {
  /// A flat list of all PGN nodes (collected recursively).
  final List<PgnNode<ExtMove>> _allNodes = <PgnNode<ExtMove>>[];

  @override
  void initState() {
    super.initState();
    // Collect all nodes from the PGN tree into _allNodes.
    final PgnNode<ExtMove> root = GameController().gameRecorder.pgnRoot;
    _collectAllNodes(root);
  }

  /// Recursively walk the PGN tree and add each node to `_allNodes`.
  void _collectAllNodes(PgnNode<ExtMove> node) {
    _allNodes.add(node);
    // Note: Should use node.children.forEach(_collectAllNodes);
    node.children.forEach(_collectAllNodes);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Branch Graph"),
      ),
      body: ListView.builder(
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
    // Retrieve notation, comment, board layout from node.data
    final ExtMove? moveData = node.data;
    final String notation = moveData?.notation ?? "";
    final String boardLayout = moveData?.boardLayout ?? "";

    // Retrieve comment
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
            /// Left side: ~38.2% for the board
            Expanded(
              flex: 382, // 38.2%
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: boardLayout.isNotEmpty
                    ? MiniBoard(boardLayout: boardLayout)
                    : const SizedBox.shrink(),
              ),
            ),

            /// Right side: ~61.8% for notation + comment
            Expanded(
              flex: 618, // 61.8%
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    // Notation at the top
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

                    // Comment at the bottom
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
