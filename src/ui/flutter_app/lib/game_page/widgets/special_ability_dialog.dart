// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// special_ability_dialog.dart

import 'package:flutter/material.dart';

import '../../generated/intl/l10n.dart';
import '../services/mill.dart';

/// Dialog for choosing targets for special piece abilities
class SpecialAbilityDialog extends StatelessWidget {
  const SpecialAbilityDialog({
    super.key,
    required this.specialPiece,
    required this.availableTargets,
    required this.onTargetSelected,
    this.allowMultiple = false,
  });

  final SpecialPiece specialPiece;
  final List<int> availableTargets;
  final Function(List<int>) onTargetSelected;
  final bool allowMultiple;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('${specialPiece.localizedName(context)} Ability'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            specialPiece.description,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          if (availableTargets.isEmpty)
            const Text('No valid targets available.')
          else
            Text(
              allowMultiple
                  ? 'Select target squares:'
                  : 'Select a target square:',
              style: Theme.of(context).textTheme.titleSmall,
            ),
          const SizedBox(height: 8),
          if (availableTargets.isNotEmpty)
            SizedBox(
              height: 200,
              child: ListView.builder(
                itemCount: availableTargets.length,
                itemBuilder: (BuildContext context, int index) {
                  final int square = availableTargets[index];
                  final String notation = _squareToNotation(square);

                  return ListTile(
                    title: Text('Square $notation'),
                    onTap: () {
                      onTargetSelected(<int>[square]);
                      Navigator.of(context).pop();
                    },
                  );
                },
              ),
            ),
        ],
      ),
      actions: <Widget>[
        if (availableTargets.isEmpty)
          TextButton(
            onPressed: () {
              onTargetSelected(<int>[]);
              Navigator.of(context).pop();
            },
            child: Text(S.of(context).ok),
          )
        else
          TextButton(
            onPressed: () {
              onTargetSelected(<int>[]);
              Navigator.of(context).pop();
            },
            child: const Text('Skip'),
          ),
      ],
    );
  }

  /// Convert square index to chess notation (a1, b2, etc.)
  String _squareToNotation(int square) {
    // This is a simplified conversion - in a full implementation,
    // this would use the proper square-to-notation conversion
    final int file = (square ~/ 8) + 1;
    final int rank = (square % 8) + 1;
    return '${String.fromCharCode(96 + file)}$rank';
  }
}

/// Show special ability target selection dialog
Future<List<int>> showSpecialAbilityDialog(
  BuildContext context,
  SpecialPiece specialPiece,
  List<int> availableTargets, {
  bool allowMultiple = false,
}) async {
  List<int> selectedTargets = <int>[];

  await showDialog<void>(
    context: context,
    builder: (BuildContext context) => SpecialAbilityDialog(
      specialPiece: specialPiece,
      availableTargets: availableTargets,
      allowMultiple: allowMultiple,
      onTargetSelected: (List<int> targets) {
        selectedTargets = targets;
      },
    ),
  );

  return selectedTargets;
}
