// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// report_attachment_registry_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/shared/services/report_attachment_registry.dart';

void main() {
  group('ReportAttachmentRegistry', () {
    setUp(ReportAttachmentRegistry.clear);
    tearDown(ReportAttachmentRegistry.clear);

    test('collects non-null paths in registration order', () async {
      ReportAttachmentRegistry.register(() async => '/tmp/a.txt');
      ReportAttachmentRegistry.register(() async => '/tmp/b.txt');

      final List<String> paths = await ReportAttachmentRegistry.collectPaths();

      expect(paths, <String>['/tmp/a.txt', '/tmp/b.txt']);
    });

    test('skips null and empty results', () async {
      ReportAttachmentRegistry.register(() async => null);
      ReportAttachmentRegistry.register(() async => '');
      ReportAttachmentRegistry.register(() async => '/tmp/c.txt');

      final List<String> paths = await ReportAttachmentRegistry.collectPaths();

      expect(paths, <String>['/tmp/c.txt']);
    });

    test('deduplicates identical paths', () async {
      ReportAttachmentRegistry.register(() async => '/tmp/dup.txt');
      ReportAttachmentRegistry.register(() async => '/tmp/dup.txt');

      final List<String> paths = await ReportAttachmentRegistry.collectPaths();

      expect(paths, <String>['/tmp/dup.txt']);
    });

    test('isolates a failing provider from the others', () async {
      ReportAttachmentRegistry.register(() async => throw Exception('boom'));
      ReportAttachmentRegistry.register(() async => '/tmp/ok.txt');

      final List<String> paths = await ReportAttachmentRegistry.collectPaths();

      expect(paths, <String>['/tmp/ok.txt']);
    });

    test('ignores duplicate provider registration', () async {
      Future<String?> provider() async => '/tmp/single.txt';

      ReportAttachmentRegistry.register(provider);
      ReportAttachmentRegistry.register(provider);

      expect(ReportAttachmentRegistry.providerCount, 1);
    });

    test('unregister removes a provider', () async {
      Future<String?> provider() async => '/tmp/x.txt';

      ReportAttachmentRegistry.register(provider);
      expect(ReportAttachmentRegistry.providerCount, 1);

      ReportAttachmentRegistry.unregister(provider);
      expect(ReportAttachmentRegistry.providerCount, 0);
    });
  });
}
