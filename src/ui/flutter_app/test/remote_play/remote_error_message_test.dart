// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanmill/generated/intl/l10n.dart';
import 'package:sanmill/remote_play/remote_error_message.dart';

void main() {
  test('socket failures use a user-facing network message', () async {
    final S strings = await S.delegate.load(const Locale('en'));
    const SocketException error = SocketException(
      'Connection failed (OS Error: Network is unreachable, errno = 101)',
    );

    final String message = remoteConnectionFailureMessage(strings, error);

    expect(
      message,
      'Network connection unavailable. Make sure both devices are connected '
      'to the same Wi-Fi network, then try again.',
    );
    expect(message, isNot(contains('SocketException')));
    expect(message, isNot(contains('errno')));
  });

  test('wrapped socket failures are also sanitized', () async {
    final S strings = await S.delegate.load(const Locale('en'));

    final String message = remoteConnectionFailureMessage(
      strings,
      'SocketException: Connection reset by peer',
    );

    expect(message, strings.remoteNetworkUnavailable);
  });

  test('unknown failures retain their diagnostic description', () async {
    final S strings = await S.delegate.load(const Locale('en'));

    final String message = remoteConnectionFailureMessage(
      strings,
      const FormatException('invalid handshake'),
    );

    expect(
      message,
      'Remote connection failed: FormatException: invalid handshake',
    );
  });

  test('GATT failures use a Bluetooth-specific recovery message', () async {
    final S strings = await S.delegate.load(const Locale('en'));

    final String message = remoteConnectionFailureMessage(
      strings,
      'UniversalBleException: Unknown Error 133',
    );

    expect(message, strings.bluetoothConnectionFailed);
    expect(message, isNot(contains('133')));
  });

  test('GATT timeout 147 retains the timeout guidance', () async {
    final S strings = await S.delegate.load(const Locale('en'));

    final String message = remoteConnectionFailureMessage(
      strings,
      'BluetoothGatt.GATT_CONNECTION_TIMEOUT 147',
    );

    expect(message, strings.bluetoothConnectionTimedOut);
    expect(message, isNot(contains('147')));
  });
}
