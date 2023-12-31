// This file is part of Sanmill.
// Copyright (C) 2019-2024 The Sanmill developers (see AUTHORS file)
//
// Sanmill is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Sanmill is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

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
