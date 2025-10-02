// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// link_text_span.dart

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/environment_config.dart';
import '../services/logger.dart';

class LinkTextSpan extends TextSpan {
  LinkTextSpan({super.style, required String url, String? text})
    : super(
        text: text ?? url,
        recognizer: TapGestureRecognizer()
          ..onTap = () {
            if (EnvironmentConfig.test == true) {
              return;
            }
            final Uri? uri = _normalize(url);
            if (uri == null) {
              logger.e('Cannot launch invalid link: $url');
              return;
            }
            launchUrl(uri, mode: LaunchMode.externalApplication).then((
              bool launched,
            ) {
              if (!launched) {
                logger.e('Failed to launch URL: $uri');
              }
            });
          },
      );
}

Uri? _normalize(String rawUrl) {
  final String trimmed = rawUrl.trim();
  if (trimmed.isEmpty) {
    return null;
  }

  Uri? uri = Uri.tryParse(trimmed);
  if (uri == null || uri.scheme.isEmpty) {
    uri = Uri.tryParse('https://$trimmed');
  }

  if (uri == null) {
    return null;
  }

  if ((uri.scheme == 'http' || uri.scheme == 'https') && !uri.hasAuthority) {
    return null;
  }

  return uri;
}
