// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:async';

import 'package:app_links/app_links.dart';

class OnlineDeepLinkController {
  OnlineDeepLinkController._();

  static final OnlineDeepLinkController instance = OnlineDeepLinkController._();

  final StreamController<Uri> _links = StreamController<Uri>.broadcast(
    sync: true,
  );
  // App-lifetime subscription; the singleton lives until process shutdown.
  // ignore: cancel_subscriptions
  StreamSubscription<Uri>? _subscription;
  Uri? _pending;

  Stream<Uri> get links => _links.stream;

  Uri? get pending => _pending;

  void start() {
    if (_subscription != null) {
      return;
    }
    _subscription = AppLinks().uriLinkStream.listen((Uri uri) {
      _pending = uri;
      _links.add(uri);
    });
  }

  Uri? takePending() {
    final Uri? value = _pending;
    _pending = null;
    return value;
  }

  void consume(Uri uri) {
    if (_pending == uri) {
      _pending = null;
    }
  }
}
