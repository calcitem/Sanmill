// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/material.dart';

import '../../game_page/widgets/mini_board.dart';
import '../../generated/intl/l10n.dart';
import '../models/review_models.dart';
import '../services/review_storage.dart';
import 'review_page.dart';

class ReviewHistoryPage extends StatefulWidget {
  const ReviewHistoryPage({super.key});

  @override
  State<ReviewHistoryPage> createState() => _ReviewHistoryPageState();
}

class _ReviewHistoryPageState extends State<ReviewHistoryPage> {
  late List<PrivateGameRecord> _records;

  @override
  void initState() {
    super.initState();
    _records = ReviewStorage.instance.listGames();
  }

  @override
  Widget build(BuildContext context) {
    final S strings = S.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(strings.privateHistory)),
      body: _records.isEmpty
          ? Center(child: Text(strings.noPrivateGames))
          : ListView.separated(
              key: const Key('review_history_list'),
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: _records.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (BuildContext context, int index) {
                final PrivateGameRecord record = _records[index];
                return ListTile(
                  key: Key('review_history_${record.id}'),
                  leading: SizedBox.square(
                    dimension: 64,
                    child: IgnorePointer(
                      child: MiniBoard(
                        boardLayout:
                            record.finalBoardLayout ??
                            '********/********/********',
                        hasDiagonalLines: record.rules.hasDiagonalLines,
                      ),
                    ),
                  ),
                  title: Text('${record.white} – ${record.black}'),
                  subtitle: Text(
                    '${record.result} · ${MaterialLocalizations.of(context).formatShortDate(record.completedAt.toLocal())}',
                  ),
                  trailing: IconButton(
                    tooltip: strings.reviewGame,
                    onPressed: () => _openReview(record),
                    icon: const Icon(Icons.analytics_outlined),
                  ),
                  onTap: () => _openReview(record),
                );
              },
            ),
    );
  }

  Future<void> _openReview(PrivateGameRecord record) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => ReviewPage(record: record),
      ),
    );
    if (mounted) {
      setState(() => _records = ReviewStorage.instance.listGames());
    }
  }
}
