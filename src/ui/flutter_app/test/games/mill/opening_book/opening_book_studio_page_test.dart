// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image_lib;
import 'package:sanmill/games/mill/opening_book/opening_book_source_models.dart';
import 'package:sanmill/games/mill/opening_book/opening_book_studio_page.dart';
import 'package:sanmill/games/mill/opening_book/opening_book_studio_repository.dart';
import 'package:sanmill/generated/intl/l10n.dart';
import 'package:sanmill/shared/utils/localizations/sanmill_localizations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('studio edits, validates, saves, exports, and screenshots', (
    WidgetTester tester,
  ) async {
    final _FakeOpeningBookStudioRepository repository =
        _FakeOpeningBookStudioRepository(_samplePackage());

    await tester.binding.setSurfaceSize(const Size(1280, 900));

    await tester.pumpWidget(
      _localizedApp(
        OpeningBookStudioPage(repository: repository, showSnackBars: false),
      ),
    );
    await _pumpStudioFrame(tester);

    expect(find.byKey(const Key('opening_book_studio_page')), findsOneWidget);
    expect(find.text('Opening Book Studio'), findsOneWidget);
    expect(find.text('Center Cross'), findsWidgets);
    expect(find.text('Validation passed.'), findsOneWidget);

    final TextFormField nameField = tester.widget<TextFormField>(
      find.byKey(const Key('opening_book_studio_name_field')),
    );
    nameField.onChanged!('Center Cross Revised');
    await _pumpStudioFrame(tester);

    await tester.tap(
      find.byKey(const Key('opening_book_studio_save_asset_button')),
    );
    await _pumpStudioFrame(tester);
    expect(repository.savedPackage, isNotNull);
    expect(
      repository.savedPackage!.openings.single.name,
      'Center Cross Revised',
    );

    await tester.tap(
      find.byKey(const Key('opening_book_studio_export_button')),
    );
    await _pumpStudioFrame(tester);
    expect(repository.exportedPackage, isNotNull);
    expect(repository.lastDialogTitle, 'Export Sanmill opening book');

    final _ScreenshotStats stats =
        await tester.runAsync<_ScreenshotStats>(
          () => _captureScreenshotStats(
            find.byKey(const Key('opening_book_studio_repaint_boundary')),
            tester,
          ),
        ) ??
        _ScreenshotStats.empty;
    if (stats.rawBytes <= 1000000 ||
        stats.darkPixels <= 1000 ||
        stats.distinctColorBuckets <= 10) {
      fail('Opening Book Studio screenshot did not contain enough UI detail.');
    }
  });

  testWidgets('studio imports a Sanmill source package', (
    WidgetTester tester,
  ) async {
    final _FakeOpeningBookStudioRepository repository =
        _FakeOpeningBookStudioRepository(
          _samplePackage(),
          importPackage: SanmillOpeningBookSourcePackage.nmm(
            openings: <SanmillOpeningSourceEntry>[
              SanmillOpeningSourceEntry.empty(
                1,
              ).copyWith(id: 'imported-line', name: 'Imported Line'),
            ],
          ),
        );

    await tester.binding.setSurfaceSize(const Size(1000, 700));

    await tester.pumpWidget(
      _localizedApp(
        OpeningBookStudioPage(repository: repository, showSnackBars: false),
      ),
    );
    await _pumpStudioFrame(tester);

    await tester.tap(
      find.byKey(const Key('opening_book_studio_import_button')),
    );
    await _pumpStudioFrame(tester);

    expect(find.text('Imported Line'), findsWidgets);
    expect(repository.importCalled, isTrue);
  });
}

Widget _localizedApp(Widget child) {
  return MaterialApp(
    localizationsDelegates: sanmillLocalizationsDelegates,
    supportedLocales: S.supportedLocales,
    locale: const Locale('en'),
    home: child,
  );
}

