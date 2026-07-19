// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_page/services/gif_share/gif_share.dart';
import 'package:sanmill/game_page/services/mill.dart';
import 'package:sanmill/shared/database/database.dart';

import '../helpers/mocks/mock_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => DB.instance = MockDB());
  tearDown(() => DB.instance = null);

  test('GIF export uses a crisp fixed board size and continuous looping', () {
    expect(GifShare.imageSize, 540);
    expect(GifShare.loopCount, 0);
  });

  test('short GIF replays preserve every frame', () {
    expect(GifShare.sampledFrameIndices(4), <int>[0, 1, 2, 3]);
  });

  test('long GIF replays are sampled uniformly with both endpoints', () {
    final List<int> indices = GifShare.sampledFrameIndices(400);

    expect(indices, hasLength(GifShare.maximumFrameCount));
    expect(indices.first, 0);
    expect(indices.last, 399);
    expect(indices.toSet(), hasLength(indices.length));
    for (int i = 1; i < indices.length; i++) {
      expect(indices[i], greaterThan(indices[i - 1]));
    }
  });

  test('board replay encodes a valid fixed-size GIF', () async {
    final List<int>? gif = await GifShare().encodeGame(
      moves: <ExtMove>[
        ExtMove(
          'a1',
          side: PieceColor.white,
          boardLayout: '********/********/O*******',
        ),
      ],
      hasDiagonalLines: false,
    );

    expect(gif, isNotNull);
    expect(ascii.decode(gif!.take(6).toList()), 'GIF89a');
    expect(gif[6] | (gif[7] << 8), GifShare.imageSize);
    expect(gif[8] | (gif[9] << 8), GifShare.imageSize);
  });
}
