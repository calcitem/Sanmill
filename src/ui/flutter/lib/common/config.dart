import 'profile.dart';

class Config {
  //
  static bool bgmEnabled = false;
  static bool toneEnabled = true;
  static int stepTime = 5000;

  static Future<void> loadProfile() async {
    //
    final profile = await Profile.shared();

    Config.bgmEnabled = profile['bgm-enabled'] ?? false;
    Config.toneEnabled = profile['tone-enabled'] ?? true;
    Config.stepTime = profile['step-time'] ?? 5000;

    return true;
  }

  static Future<bool> save() async {
    //
    final profile = await Profile.shared();

    profile['bgm-enabled'] = Config.bgmEnabled;
    profile['tone-enabled'] = Config.toneEnabled;
    profile['step-time'] = Config.stepTime;

    profile.commit();

    return true;
  }
}