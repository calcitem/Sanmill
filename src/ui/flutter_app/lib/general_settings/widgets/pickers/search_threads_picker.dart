// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// search_threads_picker.dart

part of 'package:sanmill/general_settings/widgets/general_settings_page.dart';

class _SearchThreadsPicker extends StatelessWidget {
  const _SearchThreadsPicker();

  static const List<int> _threadCounts = <int>[1, 2, 4, 6, 8, 12, 16];

  void _commit(BuildContext context, int value) {
    assert(_threadCounts.contains(value), 'Unsupported thread count: $value.');
    final GeneralSettings current = DB().generalSettings;
    DB().generalSettings = current.copyWith(engineThreads: value);
    logger.t("${GeneralSettingsPage._logTag} engineThreads: $value");
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final int selected = DB().generalSettings.engineThreads;
    assert(
      _threadCounts.contains(selected),
      'Stored thread count is not selectable: $selected.',
    );
    return SafeArea(
      child: Semantics(
        key: const Key('search_threads_picker_semantics'),
        label: S.of(context).engineThreads,
        child: RadioGroup<int>(
          groupValue: selected,
          onChanged: (int? next) {
            assert(next != null, 'Thread picker returned null value.');
            _commit(context, next!);
          },
          child: Column(
            key: const Key('search_threads_picker_column'),
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  S.of(context).engineThreads,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              for (final int value in _threadCounts)
                RadioListTile<int>(
                  key: Key('search_threads_picker_radio_$value'),
                  title: Text(value.toString()),
                  value: value,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