Future<void> _pumpStudioFrame(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

Future<_ScreenshotStats> _captureScreenshotStats(
  Finder finder,
  WidgetTester tester,
) async {
  final RenderRepaintBoundary boundary = tester
      .renderObject<RenderRepaintBoundary>(finder);
  final ui.Image image = await boundary.toImage();
  try {
    final ByteData? rgbaData = await image.toByteData();
    assert(rgbaData != null, 'RGBA screenshot data must be available.');

    final Uint8List rgba = rgbaData!.buffer.asUint8List();
    if (const bool.fromEnvironment('SANMILL_WRITE_STUDIO_SCREENSHOT')) {
      final image_lib.Image screenshot = image_lib.Image.fromBytes(
        width: image.width,
        height: image.height,
        bytes: rgba.buffer,
        numChannels: 4,
        order: image_lib.ChannelOrder.rgba,
      );
      await File(
        '/tmp/sanmill_opening_book_studio.png',
      ).writeAsBytes(image_lib.encodePng(screenshot), flush: true);
    }

    int darkPixels = 0;
    final Set<int> buckets = <int>{};
    for (int offset = 0; offset < rgba.length; offset += 16) {
      final int r = rgba[offset];
      final int g = rgba[offset + 1];
      final int b = rgba[offset + 2];
      final int a = rgba[offset + 3];
      if (a == 0) {
        continue;
      }
      final int luminance = r + g + b;
      if (luminance < 220) {
        darkPixels++;
      }
      buckets.add((r ~/ 32) << 10 | (g ~/ 32) << 5 | (b ~/ 32));
    }
    return _ScreenshotStats(
      rawBytes: rgba.length,
      darkPixels: darkPixels,
      distinctColorBuckets: buckets.length,
    );
  } finally {
    image.dispose();
  }
}

SanmillOpeningBookSourcePackage _samplePackage() {
  return SanmillOpeningBookSourcePackage.nmm(
    openings: const <SanmillOpeningSourceEntry>[
      SanmillOpeningSourceEntry(
        id: 'center-cross',
        name: 'Center Cross',
        family: 'Central',
        aliases: <String>['Cross setup'],
        side: 'both',
        favoredSide: 'W',
        confidence: 0.9,
        tags: <String>['placement', 'manual'],
        stats: SanmillOpeningStats(
          whiteWins: 3,
          blackWins: 1,
          draws: 2,
          sampleSize: 6,
        ),
        line: SanmillOpeningLine(
          moves: <String>['d2', 'd6', 'd5', 'e5'],
          comment: 'Controls the central files.',
          variations: <SanmillOpeningVariation>[
            SanmillOpeningVariation(
              id: 'center-cross-wing',
              name: 'Wing try',
              afterPly: 2,
              moves: <String>['g7', 'a1'],
            ),
          ],
        ),
        commonBlunders: <String>['c3 before d5'],
        recommendedResponses: <String, List<String>>{
          'W': <String>['d5'],
          'B': <String>['e5'],
        },
        source: 'book',
        sourceReference: 'test',
      ),
    ],
  );
}

class _ScreenshotStats {
  const _ScreenshotStats({
    required this.rawBytes,
    required this.darkPixels,
    required this.distinctColorBuckets,
  });

  static const _ScreenshotStats empty = _ScreenshotStats(
    rawBytes: 0,
    darkPixels: 0,
    distinctColorBuckets: 0,
  );

  final int rawBytes;
  final int darkPixels;
  final int distinctColorBuckets;
}

class _FakeOpeningBookStudioRepository extends OpeningBookStudioRepository {
  _FakeOpeningBookStudioRepository(this.package, {this.importPackage});

  SanmillOpeningBookSourcePackage package;
  SanmillOpeningBookSourcePackage? importPackage;
  SanmillOpeningBookSourcePackage? savedPackage;
  SanmillOpeningBookSourcePackage? exportedPackage;
  String? lastDialogTitle;
  bool importCalled = false;

  @override
  Future<SanmillOpeningBookSourcePackage> loadNmmSource() async => package;

  @override
  Future<void> saveNmmSource(SanmillOpeningBookSourcePackage package) async {
    savedPackage = package;
  }

  @override
  Future<bool?> exportSourcePackage(
    SanmillOpeningBookSourcePackage package, {
    required String dialogTitle,
  }) async {
    exportedPackage = package;
    lastDialogTitle = dialogTitle;
    return true;
  }

  @override
  Future<SanmillOpeningBookSourcePackage?> importSourcePackage() async {
    importCalled = true;
    return importPackage;
  }
}
