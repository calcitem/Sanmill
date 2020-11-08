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

import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../common/profile.dart';
import 'ranks.dart';

class Player extends RankItem {
  //
  static Player _instance;
  String _uuid;

  static get shared => _instance;

  static Future<Player> loadProfile() async {
    //
    if (_instance == null) {
      _instance = Player();
      await _instance._load();
    }

    return _instance;
  }

  _load() async {
    //
    final profile = await Profile.shared();

    _uuid = profile['player-uuid'];

    if (_uuid == null) {
      profile['player-uuid'] = _uuid = Uuid().v1();
    } else {
      //
      final playerInfoJson = profile['_rank-player-info'] ?? '{}';
      final values = jsonDecode(playerInfoJson);

      name = values['name'] ?? '无名英雄';
      winCloudEngine = values['win_cloud_engine'] ?? 0;
      winPhoneAi = values['win_phone_ai'] ?? 0;
    }
  }

  Player() : super.empty();

  Future<void> increaseWinPhoneAi() async {
    winPhoneAi++;
    await saveAndUpload();
  }

  Future<void> saveAndUpload() async {
    //
    final profile = await Profile.shared();
    profile['_rank-player-info'] = jsonEncode(toMap());
    profile.commit();

    await Ranks.mockUpload(uuid: _uuid, rank: this);
  }
}
