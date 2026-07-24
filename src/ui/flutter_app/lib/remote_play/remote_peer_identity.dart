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

  static Future<RemotePeerInfo> create({required int eloRating}) async {
    assert(eloRating >= 100 && eloRating <= 4000);
    final (BaseDeviceInfo device, PackageInfo package) = await (
      DeviceInfoPlugin().deviceInfo,
      PackageInfo.fromPlatform(),
    ).wait;
    final Map<String, dynamic> data = device.data;
    final String label = labelFromDeviceData(
      data,
      platform: defaultTargetPlatform,
      isWeb: kIsWeb,
    );
    return RemotePeerInfo(
      peerId: _uuid.v4(),
      label: label,
      platform: defaultTargetPlatform.name,
      appVersion: package.version,
      appBuild: package.buildNumber,
      eloRating: eloRating,
    );
  }

  @visibleForTesting
  static String labelFromDeviceData(
    Map<String, dynamic> data, {
    required TargetPlatform platform,
    bool isWeb = false,
  }) {
    if (isWeb) {
      final String browser = _browserName(data['browserName']);
      return browser.isEmpty ? 'Web' : 'Web $browser';
    }

    final (String brand, String model) = switch (platform) {
      TargetPlatform.android => (
        _displayBrand(
          _firstNonEmpty(<Object?>[
            data['brand'],
            data['manufacturer'],
            'Android',
          ]),
        ),
        _firstNonEmpty(<Object?>[
          data['model'],
          data['product'],
          data['device'],
        ]),
      ),
      TargetPlatform.iOS => (
        'Apple',
        _firstNonEmpty(<Object?>[
          data['modelName'],
          data['model'],
          data['localizedModel'],
        ]),
      ),
      TargetPlatform.macOS => (
        'Apple',
        _firstNonEmpty(<Object?>[data['modelName'], data['model']]),
      ),
      TargetPlatform.windows => (
        'Windows',
        _firstNonEmpty(<Object?>[data['productName']]),
      ),
      TargetPlatform.linux => (
        'Linux',
        _firstNonEmpty(<Object?>[data['prettyName'], data['name']]),
      ),
      TargetPlatform.fuchsia => (
        'Fuchsia',
        _firstNonEmpty(<Object?>[
          data['productName'],
          data['model'],
          data['name'],
        ]),
      ),
    };
    return _combineBrandAndModel(brand, model);
  }

  static String _combineBrandAndModel(String brand, String model) {
    if (brand.isEmpty) {
      return model.isEmpty ? 'Mill' : model;
    }
    if (model.isEmpty) {
      return brand;
    }
    final String normalizedBrand = _comparisonToken(brand);
    final String normalizedModel = _comparisonToken(model);
    if (normalizedBrand.isNotEmpty &&
        normalizedModel.contains(normalizedBrand)) {
      return model;
    }
    return '$brand $model';
  }

  static String _comparisonToken(String value) =>
      value.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');

  static String _displayBrand(String value) {
    if (value.isEmpty || value != value.toLowerCase()) {
      return value;
    }
    return '${value[0].toUpperCase()}${value.substring(1)}';
  }

  static String _browserName(Object? value) {
    final String raw = _firstNonEmpty(<Object?>[value]);
    if (raw.isEmpty) {
      return '';
    }
    final String name = raw.split('.').last;
    return switch (name) {
      'chrome' => 'Chrome',
      'edge' => 'Edge',
      'firefox' => 'Firefox',
      'opera' => 'Opera',
      'safari' => 'Safari',
      'samsungInternet' => 'Samsung Internet',
      'msie' => 'Internet Explorer',
      'unknown' => '',
      _ => _displayBrand(name),
    };
  }

  static String _firstNonEmpty(Iterable<Object?> values) {
    for (final Object? value in values) {
      final String text = value?.toString().trim() ?? '';
      if (text.isNotEmpty &&
          text.toLowerCase() != 'null' &&
          text.toLowerCase() != 'unknown') {
        return text;
      }
    }
    return '';
  }
}
