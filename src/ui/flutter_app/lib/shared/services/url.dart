// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// url.dart

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/constants.dart';
import 'environment_config.dart';

Future<void> launchURL(BuildContext context, UrlHelper url) async {
  if (EnvironmentConfig.test) {
    return;
  }

  final String urlString =
      Localizations.localeOf(context).languageCode.startsWith("zh")
          ? url.baseChinese.substring("https://".length)
          : url.base.substring("https://".length);
  final String authority = urlString.substring(0, urlString.indexOf('/'));
  final String unencodedPath = urlString.substring(urlString.indexOf('/'));
  final Uri uri = Uri.https(authority, unencodedPath);

  await launchUrl(uri, mode: LaunchMode.externalApplication);
}
