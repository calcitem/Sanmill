// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../game_page/widgets/qr_scanner_page.dart';
import '../generated/intl/l10n.dart';
import '../remote_play/remote_match_controller.dart';
import '../remote_play/remote_models.dart';
import '../shared/widgets/snackbars/scaffold_messenger.dart';
import 'cloud_match_coordinator.dart';
import 'online_deep_links.dart';
import 'online_game_registration.dart';
import 'online_models.dart';
import 'online_room_api.dart';
import 'online_session_store.dart';
import 'online_socket_client.dart';

typedef OnlineSocketClientFactory = OnlineSocketClient Function();

enum _OnlinePageStage { home, busy, joining, waiting, board }

class OnlineFriendGamePage extends StatefulWidget {
  const OnlineFriendGamePage({
    super.key,
    required this.registration,
    this.service,
    this.roomApi,
    this.sessionStore,
    this.socketFactory,
    this.initialInviteUri,
  });

  final OnlineGameRegistration registration;
  final OnlineServiceConfig? service;
  final OnlineRoomApi? roomApi;
  final OnlineSessionStore? sessionStore;
  final OnlineSocketClientFactory? socketFactory;
  final Uri? initialInviteUri;

  @override
  State<OnlineFriendGamePage> createState() => _OnlineFriendGamePageState();
}

class _OnlineFriendGamePageState extends State<OnlineFriendGamePage> {
  _OnlinePageStage _stage = _OnlinePageStage.home;
  OnlineServiceConfig? _service;
  OnlineRoomApi? _roomApi;
  late final OnlineSessionStore _sessionStore;
  late final OnlineSocketClientFactory _socketFactory;
  CloudMatchCoordinator? _coordinator;
  StreamSubscription<RemoteMatchEvent>? _matchSubscription;
  StreamSubscription<Uri>? _linkSubscription;
  OnlineRoomSession? _roomSession;
  OnlineFailure? _failure;
  String? _terminalStatus;

  @override
  void initState() {
    super.initState();
    _sessionStore = widget.sessionStore ?? SecureOnlineSessionStore();
    _socketFactory = widget.socketFactory ?? () => ChannelOnlineSocketClient();
    try {
      _service = widget.service ?? OnlineServiceConfig.fromEnvironment();
      _roomApi =
          widget.roomApi ??
          HttpOnlineRoomApi(
            service: _service!,
            definition: widget.registration.definition,
          );
    } on FormatException {
      _failure = OnlineFailure.serviceUnavailable;
    }
    _linkSubscription = OnlineDeepLinkController.instance.links.listen(
      _handleIncomingUri,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _resumeOrJoin());
  }

  Future<void> _resumeOrJoin() async {
    final Uri? initial =
        widget.initialInviteUri ??
        OnlineDeepLinkController.instance.takePending();
    if (initial != null) {
      await _handleIncomingUri(initial);
      return;
    }
    if (_service == null || _roomApi == null) {
      return;
    }
    try {
      final OnlineRoomSession? saved = await _sessionStore.read();
      if (!mounted || saved == null) {
        return;
      }
      if (saved.serviceBaseUri.origin != _service!.baseUri.origin) {
        await _sessionStore.delete();
        return;
      }
      await _connectSession(saved);
    } on OnlineApiException catch (error) {
      if (mounted) {
        setState(() => _failure = error.failure);
      }
    } on Object {
      if (mounted) {
        setState(() => _failure = OnlineFailure.serviceUnavailable);
      }
    }
  }

  Future<void> _handleIncomingUri(Uri uri) async {
    if (!mounted || _stage == _OnlinePageStage.busy) {
      return;
    }
    OnlineDeepLinkController.instance.consume(uri);
    final OnlineServiceConfig? service = _service;
    if (service == null) {
      setState(() => _failure = OnlineFailure.serviceUnavailable);
      return;
    }
    final OnlineInvite? invite = OnlineInvite.tryParse(uri.toString(), service);
    if (invite == null) {
      setState(() => _failure = OnlineFailure.invalidInvite);
      return;
    }
    await _joinInvite(invite);
  }

  Future<void> _createGame(OnlineSidePreference side) async {
    final OnlineRoomApi? api = _roomApi;
    if (api == null) {
      setState(() => _failure = OnlineFailure.serviceUnavailable);
      return;
    }
    setState(() {
      _stage = _OnlinePageStage.busy;
      _failure = null;
    });
    try {
      final OnlineRoomSession session = await api.createRoom(
        ruleOptions: widget.registration.createRuleOptions(),
        sidePreference: side,
      );
      if (!mounted) {
        return;
      }
      await _connectSession(session);
    } on OnlineApiException catch (error) {
      _showFailure(error.failure);
    } on Object {
      _showFailure(OnlineFailure.serviceUnavailable);
    }
  }

