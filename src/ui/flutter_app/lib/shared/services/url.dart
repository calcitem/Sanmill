// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

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

  final String rawUrl = Localizations.localeOf(context)
          .languageCode
          .startsWith("zh")
      ? url.baseChinese
      : url.base;

  final String normalizedUrl =
      rawUrl.contains('://') ? rawUrl : 'https://$rawUrl';

  final Uri? uri = Uri.tryParse(normalizedUrl);
  if (uri == null || uri.host.isEmpty) {
    logger.e('Unable to launch invalid URL: $rawUrl');
    return;
  }

  await launchUrl(uri, mode: LaunchMode.externalApplication);
}
