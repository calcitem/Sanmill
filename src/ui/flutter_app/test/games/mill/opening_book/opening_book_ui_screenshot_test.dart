// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_flutter.dart' show Box;
import 'package:sanmill/appearance_settings/models/color_settings.dart';
import 'package:sanmill/game_page/services/mill.dart';
import 'package:sanmill/game_page/widgets/game_page.dart';
import 'package:sanmill/game_platform/game_id.dart';
import 'package:sanmill/game_platform/game_session.dart';
import 'package:sanmill/games/mill/mill_constants.dart';
import 'package:sanmill/games/mill/mill_marked_pieces_codec.dart';
import 'package:sanmill/games/mill/mill_session_recorder_bridge.dart';
import 'package:sanmill/games/mill/native_mill_game_session.dart';
import 'package:sanmill/games/mill/native_mill_rules_port.dart';
import 'package:sanmill/games/mill/opening_book/opening_book_models.dart';
import 'package:sanmill/games/mill/opening_book/opening_book_repository.dart';
import 'package:sanmill/general_settings/models/general_settings.dart';
import 'package:sanmill/general_settings/widgets/general_settings_page.dart';
import 'package:sanmill/generated/intl/l10n.dart';
import 'package:sanmill/shared/database/database.dart';
import 'package:sanmill/shared/utils/localizations/sanmill_localizations.dart';
import 'package:sanmill/src/rust/api/simple.dart' as tgf;

