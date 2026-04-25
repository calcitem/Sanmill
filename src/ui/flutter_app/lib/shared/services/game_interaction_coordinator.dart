// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'package:flutter/material.dart';

import '../../generated/intl/l10n.dart';
import '../widgets/snackbars/scaffold_messenger.dart';

/// LAN opponent asked to restart: show accept / reject, then run callbacks.
/// Kept as top-level to avoid a static-only class; [GameController] stays thin
/// on dialog code paths.
void showLanRestartRequestDialog({
  required void Function(BuildContext dialogContext) onAccept,
  required void Function(BuildContext dialogContext) onReject,
}) {
  final BuildContext? context = rootScaffoldMessengerKey.currentContext;
  if (context == null) {
    return;
  }
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext dialogContext) {
      return AlertDialog(
        title: Text(S.of(dialogContext).restartRequest),
        content: Text(
          S.of(dialogContext).opponentRequestedToRestartTheGameDoYouAccept,
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              onAccept(dialogContext);
            },
            child: Text(S.of(dialogContext).yes),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              onReject(dialogContext);
            },
            child: Text(S.of(dialogContext).no),
          ),
        ],
      );
    },
  );
}
