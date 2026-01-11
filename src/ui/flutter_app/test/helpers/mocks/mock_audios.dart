// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// mock_audios.dart

import 'package:mockito/mockito.dart';
import 'package:sanmill/game_page/services/mill.dart';

class MockAudios extends Mock implements SoundManager {
  @override
  Future<void> loadSounds() async {}

  @override
  void disposePool() {}

  @override
  Future<void> playTone(Sound sound) async {}

  @override
  void mute() {}

  @override
  void unMute() {}
}
