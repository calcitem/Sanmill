// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// git_info_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/shared/services/git_info.dart';

void main() {
  group('GitInfo', () {
    test('should store branch and revision', () {
      const GitInfo info = GitInfo(branch: 'main', revision: 'abc123def');

      expect(info.branch, 'main');
      expect(info.revision, 'abc123def');
    });

    test('revision can be null', () {
      const GitInfo info = GitInfo(branch: 'develop', revision: null);

      expect(info.branch, 'develop');
      expect(info.revision, isNull);
    });

    test('branch should not be empty', () {
      const GitInfo info = GitInfo(branch: 'feature/test', revision: '1234567');

      expect(info.branch, isNotEmpty);
    });
  });
}
