// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)
//
// Game-neutral hook used by [TgfKernel] to inject game-specific
// payload-extras (Mill marked pieces, future Othello cell-counts, …)
// into the framework-level [GameStateSnapshot.payload] without the
// kernel itself having to know any game's binary layout.
//
// Each game module registers a decoder in its module bootstrap (see
// `MillGameModule`, future `OthelloGameModule` etc.).  The keys produced
// by the decoder show up under `snapshot.payload` and are consumed by
// game-specific accessor extensions, e.g. `GameStateSnapshotMillExt`.

import 'dart:typed_data';

import '../game_id.dart';

/// Implemented by per-game modules to surface game-specific bits of the
/// opaque payload through the framework-level snapshot map.  Returns the
/// key/value pairs that the kernel will splice into
/// `GameStateSnapshot.payload`.
abstract class TgfKernelExtraDecoder {
  Map<String, Object?> decode(Uint8List opaquePayload);
}

/// Process-wide registry of [TgfKernelExtraDecoder]s, keyed by [GameId].
/// Game modules register their decoder during module bootstrap; the
/// kernel consults this registry once per snapshot mapping.
class TgfKernelExtraRegistry {
  TgfKernelExtraRegistry._();

  static final TgfKernelExtraRegistry instance = TgfKernelExtraRegistry._();

  final Map<GameId, TgfKernelExtraDecoder> _decoders =
      <GameId, TgfKernelExtraDecoder>{};

  /// Replace any previously registered decoder for [gameId].
  void register(GameId gameId, TgfKernelExtraDecoder decoder) {
    _decoders[gameId] = decoder;
  }

  /// Look up the decoder for [gameId], or `null` when the game module
  /// has not registered one (e.g. games whose Flutter shell does not
  /// peek inside the opaque payload at all).
  TgfKernelExtraDecoder? decoderFor(GameId gameId) => _decoders[gameId];

  /// Test-only escape hatch.
  void clearForTesting() {
    _decoders.clear();
  }
}