  void _showSessionFailure(OnlineFailure failure, OnlineRoomSession session) {
    if (!mounted) {
      return;
    }
    setState(() {
      _failure = failure;
      _stage = session.role == RemoteRole.host
          ? _OnlinePageStage.waiting
          : _OnlinePageStage.board;
    });
  }

  Future<void> _joinInvite(OnlineInvite invite) async {
    final OnlineRoomApi? api = _roomApi;
    if (api == null) {
      _showFailure(OnlineFailure.serviceUnavailable);
      return;
    }
    setState(() {
      _stage = _OnlinePageStage.joining;
      _failure = null;
    });
    try {
      final OnlineRoomSession session = await api.joinRoom(invite);
      if (!mounted) {
        return;
      }
      await _connectSession(session);
    } on OnlineApiException catch (error) {
      _showFailure(error.failure);
    } on Object {
      _showFailure(OnlineFailure.serviceUnavailable);
    }
  }

  Future<void> _connectSession(OnlineRoomSession session) async {
    unawaited(_matchSubscription?.cancel());
    _matchSubscription = null;
    final OnlineGameDefinition definition = widget.registration.definition;
    if (session.room.appId != definition.appId ||
        session.room.gameId != definition.gameId ||
        session.room.rulesetId != definition.rulesetId) {
      throw const OnlineApiException(OnlineFailure.versionMismatch);
    }
    final CloudMatchCoordinator coordinator = await widget.registration
        .installCoordinator(
          session: session,
          roomApi: _roomApi!,
          socket: _socketFactory(),
          sessionStore: _sessionStore,
        );
    _coordinator = coordinator;
    _roomSession = session;
    _matchSubscription = coordinator.events.listen(_handleMatchEvent);
    if (mounted) {
      setState(() {
        _stage = session.role == RemoteRole.host
            ? _OnlinePageStage.waiting
            : _OnlinePageStage.joining;
        _failure = null;
      });
    }
    try {
      await coordinator.start();
      if (!mounted) {
        return;
      }
      _roomSession = coordinator.roomSession;
      if (coordinator.isConnected) {
        setState(() => _stage = _OnlinePageStage.board);
      } else if (session.role == RemoteRole.host) {
        setState(() => _stage = _OnlinePageStage.waiting);
      }
    } on OnlineApiException catch (error) {
      await _showConnectionFailure(error.failure, session);
    } on Object {
      _showSessionFailure(OnlineFailure.serviceUnavailable, session);
    }
  }

  Future<void> _showConnectionFailure(
    OnlineFailure failure,
    OnlineRoomSession session,
  ) async {
    if (isTerminalOnlineFailure(failure)) {
      await _disposeCoordinator();
      _roomSession = null;
      _showFailure(failure);
    } else {
      _showSessionFailure(failure, session);
    }
  }

  void _handleMatchEvent(RemoteMatchEvent event) {
    if (!mounted) {
      return;
    }
    switch (event) {
      case RemoteMatchReady():
        setState(() {
          _roomSession = _coordinator?.roomSession;
          _stage = _OnlinePageStage.board;
          _failure = null;
        });
        if (!event.resumed) {
          rootScaffoldMessengerKey.currentState?.showSnackBar(
            SnackBar(content: Text(S.of(context).onlineOpponentJoined)),
          );
        }
      case RemoteOnlineFailure():
        setState(() => _failure = event.failure);
      case RemoteMatchActionRejected():
        rootScaffoldMessengerKey.currentState?.showSnackBar(
          SnackBar(content: Text(S.of(context).onlineActionRejected)),
        );
      case RemoteOpponentLeft():
        setState(() => _terminalStatus = S.of(context).onlineOpponentLeft);
      case RemoteOpponentResigned():
        setState(() => _terminalStatus = S.of(context).opponentResignedYouWin);
      case RemoteMatchStateChanged() ||
          RemoteOpponentConnectionChanged() ||
          RemoteReconnectExhausted() ||
          RemotePeerApprovalRequested() ||
          RemoteMatchUpgradeRequired() ||
          RemoteTakeBackApprovalRequested() ||
          RemoteRestartApprovalRequested() ||
          RemoteMatchAborted() ||
          RemoteMatchFailure():
        setState(() {});
    }
  }

  void _showFailure(OnlineFailure failure) {
    if (!mounted) {
      return;
    }
    setState(() {
      _failure = failure;
      _stage = _OnlinePageStage.home;
    });
  }