import '../../../helpers/mocks/mock_database.dart';
import 'opening_book_test_assets.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    OpeningBookRepository.instance.resetForTest();
    OpeningBookRepository.instance.assetLoader = loadOpeningBookAssetFromDisk;
    await OpeningBookRepository.instance.ensureLoaded();
  });

  tearDownAll(OpeningBookRepository.instance.resetForTest);

  setUp(() {
    DB.instance = _OpeningBookUiDb(const GeneralSettings());
    GameController().gameRecorder.reset();
    GameController().headerTipNotifier.showTip('', snackBar: false);
    GameController().gameInstance.gameMode = GameMode.humanVsHuman;
  });

  tearDown(() {
    DB.instance = null;
  });

  testWidgets('settings page exposes opening-book controls', (
    WidgetTester tester,
  ) async {
    final _OpeningBookUiDb db = DB.instance! as _OpeningBookUiDb;
    db.updateGeneralSettings(const GeneralSettings());

    await tester.binding.setSurfaceSize(const Size(1100, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_localizedApp(const GeneralSettingsPage()));
    await tester.pump();

    final Finder useOpeningBook = find.text('Use opening book');
    final Finder showOpeningInfo = find.text('Show opening information');
    final Finder preferFavoredOpenings = find.text(
      'Prefer favourable openings',
    );
    expect(useOpeningBook, findsOneWidget);
    expect(showOpeningInfo, findsOneWidget);
    expect(preferFavoredOpenings, findsOneWidget);
  });

  testWidgets('game header screenshot shows recognised opening information', (
    WidgetTester tester,
  ) async {
    final _OpeningBookUiDb db = DB.instance! as _OpeningBookUiDb;
    db.updateGeneralSettings(
      db.generalSettings.copyWith(showOpeningInfo: true),
    );

    final OpeningEntry opening = OpeningBookRepository.instance
        .openingsFor(isElFilja: false)
        .firstWhere((OpeningEntry entry) => entry.lineMoves.length >= 2);
    final String normalizedOpeningName = opening.name.replaceAll('—', '-');
    final GlobalKey screenshotKey = GlobalKey();
    BuildContext? headerContext;
    final List<String> openingPrefix = opening.lineMoves.take(2).toList();
    final NativeMillGameSession session = NativeMillGameSession(
      rulesPort: _HeaderTestRulesPort(legalMoves: openingPrefix),
    );
    addTearDown(session.dispose);
    final MillSessionRecorderBridge recorderBridge =
        MillSessionRecorderBridge.forGameController(session: session);
    addTearDown(recorderBridge.dispose);
    await tester.binding.setSurfaceSize(const Size(2400, 160));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _localizedApp(
        Builder(
          builder: (BuildContext context) {
            headerContext = context;
            return Center(
              child: SizedBox(
                width: 2200,
                height: 48,
                child: ColoredBox(
                  color: Colors.black,
                  child: RepaintBoundary(
                    key: screenshotKey,
                    child: const HeaderTip(),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );

    for (final String move in openingPrefix) {
      await session.apply(
        GameAction(
          type: MillActionTypes.place,
          payload: <String, Object?>{'move': move},
        ),
      );
    }
    expect(
      GameController().gameRecorder.mainlineMoves.map(
        (ExtMove move) => move.move,
      ),
      openingPrefix,
    );

    GameController().gameRecorder.activeNode!.data!.comments = <String>[
      'existing user comment',
    ];

    final GameController controller = GameController();
    controller.refreshNativeSessionHeader(
      headerContext!,
      session,
      showThinking: true,
    );
    await _flushHeaderNotifierTimers(tester);

    expect(controller.headerTipNotifier.message, contains('Opening:'));
    expect(
      controller.headerTipNotifier.message,
      contains(normalizedOpeningName),
    );
    expect(
      controller.headerTipNotifier.message,
      contains(S.of(headerContext!).thinking.replaceAll('…', '...')),
    );
    expect(controller.headerTipNotifier.message, isNot(contains('—')));
    expect(controller.headerTipNotifier.message, isNot(contains('•')));

    controller.refreshNativeSessionHeader(headerContext!, session);
    await _flushHeaderNotifierTimers(tester);

    expect(controller.headerTipNotifier.message, contains('Opening:'));
    expect(
      controller.headerTipNotifier.message,
      contains(normalizedOpeningName),
    );
    expect(
      controller.headerTipNotifier.message,
      contains(S.of(headerContext!).tipToMove(S.of(headerContext!).white)),
    );
    expect(find.textContaining('Opening:'), findsAtLeastNWidgets(1));
    expect(find.text('existing user comment'), findsNothing);
    expect(find.byKey(const Key('header_tip_marquee')), findsOneWidget);

    final int brightPixels =
        await tester.runAsync<int>(() async {
          final ui.Image image = await _captureImage(screenshotKey);
          try {
            return _countBrightPixels(
              image,
              Rect.fromLTWH(
                0,
                0,
                image.width.toDouble(),
                image.height.toDouble(),
              ),
            );
          } finally {
            image.dispose();
          }
        }) ??
        0;
    expect(brightPixels, greaterThan(80));
  });
}

Future<void> _flushHeaderNotifierTimers(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 1));
  await tester.pump(const Duration(milliseconds: 1));
  await tester.pump(const Duration(milliseconds: 1));
}

Widget _localizedApp(Widget child) {
  return MaterialApp(
    localizationsDelegates: sanmillLocalizationsDelegates,
    supportedLocales: S.supportedLocales,
    locale: const Locale('en'),
    home: child,
  );
}

Future<ui.Image> _captureImage(GlobalKey key) {
  final RenderRepaintBoundary boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  return boundary.toImage();
}

Future<int> _countBrightPixels(ui.Image image, Rect region) async {
  return _countPixels(
    image,
    region,
    (int r, int g, int b, int a) => a > 0 && r + g + b > 600,
  );
}

Future<int> _countPixels(
  ui.Image image,
  Rect region,
  bool Function(int r, int g, int b, int a) predicate,
) async {
  final ByteData? data = await image.toByteData();
  assert(data != null, 'screenshot byte data must be available');
  final Uint8List bytes = data!.buffer.asUint8List();
  final int left = region.left.isFinite && region.left > 0
      ? region.left.floor()
      : 0;
  final int top = region.top.isFinite && region.top > 0
      ? region.top.floor()
      : 0;
  final int right = region.right.isFinite && region.right < image.width
      ? region.right.ceil()
      : image.width;
  final int bottom = region.bottom.isFinite && region.bottom < image.height
      ? region.bottom.ceil()
      : image.height;

  int count = 0;
  for (int y = top; y < bottom; y++) {
    for (int x = left; x < right; x++) {
      final int offset = (y * image.width + x) * 4;
      if (predicate(
        bytes[offset],
        bytes[offset + 1],
        bytes[offset + 2],
        bytes[offset + 3],
      )) {
        count++;
      }
    }
  }
  return count;
}

class _OpeningBookUiDb extends MockDB {
  _OpeningBookUiDb(GeneralSettings settings)
    : _generalSettingsListenable = ValueNotifier<Box<GeneralSettings>>(
        _SettingsBox<GeneralSettings>(DB.generalSettingsKey, settings),
      ),
      _colorSettingsListenable = ValueNotifier<Box<ColorSettings>>(
        _SettingsBox<ColorSettings>(DB.colorSettingsKey, const ColorSettings()),
      ) {
    generalSettings = settings;
  }

  final ValueNotifier<Box<GeneralSettings>> _generalSettingsListenable;
  final ValueNotifier<Box<ColorSettings>> _colorSettingsListenable;

  @override
  ValueListenable<Box<GeneralSettings>> get listenGeneralSettings {
    return _generalSettingsListenable;
  }

  @override
  ValueListenable<Box<ColorSettings>> get listenColorSettings {
    return _colorSettingsListenable;
  }

  void updateGeneralSettings(GeneralSettings settings) {
    generalSettings = settings;
    _generalSettingsListenable.value = _SettingsBox<GeneralSettings>(
      DB.generalSettingsKey,
      settings,
    );
  }
}

class _SettingsBox<T> extends Fake implements Box<T> {
  _SettingsBox(this.settingsKey, this.value);

  final String settingsKey;
  final T value;

  @override
  T? get(dynamic key, {T? defaultValue}) {
    return key == settingsKey ? value : defaultValue;
  }
}

class _HeaderTestRulesPort implements NativeMillRulesPort {
  _HeaderTestRulesPort({List<String> legalMoves = const <String>[]})
    : _legalMoves = legalMoves,
      _snapshot = GameStateSnapshot(
        gameId: GameId.mill,
        activeSeat: PlayerSeat.first,
        outcome: const GameOutcome.ongoing(),
        phase: 'placing',
        payload: <String, Object?>{
          'tgfPayload': Uint8List(280),
          millMarkedNodesPayloadKey: const <int>{},
        },
      );

  final List<String> _legalMoves;
  int _nextMoveIndex = 0;
  GameStateSnapshot _snapshot;

  GameAction _actionFor(String move) {
    return GameAction(
      type: MillActionTypes.place,
      payload: <String, Object?>{'move': move},
    );
  }

  Uint8List _payloadForCurrentBoard() {
    final Uint8List payload = Uint8List(280);
    for (int i = 0; i < _nextMoveIndex && i < 24; i++) {
      payload[i] = i.isEven ? 1 : 2;
    }
    return payload;
  }

  PlayerSeat get _nextSeat => _snapshot.activeSeat == PlayerSeat.first
      ? PlayerSeat.second
      : PlayerSeat.first;

  @override
  int get redoDepth => 0;

  @override
  GameStateSnapshot get snapshot => _snapshot;

  @override
  int get undoDepth => 0;

  @override
  List<GameAction> get legalActions {
    if (_nextMoveIndex >= _legalMoves.length) {
      return const <GameAction>[];
    }
    return <GameAction>[_actionFor(_legalMoves[_nextMoveIndex])];
  }

  @override
  GameStateSnapshot apply(GameAction action) {
    assert(isLegal(action), 'test action must be legal');
    _nextMoveIndex++;
    _snapshot = GameStateSnapshot(
      gameId: GameId.mill,
      activeSeat: _nextSeat,
      outcome: const GameOutcome.ongoing(),
      phase: 'placing',
      lastAction: action,
      payload: <String, Object?>{
        'tgfPayload': _payloadForCurrentBoard(),
        millMarkedNodesPayloadKey: const <int>{},
      },
    );
    return _snapshot;
  }

  @override
  bool isLegal(GameAction action) {
    if (_nextMoveIndex >= _legalMoves.length) {
      return false;
    }
    return action.type == MillActionTypes.place &&
        action.payload['move'] == _legalMoves[_nextMoveIndex];
  }

  @override
  tgf.MillAnalysisReport analyzePerfectDb() => const tgf.MillAnalysisReport(
    moves: <tgf.MillMoveAnalysis>[],
    traps: <String>[],
  );

  @override
  void dispose() {}

  @override
  String exportFen() => '';

  @override
  Stream<tgf.EngineEvent> millSearchEvents({
    required int depth,
    int moveLimitMs = 0,
    GeneralSettings? engineSettings,
  }) => const Stream<tgf.EngineEvent>.empty();

  @override
  GameAction? perfectDatabaseBestAction({GeneralSettings? engineSettings}) {
    return null;
  }

  @override
  GameStateSnapshot redo() => _snapshot;

  @override
  GameStateSnapshot setFromFen(String fen) => _snapshot;

  @override
  GameStateSnapshot setupClear() => _snapshot;

  @override
  GameStateSnapshot setupFinish() => _snapshot;

  @override
  GameStateSnapshot setupSetPiece(int node, int owner) => _snapshot;

  @override
  GameStateSnapshot setupSetSide(int side) {
    _snapshot = GameStateSnapshot(
      gameId: _snapshot.gameId,
      activeSeat: side == 0 ? PlayerSeat.first : PlayerSeat.second,
      outcome: _snapshot.outcome,
      phase: _snapshot.phase,
      lastAction: _snapshot.lastAction,
      payload: _snapshot.payload,
    );
    return _snapshot;
  }

  @override
  GameStateSnapshot undo() => _snapshot;
}
