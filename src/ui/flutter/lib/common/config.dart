/*
  FlutterMill, a mill game playing frontend derived from ChessRoad
  Copyright (C) 2019 He Zhaoyun (ChessRoad author)
  Copyright (C) 2019-2020 Calcitem <calcitem@outlook.com>

  FlutterMill is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  FlutterMill is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

import 'profile.dart';

class Config {
  static bool bgmEnabled = false;
  static bool toneEnabled = true;
  static int thinkingTime = 5000;

  static Future<void> loadProfile() async {
    final profile = await Profile.shared();

    Config.bgmEnabled = profile['bgm-enabled'] ?? false;
    Config.toneEnabled = profile['tone-enabled'] ?? true;
    Config.thinkingTime = profile['thinking-time'] ?? 5000;

    return true;
  }

  static Future<bool> save() async {
    final profile = await Profile.shared();

    profile['bgm-enabled'] = Config.bgmEnabled;
    profile['tone-enabled'] = Config.toneEnabled;
    profile['thinking-time'] = Config.thinkingTime;

    profile.commit();

    return true;
  }
}
