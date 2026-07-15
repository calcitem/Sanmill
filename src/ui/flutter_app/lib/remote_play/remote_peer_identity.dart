// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:async';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:uuid/uuid.dart';

import 'remote_models.dart';

abstract final class RemotePeerIdentity {
  static const Uuid _uuid = Uuid();

  static Future<RemotePeerInfo> create() async {
    final (BaseDeviceInfo device, PackageInfo package) = await (
      DeviceInfoPlugin().deviceInfo,
      PackageInfo.fromPlatform(),
    ).wait;
    final Map<String, dynamic> data = device.data;
    final String model = _firstNonEmpty(<Object?>[
      data['model'],
      data['productName'],
      data['computerName'],
      data['prettyName'],
      data['localizedModel'],
      data['name'],
    ]);
    return RemotePeerInfo(
      peerId: _uuid.v4(),
      label: model.isEmpty ? 'Sanmill' : model,
      platform: defaultTargetPlatform.name,
      appVersion: package.version,
      appBuild: package.buildNumber,
    );
  }

  static String _firstNonEmpty(Iterable<Object?> values) {
    for (final Object? value in values) {
      final String text = value?.toString().trim() ?? '';
      if (text.isNotEmpty && text != 'null') {
        return text;
      }
    }
    return '';
  }
}
