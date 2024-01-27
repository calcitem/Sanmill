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

part of 'package:sanmill/main.dart';

/// Initializes the given [SystemChrome] ui
void _initUI() {
  // TODO: [Leptopoda] Use layoutBuilder to add adaptiveness
  if (DB().displaySettings.isFullScreen) {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual,
        overlays: <SystemUiOverlay>[]);
  } else {
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarBrightness: Brightness.light,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: Colors.black,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
    );
  }
}

void _initializeScreenOrientation(BuildContext context) {
  if (!isTablet(context)) {
    SystemChrome.setPreferredOrientations(
      <DeviceOrientation>[
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown
      ],
    );
  }
}

const MethodChannel uiMethodChannel = MethodChannel('com.calcitem.sanmill/ui');

Future<void> setWindowTitle(String title) async {
  if (kIsWeb || !Platform.isMacOS) {
    // TODO: Support other desktop platforms.
    return;
  }

  await uiMethodChannel
      .invokeMethod('setWindowTitle', <String, String>{'title': title});
}
