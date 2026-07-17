// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/generated/intl/l10n.dart';

void main() {
  test('Simplified Chinese localizes saved-game archive actions', () async {
    final S strings = await S.delegate.load(const Locale('zh'));

    expect(strings.copyGameToClipboard, '复制棋局到剪贴板');
    expect(strings.deleteSavedGameTitle, '删除已保存棋局？');
    expect(strings.deleteSavedGameMessage('game.pgn'), '删除“game.pgn”？此操作无法撤销。');
    expect(strings.exportGameArchive, '导出棋局归档');
    expect(strings.importGameArchive, '导入棋局归档');
    expect(strings.pgnFilesImported(1), '已导入 1 个 PGN 文件');
    expect(strings.pgnFilesImported(3), '已导入 3 个 PGN 文件');
    expect(strings.savedGameActions('game.pgn'), 'game.pgn 的操作');
    expect(strings.sortNewestFirst, '最新优先');
    expect(strings.sortOldestFirst, '最早优先');
  });
}
