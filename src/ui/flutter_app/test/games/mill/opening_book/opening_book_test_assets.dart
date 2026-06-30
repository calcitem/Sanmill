// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:io';

/// Reads an opening-book asset directly from the project tree.
///
/// Flutter unit tests run with the working directory at the package root, so
/// the bundle asset keys (`assets/opening_books/...`) double as file paths.
/// Injecting this into [OpeningBookRepository.assetLoader] lets suites exercise
/// the real shipped books without a Flutter asset bundle.
Future<String> loadOpeningBookAssetFromDisk(String assetKey) {
  return File(assetKey).readAsString();
}
