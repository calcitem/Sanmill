// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:io';

import '../generated/intl/l10n.dart';

String remoteConnectionFailureMessage(S strings, Object error) {
  final String raw = error.toString();
  final String lower = raw.toLowerCase();
  if (RegExp(r'\b147\b').hasMatch(raw) ||
      lower.contains('gatt_connection_timeout') ||
      (lower.contains('bluetooth') &&
          lower.contains('timeout') &&
          lower.contains('connect'))) {
    return strings.bluetoothConnectionTimedOut;
  }
  if (RegExp(r'\b133\b').hasMatch(raw) ||
      lower.contains('universalbleexception') ||
      lower.contains('gatt')) {
    return strings.bluetoothConnectionFailed;
  }
  if (error is SocketException ||
      lower.contains('socketexception') ||
      lower.contains('network is unreachable') ||
      lower.contains('connection refused') ||
      lower.contains('connection reset') ||
      lower.contains('broken pipe')) {
    return strings.remoteNetworkUnavailable;
  }
  return strings.remoteConnectionFailed(raw);
}
