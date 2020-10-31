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