  Future<void> _showCreateSettings() async {
    final OnlineSidePreference? side =
        await showModalBottomSheet<OnlineSidePreference>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (BuildContext context) =>
              _CreateGameSheet(registration: widget.registration),
        );
    if (side != null && mounted) {
      await _createGame(side);
    }
  }

  Future<void> _showJoinSheet() async {
    final String? source = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext context) => const _JoinGameSheet(),
    );
    if (source == null || !mounted) {
      return;
    }
    final OnlineServiceConfig? service = _service;
    final OnlineInvite? invite = service == null
        ? null
        : OnlineInvite.tryParse(source, service);
    if (invite == null) {
      setState(() => _failure = OnlineFailure.invalidInvite);
      return;
    }
    await _joinInvite(invite);
  }

  Future<void> _cancelWaitingRoom() async {
    final OnlineRoomSession? session = _roomSession;
    if (session == null || _roomApi == null) {
      return;
    }
    try {
      await _roomApi!.cancelRoom(session);
    } on OnlineApiException catch (error) {
      if (error.failure != OnlineFailure.roomUnavailable) {
        if (mounted) {
          setState(() => _failure = error.failure);
        }
        return;
      }
    }
    await _sessionStore.delete();
    await _disposeCoordinator();
    if (mounted) {
      setState(() {
        _roomSession = null;
        _stage = _OnlinePageStage.home;
      });
    }
  }

  Future<void> _leaveGame() async {
    await _disposeCoordinator(leave: true);
    if (mounted) {
      setState(() {
        _roomSession = null;
        _terminalStatus = null;
        _stage = _OnlinePageStage.home;
      });
    }
  }

  Future<void> _disposeCoordinator({bool leave = false}) async {
    final StreamSubscription<RemoteMatchEvent>? subscription =
        _matchSubscription;
    final CloudMatchCoordinator? coordinator = _coordinator;
    _matchSubscription = null;
    unawaited(subscription?.cancel());
    if (leave) {
      await coordinator?.leave();
    }
    await widget.registration.disposeCoordinator();
    if (identical(_coordinator, coordinator)) {
      _coordinator = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_stage == _OnlinePageStage.board && _coordinator != null) {
      return _buildBoard();
    }
    final S s = S.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(s.onlineFriendGame)),
      body: SafeArea(
        child: switch (_stage) {
          _OnlinePageStage.busy => _ProgressBody(label: s.onlineCreatingGame),
          _OnlinePageStage.joining => _ProgressBody(label: s.onlineJoiningGame),
          _OnlinePageStage.waiting => _buildWaiting(),
          _OnlinePageStage.home || _OnlinePageStage.board => _buildHome(),
        },
      ),
    );
  }

  Widget _buildHome() {
    final S s = S.of(context);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const SizedBox(height: 16),
                  Icon(
                    Icons.cloud_outlined,
                    size: 64,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    s.onlineFriendGameDescription,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          const Icon(Icons.info_outline),
                          const SizedBox(width: 12),
                          Expanded(child: Text(s.onlineServiceDisclosure)),
                        ],
                      ),
                    ),
                  ),
                  if (_failure != null) ...<Widget>[
                    const SizedBox(height: 12),
                    Semantics(
                      liveRegion: true,
                      child: Card(
                        color: Theme.of(context).colorScheme.errorContainer,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(_failureText(s, _failure!)),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    key: const Key('online_create_game'),
                    onPressed: _roomApi == null ? null : _showCreateSettings,
                    icon: const Icon(Icons.add_circle_outline),
                    label: Text(s.onlineCreateGame),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    key: const Key('online_join_game'),
                    onPressed: _roomApi == null ? null : _showJoinSheet,
                    icon: const Icon(Icons.link),
                    label: Text(s.onlineJoinGame),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildWaiting() {
    final S s = S.of(context);
    final OnlineRoomSession? session = _roomSession;
    final Uri? invite = session?.inviteUri;
    if (session == null || invite == null) {
      return _ProgressBody(label: s.onlineSynchronizing);
    }
    final double qrSize = MediaQuery.sizeOf(
      context,
    ).shortestSide.clamp(180.0, 300.0);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Semantics(
                liveRegion: true,
                child: Text(
                  s.onlineWaitingForOpponent,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              const SizedBox(height: 8),
              Text(s.onlineInviteInstruction, textAlign: TextAlign.center),
              const SizedBox(height: 20),
              Center(
                child: Semantics(
                  label: s.shareQrCode,
                  image: true,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: QrImageView(
                        data: invite.toString(),
                        size: qrSize,
                        backgroundColor: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SelectableText(
                invite.toString(),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  OutlinedButton.icon(
                    onPressed: () => _copyInvite(invite),
                    icon: const Icon(Icons.copy_outlined),
                    label: Text(s.onlineCopyInviteLink),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: () => SharePlus.instance.share(
                      ShareParams(text: invite.toString()),
                    ),
                    icon: const Icon(Icons.share_outlined),
                    label: Text(s.onlineShareInviteLink),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              if (_coordinator?.state == RemoteConnectionState.reconnecting)
                _WaitingConnectionCard(label: s.onlineReconnecting, retry: null)
              else if (_coordinator?.state == RemoteConnectionState.error)
                _WaitingConnectionCard(
                  label: _failure == null
                      ? s.onlineReconnectFailed
                      : _failureText(s, _failure!),
                  retry: _coordinator!.retryConnection,
                ),
              if (_coordinator?.state == RemoteConnectionState.reconnecting ||
                  _coordinator?.state == RemoteConnectionState.error)
                const SizedBox(height: 16),
              Card(
                color: Theme.of(context).colorScheme.secondaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Icon(Icons.privacy_tip_outlined),
                      const SizedBox(width: 10),
                      Expanded(child: Text(s.onlineInvitePrivacyNotice)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _MatchSummary(
                session: session,
                registration: widget.registration,
              ),
              const SizedBox(height: 16),
              TextButton(onPressed: _cancelWaitingRoom, child: Text(s.cancel)),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _copyInvite(Uri invite) async {
    await Clipboard.setData(ClipboardData(text: invite.toString()));
    if (mounted) {
      rootScaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(content: Text(S.of(context).onlineInviteLinkCopied)),
      );
    }
  }

  Widget _buildBoard() {
    final CloudMatchCoordinator coordinator = _coordinator!;
    return ValueListenableBuilder<RemoteConnectionState>(
      valueListenable: coordinator.stateNotifier,
      builder:
          (
            BuildContext context,
            RemoteConnectionState connection,
            Widget? child,
          ) {
            final bool locked = connection != RemoteConnectionState.ready;
            return Stack(
              fit: StackFit.expand,
              children: <Widget>[
                widget.registration.buildBoard(context),
                if (locked)
                  _ConnectionOverlay(
                    state: connection,
                    terminalStatus: _terminalStatus,
                    onRetry: coordinator.retryConnection,
                    onLeave: _leaveGame,
                  ),
              ],
            );
          },
    );
  }

  @override
  void dispose() {
    unawaited(_linkSubscription?.cancel());
    if (_coordinator != null) {
      unawaited(_disposeCoordinator());
    } else {
      unawaited(_matchSubscription?.cancel());
    }
    super.dispose();
  }
}

class _CreateGameSheet extends StatefulWidget {
  const _CreateGameSheet({required this.registration});

  final OnlineGameRegistration registration;

  @override
  State<_CreateGameSheet> createState() => _CreateGameSheetState();
}

class _CreateGameSheetState extends State<_CreateGameSheet> {
  OnlineSidePreference _side = OnlineSidePreference.random;

  @override
  Widget build(BuildContext context) {
    final S s = S.of(context);
    final Map<String, Object?> ruleOptions = widget.registration
        .createRuleOptions();
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              s.onlineFriendGameSettings,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.grid_3x3),
              title: Text(s.variant),
              subtitle: Text(
                widget.registration.variantLabel(context, ruleOptions),
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.timer_outlined),
              title: Text(s.unlimited),
            ),
            const SizedBox(height: 8),
            Text(s.side, style: Theme.of(context).textTheme.titleMedium),
            RadioGroup<OnlineSidePreference>(
              groupValue: _side,
              onChanged: (OnlineSidePreference? value) {
                if (value != null) {
                  setState(() => _side = value);
                }
              },
              child: Column(
                children: <Widget>[
                  RadioListTile<OnlineSidePreference>(
                    value: OnlineSidePreference.first,
                    title: Text(s.onlinePlayFirst),
                  ),
                  RadioListTile<OnlineSidePreference>(
                    value: OnlineSidePreference.second,
                    title: Text(s.onlinePlaySecond),
                  ),
                  RadioListTile<OnlineSidePreference>(
                    value: OnlineSidePreference.random,
                    title: Text(s.onlineRandomSide),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(_side),
              child: Text(s.onlineCreateGame),
            ),
          ],
        ),
      ),
    );
  }
}

class _JoinGameSheet extends StatefulWidget {
  const _JoinGameSheet();

  @override
  State<_JoinGameSheet> createState() => _JoinGameSheetState();
}

class _JoinGameSheetState extends State<_JoinGameSheet> {
  final TextEditingController _controller = TextEditingController();

  Future<void> _paste() async {
    final ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null) {
      _controller.text = data!.text!;
    }
  }

  Future<void> _scan() async {
    final String? value = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(builder: (_) => const QrScannerPage()),
    );
    if (value != null && mounted) {
      Navigator.of(context).pop(value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final S s = S.of(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              s.onlineJoinGame,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('online_invite_field'),
              controller: _controller,
              keyboardType: TextInputType.url,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: s.onlinePasteInviteLink,
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  tooltip: s.onlinePasteInviteLink,
                  onPressed: _paste,
                  icon: const Icon(Icons.content_paste),
                ),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _scan,
              icon: const Icon(Icons.qr_code_scanner),
              label: Text(s.scanQrCode),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(_controller.text),
              child: Text(s.join),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

class _MatchSummary extends StatelessWidget {
  const _MatchSummary({required this.session, required this.registration});

  final OnlineRoomSession session;
  final OnlineGameRegistration registration;

  @override
  Widget build(BuildContext context) {
    final S s = S.of(context);
    return Card(
      child: Column(
        children: <Widget>[
          ListTile(
            leading: const Icon(Icons.grid_3x3),
            title: Text(s.variant),
            trailing: Text(
              registration.variantLabel(context, session.room.ruleOptions),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.swap_horiz),
            title: Text(s.side),
            trailing: Text(
              session.localSeat == RemoteSeat.first
                  ? s.onlinePlayFirst
                  : s.onlinePlaySecond,
            ),
          ),
          ListTile(
            leading: const Icon(Icons.timer_outlined),
            title: Text(s.unlimited),
          ),
        ],
      ),
    );
  }
}

class _ProgressBody extends StatelessWidget {
  const _ProgressBody({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Semantics(
        liveRegion: true,
        label: label,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(label),
          ],
        ),
      ),
    );
  }
}

class _ConnectionOverlay extends StatelessWidget {
  const _ConnectionOverlay({
    required this.state,
    required this.onRetry,
    required this.onLeave,
    this.terminalStatus,
  });

  final RemoteConnectionState state;
  final String? terminalStatus;
  final Future<void> Function() onRetry;
  final Future<void> Function() onLeave;

  @override
  Widget build(BuildContext context) {
    final S s = S.of(context);
    final bool failed = state == RemoteConnectionState.error;
    final bool ended = state == RemoteConnectionState.ended;
    final String label =
        terminalStatus ??
        (failed
            ? s.onlineReconnectFailed
            : ended
            ? s.onlineOpponentLeft
            : state == RemoteConnectionState.listening
            ? s.onlineOpponentDisconnected
            : state == RemoteConnectionState.reconnecting
            ? s.onlineReconnecting
            : s.onlineSynchronizing);
    return ColoredBox(
      color: Colors.black54,
      child: Center(
        child: Semantics(
          liveRegion: true,
          label: label,
          child: Card(
            margin: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    if (!failed && !ended) const CircularProgressIndicator(),
                    if (!failed && !ended) const SizedBox(height: 16),
                    Text(label, textAlign: TextAlign.center),
                    if (failed) ...<Widget>[
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: onRetry,
                        child: Text(s.onlineRetryConnection),
                      ),
                    ],
                    if (failed || ended) ...<Widget>[
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: onLeave,
                        child: Text(s.onlineLeaveGame),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WaitingConnectionCard extends StatelessWidget {
  const _WaitingConnectionCard({required this.label, required this.retry});

  final String label;
  final Future<void> Function()? retry;

  @override
  Widget build(BuildContext context) {
    final S s = S.of(context);
    return Semantics(
      liveRegion: true,
      label: label,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: <Widget>[
              if (retry == null) const CircularProgressIndicator(),
              if (retry == null) const SizedBox(height: 12),
              Text(label, textAlign: TextAlign.center),
              if (retry != null) ...<Widget>[
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: retry,
                  child: Text(s.onlineRetryConnection),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

String _failureText(S s, OnlineFailure failure) => switch (failure) {
  OnlineFailure.invalidInvite => s.onlineInvalidInvite,
  OnlineFailure.inviteExpired => s.onlineInviteExpired,
  OnlineFailure.inviteAlreadyUsed => s.onlineInviteAlreadyUsed,
  OnlineFailure.roomUnavailable => s.onlineRoomUnavailable,
  OnlineFailure.roomFull => s.onlineRoomFull,
  OnlineFailure.versionMismatch => s.onlineVersionMismatch,
  OnlineFailure.serviceUnavailable ||
  OnlineFailure.unauthorized ||
  OnlineFailure.protocolError => s.onlineServiceUnavailable,
};
