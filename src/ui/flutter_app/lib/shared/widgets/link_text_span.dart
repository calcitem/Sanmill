// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// link_text_span.dart

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/environment_config.dart';

class LinkTextSpan extends TextSpan {
  LinkTextSpan({super.style, required String url, String? text})
      : super(
          text: text ?? url,
          recognizer: TapGestureRecognizer()
            ..onTap = () {
              if (EnvironmentConfig.test == true) {
                return;
              }
              final String s = url.substring("https://".length);
              final String authority = s.substring(0, s.indexOf('/'));
              final String unencodedPath = s.substring(s.indexOf('/'));
              final Uri uri = Uri.https(authority, unencodedPath);
              launchUrl(
                uri,
                mode: LaunchMode.externalApplication,
              );
            },
        );
}
