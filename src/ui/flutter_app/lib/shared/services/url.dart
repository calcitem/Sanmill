// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// url.dart

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/constants.dart';
import 'environment_config.dart';
import 'logger.dart';

Future<void> launchURL(BuildContext context, UrlHelper url) async {
  if (EnvironmentConfig.test) {
    return;
  }

  final String rawUrl =
      Localizations.localeOf(context).languageCode.startsWith("zh")
      ? url.baseChinese
      : url.base;

  final String trimmedUrl = rawUrl.trim();
  if (trimmedUrl.isEmpty) {
    logger.e('Unable to launch URL because the provided value is empty.');
    return;
  }

  Uri? uri = Uri.tryParse(trimmedUrl);
  if (uri == null || uri.scheme.isEmpty) {
    uri = Uri.tryParse('https://$trimmedUrl');
  }

  if (uri == null) {
    logger.e('Unable to launch invalid URL: $rawUrl');
    return;
  }

  if (_requiresAuthority(uri) && !uri.hasAuthority) {
    logger.e('Unable to launch URL without a valid host: $rawUrl');
    return;
  }

  final bool launched = await launchUrl(
    uri,
    mode: LaunchMode.externalApplication,
  );
  if (!launched) {
    logger.e('Failed to launch URL: $uri');
  }
}

bool _requiresAuthority(Uri uri) {
  if (!uri.hasScheme) {
    return false;
  }

  switch (uri.scheme.toLowerCase()) {
    case 'http':
    case 'https':
      return true;
    default:
      return false;
  }
}
