// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_page/services/import_export/pgn.dart';

void main() {
  group('PGN comment parsing', () {
    test('Parses clock annotation [%clk]', () {
      const String comment = '[%clk 1:23:45.123]';
      final PgnComment parsed = PgnComment.fromPgn(comment);

      expect(
        parsed.clock,
        const Duration(hours: 1, minutes: 23, seconds: 45, milliseconds: 123),
      );
    });

    test('Parses elapsed move time [%emt]', () {
      const String comment = '[%emt 0:00:05.500]';
      final PgnComment parsed = PgnComment.fromPgn(comment);

      expect(
        parsed.emt,
        const Duration(seconds: 5, milliseconds: 500),
      );
    });

    test('Parses evaluation with pawns [%eval]', () {
      const String posEval = '[%eval 1.25,10]';
      const String negEval = '[%eval -0.75,5]';

      final PgnComment parsed1 = PgnComment.fromPgn(posEval);
      expect(parsed1.eval?.isPawns(), isTrue);
      expect(parsed1.eval?.pawns, 1.25);
      expect(parsed1.eval?.depth, 10);

      final PgnComment parsed2 = PgnComment.fromPgn(negEval);
      expect(parsed2.eval?.pawns, -0.75);
      expect(parsed2.eval?.depth, 5);
    });

    test('Parses evaluation with mate [%eval]', () {
      const String matePos = '[%eval #5,12]';
      const String mateNeg = '[%eval #-3,8]';

      final PgnComment parsed1 = PgnComment.fromPgn(matePos);
      expect(parsed1.eval?.isPawns(), isFalse);
      expect(parsed1.eval?.mate, 5);
      expect(parsed1.eval?.depth, 12);

      final PgnComment parsed2 = PgnComment.fromPgn(mateNeg);
      expect(parsed2.eval?.mate, -3);
      expect(parsed2.eval?.depth, 8);
    });

    test('Parses circle shapes [%csl]', () {
      const String comment = '[%csl Gd6,Rf4,Yb2]';
      final PgnComment parsed = PgnComment.fromPgn(comment);

      expect(parsed.shapes.length, 3);
      expect(parsed.shapes[0].color, CommentShapeColor.green);
      expect(parsed.shapes[0].from.name, 'd6');
      expect(parsed.shapes[0].to.name, 'd6'); // Circle: from == to

      expect(parsed.shapes[1].color, CommentShapeColor.red);
      expect(parsed.shapes[1].from.name, 'f4');

      expect(parsed.shapes[2].color, CommentShapeColor.yellow);
      expect(parsed.shapes[2].from.name, 'b2');
    });

    test('Parses arrow shapes [%cal]', () {
      const String comment = '[%cal Rd6f4,Ga1d7]';
      final PgnComment parsed = PgnComment.fromPgn(comment);

      expect(parsed.shapes.length, 2);
      expect(parsed.shapes[0].color, CommentShapeColor.red);
      expect(parsed.shapes[0].from.name, 'd6');
      expect(parsed.shapes[0].to.name, 'f4'); // Arrow: from != to

      expect(parsed.shapes[1].color, CommentShapeColor.green);
      expect(parsed.shapes[1].from.name, 'a1');
      expect(parsed.shapes[1].to.name, 'd7');
    });

    test('Parses mixed shapes (circles and arrows)', () {
      const String comment = '[%csl Gd6] [%cal Rd6f4,Bb2d2]';
      final PgnComment parsed = PgnComment.fromPgn(comment);

      expect(parsed.shapes.length, 3);
      expect(parsed.shapes[0].from.name, 'd6'); // Circle
      expect(parsed.shapes[0].to.name, 'd6');
      expect(parsed.shapes[1].from.name, 'd6'); // Arrow
      expect(parsed.shapes[1].to.name, 'f4');
      expect(parsed.shapes[2].color, CommentShapeColor.blue);
    });

    test('Parses comment with all annotation types', () {
      const String fullComment =
          'Strategic move [%clk 0:05:30] [%emt 0:00:03.250] '
          '[%eval 0.42,15] [%csl Gd6] [%cal Rd6f4]';

      final PgnComment parsed = PgnComment.fromPgn(fullComment);

      expect(parsed.text, 'Strategic move');
      expect(parsed.clock, isNotNull);
      expect(parsed.emt, isNotNull);
      expect(parsed.eval, isNotNull);
      expect(parsed.shapes.length, 2);
    });

    test('makeComment reconstructs annotation string', () {
      final PgnComment comment = PgnComment(
        text: 'Test',
        clock: const Duration(minutes: 5, seconds: 30),
        emt: const Duration(seconds: 2),
        eval: const PgnEvaluation.pawns(pawns: 0.5, depth: 10),
        shapes: IList<PgnCommentShape>(const <PgnCommentShape>[
          PgnCommentShape(
            color: CommentShapeColor.green,
            from: Square('d6'),
            to: Square('d6'),
          ),
        ]),
      );

      final String reconstructed = comment.makeComment();

      expect(reconstructed, contains('Test'));
      expect(reconstructed, contains('%clk'));
      expect(reconstructed, contains('%emt'));
      expect(reconstructed, contains('%eval'));
      expect(reconstructed, contains('%csl'));
    });

    test('Handles empty comment text with annotations', () {
      const String comment = '[%eval 1.0]';
      final PgnComment parsed = PgnComment.fromPgn(comment);

      expect(parsed.text, isNull); // No text, only annotation
      expect(parsed.eval, isNotNull);
    });

    test('Strips annotations from text correctly', () {
      const String comment = 'Before [%clk 0:01:00] middle [%eval 0.5] after';
      final PgnComment parsed = PgnComment.fromPgn(comment);

      // Text should have annotations stripped but preserve spacing
      expect(parsed.text, contains('Before'));
      expect(parsed.text, contains('middle'));
      expect(parsed.text, contains('after'));
      expect(parsed.text, isNot(contains('%clk')));
      expect(parsed.text, isNot(contains('%eval')));
    });

    test('PgnCommentShape equality works correctly', () {
      const PgnCommentShape shape1 = PgnCommentShape(
        color: CommentShapeColor.green,
        from: Square('d6'),
        to: Square('f4'),
      );
      const PgnCommentShape shape2 = PgnCommentShape(
        color: CommentShapeColor.green,
        from: Square('d6'),
        to: Square('f4'),
      );
      const PgnCommentShape shape3 = PgnCommentShape(
        color: CommentShapeColor.red,
        from: Square('d6'),
        to: Square('f4'),
      );

      expect(shape1, equals(shape2));
      expect(shape1, isNot(equals(shape3)));
    });

    test('PgnEvaluation equality works correctly', () {
      const PgnEvaluation eval1 =
          PgnEvaluation.pawns(pawns: 0.5, depth: 10);
      const PgnEvaluation eval2 =
          PgnEvaluation.pawns(pawns: 0.5, depth: 10);
      const PgnEvaluation eval3 =
          PgnEvaluation.pawns(pawns: 1.0, depth: 10);

      expect(eval1, equals(eval2));
      expect(eval1, isNot(equals(eval3)));
    });

    test('PgnComment equality works correctly', () {
      const PgnComment comment1 = PgnComment(
        text: 'Test',
        eval: PgnEvaluation.pawns(pawns: 0.5),
      );
      const PgnComment comment2 = PgnComment(
        text: 'Test',
        eval: PgnEvaluation.pawns(pawns: 0.5),
      );
      const PgnComment comment3 = PgnComment(
        text: 'Different',
        eval: PgnEvaluation.pawns(pawns: 0.5),
      );

      expect(comment1, equals(comment2));
      expect(comment1, isNot(equals(comment3)));
    });

    test('Square parsing validates coordinates', () {
      // Valid squares
      expect(Square.parse('a1'), isNotNull);
      expect(Square.parse('g7'), isNotNull);
      expect(Square.parse('d4'), isNotNull);

      // Invalid squares
      expect(Square.parse('h8'), isNull); // Out of range
      expect(Square.parse('a8'), isNull); // Invalid rank
      expect(Square.parse('z1'), isNull); // Invalid file
      expect(Square.parse('d'), isNull); // Too short
      expect(Square.parse('d12'), isNull); // Too long
    });

    test('CommentShapeColor parses all colors', () {
      expect(
        CommentShapeColor.parseShapeColor('G'),
        CommentShapeColor.green,
      );
      expect(CommentShapeColor.parseShapeColor('R'), CommentShapeColor.red);
      expect(
        CommentShapeColor.parseShapeColor('Y'),
        CommentShapeColor.yellow,
      );
      expect(CommentShapeColor.parseShapeColor('B'), CommentShapeColor.blue);
      expect(CommentShapeColor.parseShapeColor('X'), isNull); // Invalid
    });

    test('PgnCommentShape.fromPgn parses correctly', () {
      // Circle
      final PgnCommentShape? circle = PgnCommentShape.fromPgn('Gd6');
      expect(circle, isNotNull);
      expect(circle!.color, CommentShapeColor.green);
      expect(circle.from.name, 'd6');
      expect(circle.to.name, 'd6');

      // Arrow
      final PgnCommentShape? arrow = PgnCommentShape.fromPgn('Rd6f4');
      expect(arrow, isNotNull);
      expect(arrow!.color, CommentShapeColor.red);
      expect(arrow.from.name, 'd6');
      expect(arrow.to.name, 'f4');

      // Invalid
      expect(PgnCommentShape.fromPgn('Xd6'), isNull);
      expect(PgnCommentShape.fromPgn('Gz9'), isNull);
    });

    test('PgnCommentShape toString formats correctly', () {
      const PgnCommentShape circle = PgnCommentShape(
        color: CommentShapeColor.green,
        from: Square('d6'),
        to: Square('d6'),
      );
      const PgnCommentShape arrow = PgnCommentShape(
        color: CommentShapeColor.red,
        from: Square('d6'),
        to: Square('f4'),
      );

      expect(circle.toString(), 'Gd6');
      expect(arrow.toString(), 'Rd6f4');
    });
  });
}