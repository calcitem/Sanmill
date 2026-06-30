// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/games/mill/opening_book/opening_book_repository.dart';

import 'opening_book_test_assets.dart';

void main() {
  setUp(() {
    OpeningBookRepository.instance.resetForTest();
    OpeningBookRepository.instance.assetLoader = loadOpeningBookAssetFromDisk;
  });

  tearDown(() {
    OpeningBookRepository.instance.resetForTest();
    OpeningBookRepository.instance.assetLoader = loadOpeningBookAssetFromDisk;
  });

  test('loads the bundled nmm + el_filja books from disk', () async {
    await OpeningBookRepository.instance.ensureLoaded();

    expect(OpeningBookRepository.instance.isLoaded, isTrue);
    expect(
      OpeningBookRepository.instance.oracleFor(isElFilja: false),
      isNotEmpty,
    );
    expect(
      OpeningBookRepository.instance.openingsFor(isElFilja: false),
      isNotEmpty,
    );
    // El Filja ships oracle entries but no curated named lines.
    expect(
      OpeningBookRepository.instance.oracleFor(isElFilja: true),
      isNotEmpty,
    );
  });

  test('a missing asset degrades to empty tables, not a throw', () async {
    OpeningBookRepository.instance.assetLoader = (String key) async =>
        throw const FileSystemException('missing');
    await OpeningBookRepository.instance.ensureLoaded();
    expect(OpeningBookRepository.instance.oracleFor(isElFilja: false), isEmpty);
    expect(
      OpeningBookRepository.instance.openingsFor(isElFilja: false),
      isEmpty,
    );
  });

  test('ensureLoaded is idempotent across concurrent callers', () async {
    final Future<void> a = OpeningBookRepository.instance.ensureLoaded();
    final Future<void> b = OpeningBookRepository.instance.ensureLoaded();
    await Future.wait(<Future<void>>[a, b]);
    expect(OpeningBookRepository.instance.isLoaded, isTrue);
  });
}
