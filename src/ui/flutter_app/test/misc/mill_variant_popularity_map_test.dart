// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image_lib;
import 'package:sanmill/generated/intl/l10n.dart';
import 'package:sanmill/misc/mill_variant_popularity_map.dart';

void main() {
  const List<String> variantIds = <String>[
    'standard_9mm',
    'twelve_mens_morris',
    'morabaraba',
    'dooz',
    'lasker_morris',
    'russian_mill',
    'cham_gonu',
    'zhi_qi',
    'cheng_san_qi',
    'da_san_qi',
    'mul_mulan',
    'nerenchi',
    'el_filja',
  ];

  test('every variant has a bundled popularity mask', () {
    expect(File('assets/maps/world_land.png').existsSync(), isTrue);

    for (final String variantId in variantIds) {
      final String asset = millVariantPopularityMaskAssetById(variantId);
      expect(File(asset).existsSync(), isTrue, reason: variantId);
    }
  });

  test('refined masks stay inside their requested geographic regions', () {
    final image_lib.Image land = _loadMap('world_land.png');
    final image_lib.Image standard = _loadVariantMap('standard_9mm');
    const _GeoBounds greenland = _GeoBounds(-75, 58, -10, 85);

    expect(_missingOpaquePixels(land, standard, greenland), 0);
    for (final _GeoBounds southeastAsia in <_GeoBounds>[
      const _GeoBounds(95, 0, 115, 20),
      const _GeoBounds(116, 5, 127, 20),
      const _GeoBounds(95, -10, 141, 5),
    ]) {
      expect(_opaquePixels(standard, southeastAsia), 0);
    }
    expect(_overlappingOpaquePixels(standard, _loadVariantMap('cham_gonu')), 0);

    final image_lib.Image twelveMensMorris = _loadVariantMap(
      'twelve_mens_morris',
    );
    expect(
      _opaquePixels(twelveMensMorris, const _GeoBounds(42.5, 12, 60, 30)),
      0,
    );

    final image_lib.Image dooz = _loadVariantMap('dooz');
    _expectMaskWithin(dooz, const _GeoBounds(44, 24.5, 75.5, 41.5));
    expect(_opaquePixels(dooz, const _GeoBounds(42, 12, 58, 26)), 0);
    expect(_opaquePixels(dooz, const _GeoBounds(45, 42, 90, 57)), 0);
    expect(_opaquePixels(dooz, const _GeoBounds(75.5, 24, 90, 50)), 0);

    final image_lib.Image russianMill = _loadVariantMap('russian_mill');
    expect(_opaquePixels(russianMill, const _GeoBounds(61, 30, 180, 85)), 0);
    expect(_opaquePixels(russianMill, const _GeoBounds(15, 20, 65, 40)), 0);

    _expectMaskWithin(
      _loadVariantMap('cham_gonu'),
      const _GeoBounds(124, 34, 130.5, 43),
    );

    _expectMaskWithin(
      _loadVariantMap('zhi_qi'),
      const _GeoBounds(116, 21.5, 122.5, 29),
    );

    final image_lib.Image daSanQi = _loadVariantMap('da_san_qi');
    _expectMaskWithin(daSanQi, const _GeoBounds(97, 21, 116, 34.5));
    expect(_opaquePixels(daSanQi, const _GeoBounds(116.5, 22, 123, 32)), 0);
    expect(_opaquePixels(daSanQi, const _GeoBounds(118, 20, 123, 27)), 0);
    expect(_opaquePixels(daSanQi, const _GeoBounds(95, 10, 115, 20.5)), 0);

    _expectMaskWithin(
      _loadVariantMap('nerenchi'),
      const _GeoBounds(79.5, 5.5, 82.2, 10.2),
    );

    final image_lib.Image elFilja = _loadVariantMap('el_filja');
    expect(_opaquePixels(elFilja, const _GeoBounds(-10, 36, 0, 44)), 0);
    expect(_opaquePixels(elFilja, const _GeoBounds(0, 36.75, 4, 44)), 0);
  });

  test('Asian and Oceanian languages use the Pacific-centered map', () {
    const List<String> languageCodes = <String>[
      'bn',
      'bo',
      'gu',
      'hi',
      'id',
      'ja',
      'km',
      'kn',
      'ko',
      'ms',
      'my',
      'si',
      'ta',
      'te',
      'th',
      'ur',
      'uz',
      'vi',
      'zh',
    ];

    for (final String languageCode in languageCodes) {
      expect(
        millVariantMapCenterLongitudeForLocale(Locale(languageCode)),
        150,
        reason: languageCode,
      );
    }
    expect(
      millVariantMapCenterLongitudeForLocale(
        const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
      ),
      150,
    );
  });

  test('European and West Asian languages use the Greenwich-centered map', () {
    const List<String> languageCodes = <String>[
      'en',
      'ar',
      'fa',
      'he',
      'tr',
      'hy',
      'az',
      'de',
      'ru',
    ];

    for (final String languageCode in languageCodes) {
      expect(
        millVariantMapCenterLongitudeForLocale(Locale(languageCode)),
        0,
        reason: languageCode,
      );
    }
  });

  testWidgets('RTL locale shifts geography without mirroring it', (
    WidgetTester tester,
  ) async {
    Future<void> pumpMap(Locale locale) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: locale,
          localizationsDelegates: S.localizationsDelegates,
          supportedLocales: S.supportedLocales,
          home: const Scaffold(
            body: MillVariantPopularityMap(
              variantId: 'dooz',
              semanticsLabel: 'Dooz',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await pumpMap(const Locale('ur'));

    final Directionality geography = tester.widget<Directionality>(
      find.byKey(const Key('mill_variant_popularity_geography')),
    );
    expect(geography.textDirection, TextDirection.ltr);

    Positioned centerTile = tester.widget<Positioned>(
      find.descendant(
        of: find.byKey(const Key('mill_variant_popularity_mask_center')),
        matching: find.byType(Positioned),
      ),
    );
    expect(centerTile.left, closeTo(-centerTile.width! * 150 / 360, 0.01));

    await pumpMap(const Locale('ar'));
    centerTile = tester.widget<Positioned>(
      find.descendant(
        of: find.byKey(const Key('mill_variant_popularity_mask_center')),
        matching: find.byType(Positioned),
      ),
    );
    expect(centerTile.left, 0);
  });

  test('unsupported variant IDs fail fast', () {
    expect(
      () => millVariantPopularityMaskAssetById('unknown'),
      throwsStateError,
    );
  });
}

const _GeoBounds _wholeWorld = _GeoBounds(-180, -90, 180, 90);

class _GeoBounds {
  const _GeoBounds(this.west, this.south, this.east, this.north);

  final double west;
  final double south;
  final double east;
  final double north;
}

image_lib.Image _loadVariantMap(String variantId) {
  return _loadMap('mill_variant_$variantId.png');
}

image_lib.Image _loadMap(String filename) {
  final image_lib.Image? image = image_lib.decodePng(
    File('assets/maps/$filename').readAsBytesSync(),
  );
  expect(image, isNotNull, reason: filename);
  return image!;
}

int _opaquePixels(image_lib.Image image, _GeoBounds bounds) {
  final (int left, int top, int right, int bottom) = _pixelBounds(
    image,
    bounds,
  );
  int count = 0;
  for (int y = top; y < bottom; y++) {
    for (int x = left; x < right; x++) {
      if (image.getPixel(x, y).a > 127) {
        count++;
      }
    }
  }
  return count;
}

int _missingOpaquePixels(
  image_lib.Image land,
  image_lib.Image selection,
  _GeoBounds bounds,
) {
  assert(land.width == selection.width && land.height == selection.height);
  final (int left, int top, int right, int bottom) = _pixelBounds(land, bounds);
  int count = 0;
  for (int y = top; y < bottom; y++) {
    for (int x = left; x < right; x++) {
      if (land.getPixel(x, y).a > 127 && selection.getPixel(x, y).a <= 127) {
        count++;
      }
    }
  }
  return count;
}

int _overlappingOpaquePixels(image_lib.Image first, image_lib.Image second) {
  assert(first.width == second.width && first.height == second.height);
  int count = 0;
  for (int y = 0; y < first.height; y++) {
    for (int x = 0; x < first.width; x++) {
      if (first.getPixel(x, y).a > 127 && second.getPixel(x, y).a > 127) {
        count++;
      }
    }
  }
  return count;
}

void _expectMaskWithin(image_lib.Image image, _GeoBounds bounds) {
  final int total = _opaquePixels(image, _wholeWorld);
  expect(total, greaterThan(0));
  expect(_opaquePixels(image, bounds), total);
}

(int, int, int, int) _pixelBounds(image_lib.Image image, _GeoBounds bounds) {
  final int left = ((bounds.west + 180) / 360 * image.width).round().clamp(
    0,
    image.width,
  );
  final int right = ((bounds.east + 180) / 360 * image.width).round().clamp(
    0,
    image.width,
  );
  final int top = ((90 - bounds.north) / 180 * image.height).round().clamp(
    0,
    image.height,
  );
  final int bottom = ((90 - bounds.south) / 180 * image.height).round().clamp(
    0,
    image.height,
  );
  return (left, top, right, bottom);
}
