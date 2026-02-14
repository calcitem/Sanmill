// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// constants_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/shared/config/constants.dart';

void main() {
  // ---------------------------------------------------------------------------
  // UrlHelper
  // ---------------------------------------------------------------------------
  group('UrlHelper', () {
    test('should store base and baseChinese', () {
      const UrlHelper url = UrlHelper(
        base: 'https://example.com',
        baseChinese: 'https://example.cn',
      );

      expect(url.base, 'https://example.com');
      expect(url.baseChinese, 'https://example.cn');
    });

    test('fromSubPath should append path to both base URLs', () {
      const UrlHelper url = UrlHelper(
        base: 'https://github.com',
        baseChinese: 'https://gitee.com',
      );

      final UrlHelper sub = url.fromSubPath('user/repo');

      expect(sub.base, 'https://github.com/user/repo');
      expect(sub.baseChinese, 'https://gitee.com/user/repo');
    });

    test('fromSubPath with separate Chinese path', () {
      const UrlHelper url = UrlHelper(
        base: 'https://github.com',
        baseChinese: 'https://gitee.com',
      );

      final UrlHelper sub = url.fromSubPath('wiki', 'wikis');

      expect(sub.base, 'https://github.com/wiki');
      expect(sub.baseChinese, 'https://gitee.com/wikis');
    });

    test('chained fromSubPath calls', () {
      const UrlHelper root = UrlHelper(
        base: 'https://a.com',
        baseChinese: 'https://b.com',
      );

      final UrlHelper level1 = root.fromSubPath('x');
      final UrlHelper level2 = level1.fromSubPath('y');

      expect(level2.base, 'https://a.com/x/y');
      expect(level2.baseChinese, 'https://b.com/x/y');
    });
  });

  // ---------------------------------------------------------------------------
  // Constants
  // ---------------------------------------------------------------------------
  group('Constants', () {
    test('appName should be Mill', () {
      expect(Constants.appName, 'Mill');
    });

    test('projectName should be Sanmill', () {
      expect(Constants.projectName, 'Sanmill');
    });

    test('authorAccount should be calcitem', () {
      expect(Constants.authorAccount, 'calcitem');
    });

    test('recipientEmails should not be empty', () {
      expect(Constants.recipientEmails, isNotEmpty);
      expect(Constants.recipientEmails.first, contains('@'));
    });

    test('settingsFile should contain project name', () {
      expect(Constants.settingsFile, contains('sanmill'));
    });

    test('highestSkillLevel should be 30', () {
      expect(Constants.highestSkillLevel, 30);
    });

    test('screenSizeThreshold should be 800', () {
      expect(Constants.screenSizeThreshold, 800);
    });

    test('repository URLs should contain full repository name', () {
      expect(
        Constants.repositoryUrl.base,
        contains(Constants.fullRepositoryName),
      );
    });

    test('issues URL should be based on repository URL', () {
      expect(Constants.issuesURL.base, contains('issues'));
    });

    test('wiki URL should be based on repository URL', () {
      expect(Constants.wikiURL.base, contains('wiki'));
    });

    test('privacy policy URL should be accessible', () {
      expect(Constants.privacyPolicyUrl.base, isNotEmpty);
      expect(Constants.privacyPolicyUrl.baseChinese, isNotEmpty);
    });

    test('EULA URLs should be defined', () {
      expect(Constants.endUserLicenseAgreementUrl.base, isNotEmpty);
      expect(Constants.appleStandardEulaUrl, isNotEmpty);
    });

    test('sourceControlUrl base should be GitHub', () {
      expect(Constants.sourceControlUrl.base, contains('github.com'));
    });
  });
}
