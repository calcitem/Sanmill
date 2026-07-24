// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_page/services/offline_board_history.dart';
import 'package:sanmill/games/mill/mill_types.dart';

void main() {
  group('OfflineBoardHistory', () {
    test('has no takeback at the root', () {
      expect(
        OfflineBoardHistory.takeBackStepCount(const <PieceColor>[]),
        isNull,
      );
    });

    test('takes back one ordinary turn', () {
      expect(
        OfflineBoardHistory.takeBackStepCount(const <PieceColor>[
          PieceColor.white,
          PieceColor.black,
        ]),
        1,
      );
    });

    test('keeps a capture with the move that formed the mill', () {
      expect(
        OfflineBoardHistory.takeBackStepCount(const <PieceColor>[
          PieceColor.white,
          PieceColor.black,
          PieceColor.white,
          PieceColor.white,
        ]),
        2,
      );
    });

    test('keeps every consecutive capture in the same turn', () {
      expect(
        OfflineBoardHistory.takeBackStepCount(const <PieceColor>[
          PieceColor.white,
          PieceColor.black,
          PieceColor.white,
          PieceColor.white,
          PieceColor.white,
          PieceColor.white,
        ]),
        4,
      );
    });

    test('rejects history without a playable mover', () {
      expect(
        () => OfflineBoardHistory.takeBackStepCount(const <PieceColor>[
          PieceColor.nobody,
        ]),
        throwsAssertionError,
      );
    });

    group('requester takeback', () {
      test('has no takeback before the requester has moved', () {
        expect(
          OfflineBoardHistory.requesterTakeBackStepCount(const <PieceColor>[
            PieceColor.white,
          ], PieceColor.black),
          isNull,
        );
      });

      test('takes back only the requester turn before a reply', () {
        expect(
          OfflineBoardHistory.requesterTakeBackStepCount(const <PieceColor>[
            PieceColor.white,
          ], PieceColor.white),
          1,
        );
      });

      test('takes back the requester turn and opponent reply', () {
        expect(
          OfflineBoardHistory.requesterTakeBackStepCount(const <PieceColor>[
            PieceColor.white,
            PieceColor.black,
            PieceColor.white,
            PieceColor.black,
          ], PieceColor.white),
          2,
        );
      });

      test('keeps a capture inside the requester complete turn', () {
        expect(
          OfflineBoardHistory.requesterTakeBackStepCount(const <PieceColor>[
            PieceColor.white,
            PieceColor.black,
            PieceColor.white,
            PieceColor.white,
            PieceColor.black,
          ], PieceColor.white),
          3,
        );
      });

      test('keeps captures inside both complete turns', () {
        expect(
          OfflineBoardHistory.requesterTakeBackStepCount(const <PieceColor>[
            PieceColor.white,
            PieceColor.black,
            PieceColor.white,
            PieceColor.white,
            PieceColor.black,
            PieceColor.black,
          ], PieceColor.white),
          4,
        );
      });
    });
  });
}
