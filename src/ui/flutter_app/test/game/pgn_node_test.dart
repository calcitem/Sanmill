// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// pgn_node_test.dart
//
// Tests for PgnNode tree structure, PgnNodeData, and PgnGame.

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_page/services/import_export/pgn.dart';

void main() {
  // ---------------------------------------------------------------------------
  // PgnNodeData
  // ---------------------------------------------------------------------------
  group('PgnNodeData', () {
    test('should store SAN move notation', () {
      final PgnNodeData data = PgnNodeData(san: 'd6');
      expect(data.san, 'd6');
    });

    test('should allow comments', () {
      final PgnNodeData data = PgnNodeData(
        san: 'a1',
        comments: <String>['Good move!'],
        startingComments: <String>['Opening line'],
      );

      expect(data.comments, <String>['Good move!']);
      expect(data.startingComments, <String>['Opening line']);
    });

    test('should allow NAGs', () {
      final PgnNodeData data = PgnNodeData(
        san: 'd5-e5',
        nags: <int>[1, 3], // ! and !!
      );

      expect(data.nags, <int>[1, 3]);
    });

    test('optional fields should default to null', () {
      final PgnNodeData data = PgnNodeData(san: 'xa7');

      expect(data.comments, isNull);
      expect(data.startingComments, isNull);
      expect(data.nags, isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // PgnNode tree structure
  // ---------------------------------------------------------------------------
  group('PgnNode', () {
    test('root node should have null data', () {
      final PgnNode<PgnNodeData> root = PgnNode<PgnNodeData>();

      expect(root.data, isNull);
      expect(root.children, isEmpty);
      expect(root.parent, isNull);
    });

    test('node with data should store it', () {
      final PgnNode<PgnNodeData> node = PgnNode<PgnNodeData>(
        PgnNodeData(san: 'd6'),
      );

      expect(node.data, isNotNull);
      expect(node.data!.san, 'd6');
    });

    test('adding children should build tree structure', () {
      final PgnNode<PgnNodeData> root = PgnNode<PgnNodeData>();
      final PgnNode<PgnNodeData> child1 = PgnNode<PgnNodeData>(
        PgnNodeData(san: 'd6'),
      );
      final PgnNode<PgnNodeData> child2 = PgnNode<PgnNodeData>(
        PgnNodeData(san: 'f4'),
      );

      root.children.add(child1);
      child1.parent = root;
      root.children.add(child2);
      child2.parent = root;

      expect(root.children.length, 2);
      expect(root.children[0].data!.san, 'd6');
      expect(root.children[1].data!.san, 'f4');
    });

    test('parent-child references should be consistent', () {
      final PgnNode<PgnNodeData> root = PgnNode<PgnNodeData>();
      final PgnNode<PgnNodeData> child = PgnNode<PgnNodeData>(
        PgnNodeData(san: 'a1'),
      );

      root.children.add(child);
      child.parent = root;

      expect(child.parent, same(root));
      expect(root.children.first, same(child));
    });

    test('mainline should follow first child chain', () {
      final PgnNode<PgnNodeData> root = PgnNode<PgnNodeData>();

      // Build mainline: d6 → f4 → b4
      final PgnNode<PgnNodeData> move1 = PgnNode<PgnNodeData>(
        PgnNodeData(san: 'd6'),
      );
      final PgnNode<PgnNodeData> move2 = PgnNode<PgnNodeData>(
        PgnNodeData(san: 'f4'),
      );
      final PgnNode<PgnNodeData> move3 = PgnNode<PgnNodeData>(
        PgnNodeData(san: 'b4'),
      );

      root.children.add(move1);
      move1.parent = root;
      move1.children.add(move2);
      move2.parent = move1;
      move2.children.add(move3);
      move3.parent = move2;

      final List<PgnNodeData> mainline = root.mainline().toList();

      expect(mainline.length, 3);
      expect(mainline[0].san, 'd6');
      expect(mainline[1].san, 'f4');
      expect(mainline[2].san, 'b4');
    });

    test('mainline of empty root should be empty', () {
      final PgnNode<PgnNodeData> root = PgnNode<PgnNodeData>();

      expect(root.mainline().toList(), isEmpty);
    });

    test('variations should be children beyond index 0', () {
      final PgnNode<PgnNodeData> root = PgnNode<PgnNodeData>();
      final PgnNode<PgnNodeData> mainMove = PgnNode<PgnNodeData>(
        PgnNodeData(san: 'd6'),
      );
      final PgnNode<PgnNodeData> variation = PgnNode<PgnNodeData>(
        PgnNodeData(san: 'f4'),
      );

      root.children.add(mainMove);
      mainMove.parent = root;
      root.children.add(variation);
      variation.parent = root;

      // Mainline should only follow first child
      final List<PgnNodeData> mainline = root.mainline().toList();
      expect(mainline.length, 1);
      expect(mainline[0].san, 'd6');

      // But both children are accessible
      expect(root.children.length, 2);
      expect(root.children[1].data!.san, 'f4');
    });
  });

  // ---------------------------------------------------------------------------
  // PgnGame
  // ---------------------------------------------------------------------------
  group('PgnGame', () {
    test('defaultHeaders should have seven mandatory tag pairs', () {
      final PgnHeaders headers = PgnGame.defaultHeaders();

      expect(headers.containsKey('Event'), isTrue);
      expect(headers.containsKey('Site'), isTrue);
      expect(headers.containsKey('Date'), isTrue);
      expect(headers.containsKey('Round'), isTrue);
      expect(headers.containsKey('White'), isTrue);
      expect(headers.containsKey('Black'), isTrue);
      expect(headers.containsKey('Result'), isTrue);
    });

    test('defaultHeaders Result should be "*"', () {
      final PgnHeaders headers = PgnGame.defaultHeaders();
      expect(headers['Result'], '*');
    });

    test('defaultHeaders should use "?" for unknown fields', () {
      final PgnHeaders headers = PgnGame.defaultHeaders();
      expect(headers['Event'], '?');
      expect(headers['Site'], '?');
      expect(headers['Round'], '?');
      expect(headers['White'], '?');
      expect(headers['Black'], '?');
    });

    test('should construct with headers, moves, and comments', () {
      final PgnGame<PgnNodeData> game = PgnGame<PgnNodeData>(
        headers: PgnGame.defaultHeaders(),
        moves: PgnNode<PgnNodeData>(),
        comments: <String>['Test game'],
      );

      expect(game.headers, isNotEmpty);
      expect(game.moves, isNotNull);
      expect(game.comments, <String>['Test game']);
    });
  });

  // ---------------------------------------------------------------------------
  // Deep tree operations
  // ---------------------------------------------------------------------------
  group('PgnNode deep tree', () {
    test('should handle deep mainline (20 moves)', () {
      final PgnNode<PgnNodeData> root = PgnNode<PgnNodeData>();
      PgnNode<PgnNodeData> current = root;

      for (int i = 0; i < 20; i++) {
        final PgnNode<PgnNodeData> child = PgnNode<PgnNodeData>(
          PgnNodeData(san: 'move$i'),
        );
        current.children.add(child);
        child.parent = current;
        current = child;
      }

      final List<PgnNodeData> mainline = root.mainline().toList();
      expect(mainline.length, 20);
      expect(mainline.first.san, 'move0');
      expect(mainline.last.san, 'move19');
    });

    test('should handle tree with multiple branches', () {
      final PgnNode<PgnNodeData> root = PgnNode<PgnNodeData>();

      // Main line: A → B → C
      final PgnNode<PgnNodeData> a = PgnNode<PgnNodeData>(
        PgnNodeData(san: 'A'),
      );
      final PgnNode<PgnNodeData> b = PgnNode<PgnNodeData>(
        PgnNodeData(san: 'B'),
      );
      final PgnNode<PgnNodeData> c = PgnNode<PgnNodeData>(
        PgnNodeData(san: 'C'),
      );

      root.children.add(a);
      a.parent = root;
      a.children.add(b);
      b.parent = a;
      b.children.add(c);
      c.parent = b;

      // Variation at A: A → D → E
      final PgnNode<PgnNodeData> d = PgnNode<PgnNodeData>(
        PgnNodeData(san: 'D'),
      );
      final PgnNode<PgnNodeData> e = PgnNode<PgnNodeData>(
        PgnNodeData(san: 'E'),
      );
      a.children.add(d);
      d.parent = a;
      d.children.add(e);
      e.parent = d;

      // Mainline should follow A → B → C
      final List<PgnNodeData> mainline = root.mainline().toList();
      expect(mainline.map((PgnNodeData d) => d.san).toList(),
          <String>['A', 'B', 'C']);

      // Variation branch should be accessible
      expect(a.children.length, 2);
      expect(a.children[1].data!.san, 'D');
    });
  });
}
