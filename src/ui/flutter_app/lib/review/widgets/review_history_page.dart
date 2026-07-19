// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/material.dart';

import '../../game_page/widgets/mini_board.dart';
import '../../generated/intl/l10n.dart';
import '../../shared/utils/localizations/sanmill_localizations.dart';
import '../models/review_models.dart';
import '../services/review_storage.dart';
import 'review_page.dart';

class ReviewHistoryPage extends StatefulWidget {
  const ReviewHistoryPage({super.key, @visibleForTesting this.initialRecords});

  final List<PrivateGameRecord>? initialRecords;

  @override
  State<ReviewHistoryPage> createState() => _ReviewHistoryPageState();
}

class _ReviewHistoryPageState extends State<ReviewHistoryPage> {
  late List<PrivateGameRecord> _records;
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _records = widget.initialRecords ?? ReviewStorage.instance.listGames();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final S strings = S.of(context);
    final MaterialLocalizations materialStrings = MaterialLocalizations.of(
      context,
    );
    final String backLabel = materialStrings.backButtonTooltip;
    final List<PrivateGameRecord> visibleRecords = _visibleRecords(
      materialStrings,
    );
    final Scaffold scaffold = Scaffold(
      appBar: AppBar(
        leading: IconButton(
          key: Key(
            _isSearching
                ? 'review_history_search_close'
                : 'review_history_back',
          ),
          tooltip: backLabel,
          onPressed: _isSearching
              ? _closeSearch
              : () => Navigator.maybePop(context),
          icon: Icon(Icons.arrow_back_rounded, semanticLabel: backLabel),
        ),
        title: _isSearching
            ? TextField(
                key: const Key('review_history_search_field'),
                autofocus: true,
                controller: _searchController,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  border: InputBorder.none,
                  hintText: strings.search,
                ),
                onChanged: (String value) {
                  setState(() => _searchQuery = value);
                },
              )
            : Text(strings.privateHistory),
        actions: <Widget>[
          if (_isSearching) ...<Widget>[
            if (_searchQuery.isNotEmpty)
              IconButton(
                key: const Key('review_history_search_clear'),
                tooltip: materialStrings.clearButtonTooltip,
                onPressed: _clearSearch,
                icon: const Icon(Icons.close_rounded),
              ),
          ] else if (_records.isNotEmpty)
            IconButton(
              key: const Key('review_history_search'),
              tooltip: strings.search,
              onPressed: () => setState(() => _isSearching = true),
              icon: const Icon(Icons.search_rounded),
            ),
        ],
      ),
      body: _records.isEmpty
          ? Center(child: Text(strings.noPrivateGames))
          : visibleRecords.isEmpty
          ? Center(
              key: const Key('review_history_no_matches'),
              child: Text(strings.noMatchingGames),
            )
          : ListView.separated(
              key: const Key('review_history_list'),
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: visibleRecords.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (BuildContext context, int index) {
                final PrivateGameRecord record = visibleRecords[index];
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
                  title: Text(
                    localizedGamePlayersSummary(
                          strings,
                          white: record.white,
                          black: record.black,
                        ) ??
                        strings.game,
                  ),
                  subtitle: Text(
                    '${MaterialLocalizations.of(context).formatShortDate(record.completedAt.toLocal())} · ${record.result}',
                  ),
                  trailing: IconButton(
                    key: Key('review_history_open_${record.id}'),
                    tooltip: strings.reviewGame,
                    onPressed: () => _openReview(record),
                    icon: Icon(
                      Icons.analytics_outlined,
                      semanticLabel: strings.reviewGame,
                    ),
                  ),
                  onTap: () => _openReview(record),
                );
              },
            ),
    );
    return PopScope(
      canPop: !_isSearching,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (!didPop && _isSearching) {
          _closeSearch();
        }
      },
      child: scaffold,
    );
  }

  List<PrivateGameRecord> _visibleRecords(
    MaterialLocalizations materialStrings,
  ) {
    final String query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) {
      return _records;
    }
    return _records
        .where((PrivateGameRecord record) {
          final String date = materialStrings.formatShortDate(
            record.completedAt.toLocal(),
          );
          return <String>[
            record.white,
            record.black,
            record.result,
            date,
          ].any((String value) => value.toLowerCase().contains(query));
        })
        .toList(growable: false);
  }

  void _closeSearch() {
    setState(() {
      _isSearching = false;
      _searchQuery = '';
      _searchController.clear();
    });
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() => _searchQuery = '');
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
