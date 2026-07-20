// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/material.dart';

import '../../generated/intl/l10n.dart';

const List<int> _qualityNagOrder = <int>[3, 1, 5, 6, 2, 4];

Future<void> showQualityAnnotationSheet({
  required BuildContext context,
  required int? selectedNag,
  required String keyPrefix,
  required ValueChanged<int?> onChanged,
}) {
  assert(
    selectedNag == null || (selectedNag >= 1 && selectedNag <= 6),
    'Quality annotations must use a conventional NAG from 1 to 6.',
  );
  assert(keyPrefix.isNotEmpty, 'Quality annotation keys require a prefix.');

  final S strings = S.of(context);
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (BuildContext sheetContext) {
      final bool showSystemDismiss =
          Theme.of(sheetContext).platform == TargetPlatform.iOS;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      strings.qualityAnnotation,
                      style: Theme.of(sheetContext).textTheme.titleLarge,
                    ),
                  ),
                  if (showSystemDismiss)
                    TextButton(
                      key: Key('${keyPrefix}_cancel'),
                      onPressed: () => Navigator.pop(sheetContext),
                      child: Text(strings.cancel),
                    ),
                ],
              ),
              Text(
                selectedNag == null
                    ? strings.reviewNoAnnotation
                    : strings.reviewCurrentAnnotation(
                        '${qualityNagSymbol(selectedNag)} ${qualityNagLabel(sheetContext, selectedNag)}',
                      ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  for (final int nag in _qualityNagOrder)
                    Semantics(
                      key: Key('${keyPrefix}_$nag'),
                      label:
                          '${qualityNagSymbol(nag)} ${qualityNagLabel(sheetContext, nag)}',
                      button: true,
                      selected: selectedNag == nag,
                      excludeSemantics: true,
                      child: ChoiceChip(
                        label: Text(
                          '${qualityNagSymbol(nag)} ${qualityNagLabel(sheetContext, nag)}',
                        ),
                        selected: selectedNag == nag,
                        showCheckmark: true,
                        onSelected: (_) {
                          Navigator.pop(sheetContext);
                          onChanged(nag);
                        },
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  TextButton.icon(
                    key: Key('${keyPrefix}_clear'),
                    onPressed: selectedNag == null
                        ? null
                        : () {
                            Navigator.pop(sheetContext);
                            onChanged(null);
                          },
                    icon: const Icon(Icons.clear_rounded),
                    label: Text(strings.clearAnnotation),
                  ),
                  if (showSystemDismiss) ...<Widget>[
                    const SizedBox(width: 8),
                    FilledButton.tonal(
                      key: Key('${keyPrefix}_done'),
                      onPressed: () => Navigator.pop(sheetContext),
                      child: Text(strings.done),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}

String qualityNagSymbol(int nag) => switch (nag) {
  1 => '!',
  2 => '?',
  3 => '!!',
  4 => '??',
  5 => '!?',
  6 => '?!',
  _ => throw ArgumentError.value(nag, 'nag', 'Expected a NAG from 1 to 6.'),
};

String qualityNagLabel(BuildContext context, int nag) {
  final S strings = S.of(context);
  return switch (nag) {
    1 => strings.reviewGradeGood,
    2 => strings.reviewGradeMistake,
    3 => strings.reviewGradeBrilliant,
    4 => strings.reviewGradeBlunder,
    5 => strings.reviewGradeInteresting,
    6 => strings.reviewGradeDubious,
    _ => throw ArgumentError.value(nag, 'nag', 'Expected a NAG from 1 to 6.'),
  };
}
