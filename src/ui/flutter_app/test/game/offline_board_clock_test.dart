// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/game_page/services/offline_board_clock.dart';
import 'package:sanmill/games/mill/mill_types.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final OfflineBoardClock clock = OfflineBoardClock();

  setUp(() {
    clock
      ..reset()
      ..onFlag = null;
  });

  tearDown(() {
    clock
      ..reset()
      ..onFlag = null;
  });

  test('starts paused with an independent total for each side', () {
    clock.setup(
      initialTime: const Duration(minutes: 5),
      increment: const Duration(seconds: 3),
    );

    expect(clock.state.status, OfflineBoardClockStatus.paused);
    expect(clock.state.activeSide, PieceColor.white);
    expect(clock.state.whiteTime, const Duration(minutes: 5));
    expect(clock.state.blackTime, const Duration(minutes: 5));
    expect(clock.state.increment, const Duration(seconds: 3));
    expect(clock.state.hasStarted, isFalse);
  });

  test('unlimited control disables both clocks', () {
    clock.setup(initialTime: Duration.zero, increment: Duration.zero);

    expect(clock.state.status, OfflineBoardClockStatus.disabled);
    expect(clock.state.isEnabled, isFalse);
  });

  test('increment-only control starts each side with one increment', () {
    clock.setup(
      initialTime: Duration.zero,
      increment: const Duration(seconds: 3),
    );

    expect(clock.state.status, OfflineBoardClockStatus.paused);
    expect(clock.state.whiteTime, const Duration(seconds: 3));
    expect(clock.state.blackTime, const Duration(seconds: 3));
  });

  test('untimed first move starts opponent clock without increment', () {
    clock.setup(
      initialTime: const Duration(seconds: 5),
      increment: const Duration(seconds: 3),
    );

    clock.completeTurn(sideMoved: PieceColor.white, nextSide: PieceColor.black);

    expect(clock.state.status, OfflineBoardClockStatus.running);
    expect(clock.state.activeSide, PieceColor.black);
    expect(clock.state.whiteTime, const Duration(seconds: 5));
    expect(clock.state.hasStarted, isTrue);
  });

  test('running turn receives Fischer increment', () async {
    clock.setup(
      initialTime: const Duration(seconds: 5),
      increment: const Duration(seconds: 3),
    );
    clock.resume();
    await Future<void>.delayed(const Duration(milliseconds: 30));

    clock.completeTurn(sideMoved: PieceColor.white, nextSide: PieceColor.black);

    expect(clock.state.activeSide, PieceColor.black);
    expect(clock.state.whiteTime, greaterThan(const Duration(seconds: 7)));
    expect(clock.state.whiteTime, lessThan(const Duration(seconds: 8)));
    expect(clock.state.blackTime, const Duration(seconds: 5));
  });

  test('continuous capture action does not switch or add time', () {
    clock.setup(
      initialTime: const Duration(seconds: 5),
      increment: const Duration(seconds: 3),
    );
    clock.resume();
    final Duration before = clock.state.whiteTime;

    clock.completeTurn(sideMoved: PieceColor.white, nextSide: PieceColor.white);

    expect(clock.state.activeSide, PieceColor.white);
    expect(clock.state.whiteTime, before);
  });

  test('pause freezes time and resume continues the same side', () async {
    clock.setup(
      initialTime: const Duration(seconds: 2),
      increment: Duration.zero,
    );
    clock.resume();
    await Future<void>.delayed(const Duration(milliseconds: 130));
    clock.pause();
    final Duration pausedTime = clock.state.whiteTime;

    await Future<void>.delayed(const Duration(milliseconds: 150));

    expect(clock.state.status, OfflineBoardClockStatus.paused);
    expect(clock.state.whiteTime, pausedTime);
    clock.resume();
    expect(clock.state.activeSide, PieceColor.white);
    expect(clock.state.status, OfflineBoardClockStatus.running);
  });

  test('move while paused resumes opponent without granting increment', () {
    clock.setup(
      initialTime: const Duration(seconds: 5),
      increment: const Duration(seconds: 3),
    );
    clock
      ..resume()
      ..pause();
    final Duration whiteTime = clock.state.whiteTime;

    clock.completeTurn(sideMoved: PieceColor.white, nextSide: PieceColor.black);

    expect(clock.state.status, OfflineBoardClockStatus.running);
    expect(clock.state.activeSide, PieceColor.black);
    expect(clock.state.whiteTime, whiteTime);
    expect(clock.state.blackTime, const Duration(seconds: 5));
  });

  test('history side sync never grants increment', () async {
    clock.setup(
      initialTime: const Duration(seconds: 5),
      increment: const Duration(seconds: 3),
    );
    clock.resume();
    await Future<void>.delayed(const Duration(milliseconds: 30));

    clock.syncActiveSide(PieceColor.black);

    expect(clock.state.activeSide, PieceColor.black);
    expect(clock.state.whiteTime, lessThan(const Duration(seconds: 5)));
    expect(clock.state.blackTime, const Duration(seconds: 5));
    expect(clock.state.status, OfflineBoardClockStatus.running);
  });

  test('flag callback identifies the side whose time expired', () async {
    PieceColor? flagSide;
    clock
      ..onFlag = (PieceColor side) {
        flagSide = side;
      }
      ..setup(
        initialTime: const Duration(milliseconds: 40),
        increment: Duration.zero,
      )
      ..resume();

    await Future<void>.delayed(const Duration(milliseconds: 160));

    expect(clock.state.status, OfflineBoardClockStatus.flagged);
    expect(clock.state.whiteTime, Duration.zero);
    expect(clock.state.flagSide, PieceColor.white);
    expect(flagSide, PieceColor.white);
  });
}
