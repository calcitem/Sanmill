// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'online_models.dart';

abstract interface class OnlineSessionStore {
  Future<OnlineRoomSession?> read();

  Future<void> write(OnlineRoomSession session);

  Future<void> delete();
}

class SecureOnlineSessionStore implements OnlineSessionStore {
  SecureOnlineSessionStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const String _key = 'online.friend_match.session.v1';
  final FlutterSecureStorage _storage;

  @override
  Future<OnlineRoomSession?> read() async {
    final String? source = await _storage.read(key: _key);
    if (source == null) {
      return null;
    }
    try {
      final Object? decoded = jsonDecode(source);
      if (decoded is! Map) {
        throw const FormatException('Stored online session must be an object.');
      }
      final OnlineRoomSession session = OnlineRoomSession.fromJson(
        decoded.cast<String, Object?>(),
      );
      if (session.room.expiresAt.isBefore(DateTime.now().toUtc())) {
        await delete();
        return null;
      }
      return session;
    } on Object {
      await delete();
      return null;
    }
  }

  @override
  Future<void> write(OnlineRoomSession session) {
    return _storage.write(key: _key, value: jsonEncode(session.toJson()));
  }

  @override
  Future<void> delete() => _storage.delete(key: _key);
}
