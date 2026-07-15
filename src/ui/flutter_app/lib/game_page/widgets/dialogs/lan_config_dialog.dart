// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../../generated/intl/l10n.dart';
import '../../../remote_play/lan_transport.dart';
import '../../../remote_play/remote_match_coordinator.dart';
import '../../../remote_play/remote_models.dart';
import '../../../remote_play/remote_transport.dart';
import '../../../shared/services/logger.dart';
import '../../services/mill.dart';

class LanConfigDialog extends StatefulWidget {
  const LanConfigDialog({super.key});

  @override
  State<LanConfigDialog> createState() => _LanConfigDialogState();
}

class _LanConfigDialogState extends State<LanConfigDialog> {
  static const int _defaultPort = 33333;

  final TextEditingController _addressController = TextEditingController(
    text: '127.0.0.1',
  );
  final TextEditingController _portController = TextEditingController(
    text: '$_defaultPort',
  );

  RemoteRole _role = RemoteRole.host;
  bool _hostPlaysWhite = true;
  bool _hostActive = false;
  bool _working = false;
  bool _handedOff = false;
  String? _selectedBindAddress;
  String _status = '';
  List<String> _localAddresses = const <String>[];
  List<RemoteEndpoint> _discovered = const <RemoteEndpoint>[];
  RemoteEndpoint? _selectedEndpoint;
  RemoteMatchCoordinator? _coordinator;
  StreamSubscription<RemoteMatchEvent>? _eventsSubscription;
  GameMode? _previousGameMode;

  @override
  void initState() {
    super.initState();
    unawaited(_loadInterfaces());
  }

  Future<void> _loadInterfaces() async {
    try {
      final List<String> addresses = await LanTransport.getLocalIpAddresses();
      if (!mounted) {
        return;
      }
      setState(() {
        _localAddresses = addresses;
        _selectedBindAddress = addresses.isEmpty ? null : addresses.first;
      });
    } on Object catch (error, stackTrace) {
      logger.e(
        '[Remote][LAN][UI] interface lookup failed: $error',
        stackTrace: stackTrace,
      );
    }
  }

  Future<RemoteMatchCoordinator> _ensureCoordinator() async {
    final RemoteMatchCoordinator? current = _coordinator;
    if (current != null && current.transport.role == _role) {
      return current;
    }
    await _disposeCoordinator();
    final GameController controller = GameController();
    _previousGameMode ??= controller.gameInstance.gameMode;
    final RemoteMatchCoordinator coordinator = await controller
        .createRemoteCoordinator(kind: RemoteTransportKind.lan, role: _role);
    _coordinator = coordinator;
    _eventsSubscription = coordinator.events.listen(_onMatchEvent);
    return coordinator;
  }

  void _onMatchEvent(RemoteMatchEvent event) {
    if (!mounted) {
      return;
    }
    final S s = S.of(context);
    switch (event) {
      case RemoteMatchStateChanged():
        setState(() {
          _status = switch (event.state) {
            RemoteConnectionState.listening =>
              s.startedHostingGameWaitingForPlayersToJoin,
            RemoteConnectionState.awaitingApproval => s.remoteWaitingApproval,
            RemoteConnectionState.negotiating => s.remoteNegotiating,
            RemoteConnectionState.reconnecting =>
              s.remoteReconnectingBoardLocked,
            RemoteConnectionState.connecting => s.waiting,
            RemoteConnectionState.ready => s.remoteMatchReady,
            _ => _status,
          };
        });
      case RemotePeerApprovalRequested():
        setState(() => _status = s.remoteWaitingApproval);
      case RemoteMatchReady():
        _finishHandoff();
      case RemoteMatchUpgradeRequired():
        setState(() => _status = s.remoteProtocolUpgradeRequired);
      case RemoteMatchActionRejected():
        setState(() {
          _status =
              const <String>{
                'hostBusy',
                'activeSession',
                'approvalPending',
              }.contains(event.reason)
              ? s.remoteHostBusy
              : s.remotePeerRejected;
        });
      case RemoteMatchFailure():
        setState(() => _status = s.remoteConnectionFailed('${event.error}'));
      case RemoteMatchAborted():
        setState(() {
          _status = event.reason.startsWith('Reconnect timed out')
              ? s.remoteReconnectTimedOut
              : s.remoteConnectionFailed(event.reason);
        });
      case RemoteTakeBackApprovalRequested() ||
          RemoteRestartApprovalRequested() ||
          RemoteOpponentResigned():
        break;
    }
  }

  Future<void> _startHost() async {
    final int? port = _validPort();
    if (port == null) {
      setState(() => _status = S.of(context).invalidPort);
      return;
    }
    await _run(() async {
      final RemoteMatchCoordinator coordinator = await _ensureCoordinator();
      try {
        await GameController().startRemoteHost(
          coordinator: coordinator,
          hostPlaysWhite: _hostPlaysWhite,
          bindAddress: _selectedBindAddress,
          port: port,
          advertisedLabel: coordinator.localPeer.label,
        );
      } on Object {
        await _disposeCoordinator();
        rethrow;
      }
      if (mounted) {
        setState(() {
          _hostActive = true;
          _status = S.of(context).startedHostingGameWaitingForPlayersToJoin;
        });
      }
    });
  }

  Future<void> _stopHost() async {
    if (!_hostActive) {
      return;
    }
    await _run(() async {
      await _disposeCoordinator();
      if (mounted) {
        setState(() {
          _hostActive = false;
          _status = S.of(context).serverIsStopped;
        });
      }
    });
  }

  Future<void> _discover() async {
    await _run(() async {
      final RemoteMatchCoordinator coordinator = await _ensureCoordinator();
      if (mounted) {
        setState(() {
          _status = S.of(context).discoveringSeconds('5');
          _discovered = const <RemoteEndpoint>[];
          _selectedEndpoint = null;
        });
      }
      final List<RemoteEndpoint> endpoints = await coordinator.discover(
        localAddress: _selectedBindAddress,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _discovered = endpoints;
        _selectedEndpoint = endpoints.isEmpty ? null : endpoints.first;
        _status = endpoints.isEmpty
            ? S.of(context).noHostDiscovered
            : S
                  .of(context)
                  .hostDiscovered(
                    endpoints.first.address ?? endpoints.first.label,
                    '${endpoints.first.port ?? _defaultPort}',
                  );
      });
    });
  }

  Future<void> _connect() async {
    final int? port = _validPort();
    final RemoteEndpoint? discovered = _selectedEndpoint;
    final String address = _addressController.text.trim();
    final RemoteEndpoint endpoint;
    if (discovered != null) {
      endpoint = discovered;
    } else {
      if (InternetAddress.tryParse(address)?.type != InternetAddressType.IPv4) {
        setState(() => _status = S.of(context).invalidIpAddress);
        return;
      }
      if (port == null) {
        setState(() => _status = S.of(context).invalidPort);
        return;
      }
      endpoint = RemoteEndpoint(
        id: '$address:$port',
        label: address,
        address: address,
        port: port,
      );
    }
    await _run(() async {
      final RemoteMatchCoordinator coordinator = await _ensureCoordinator();
      if (mounted) {
        setState(() => _status = S.of(context).waiting);
      }
      await coordinator.join(endpoint);
      if (mounted) {
        setState(() => _status = S.of(context).remoteWaitingApproval);
      }
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_working) {
      return;
    }
    setState(() => _working = true);
    try {
      await action();
    } on RemoteLanVersionMismatchException {
      if (mounted) {
        setState(() => _status = S.of(context).remoteProtocolUpgradeRequired);
      }
    } on Object catch (error, stackTrace) {
      logger.e(
        '[Remote][LAN][UI] operation failed: $error',
        stackTrace: stackTrace,
      );
      if (mounted) {
        setState(() {
          _status = S.of(context).remoteConnectionFailed(error.toString());
        });
      }
    } finally {
      if (mounted) {
        setState(() => _working = false);
      }
    }
  }

  int? _validPort() {
    final int? port = int.tryParse(_portController.text.trim());
    return port != null && port > 0 && port <= 65535 ? port : null;
  }

  Future<void> _disposeCoordinator() async {
    final bool hadCoordinator = _coordinator != null;
    await _eventsSubscription?.cancel();
    _eventsSubscription = null;
    _coordinator = null;
    if (hadCoordinator) {
      await GameController().disposeRemoteMatch();
    }
    _restorePreviousGameMode();
  }

  Future<void> _changeRole(RemoteRole role) async {
    if (_role == role || _working || _hostActive) {
      return;
    }
    await _run(() async {
      await _disposeCoordinator();
      if (mounted) {
        setState(() {
          _role = role;
          _status = '';
          _discovered = const <RemoteEndpoint>[];
          _selectedEndpoint = null;
        });
      }
    });
  }

  void _finishHandoff() {
    if (_handedOff) {
      return;
    }
    setState(() {
      _handedOff = true;
      _hostActive = false;
      _working = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    });
  }

  void _restorePreviousGameMode() {
    final GameMode? previousGameMode = _previousGameMode;
    if (!_handedOff && previousGameMode != null) {
      final GameController controller = GameController();
      if (controller.gameInstance.gameMode != previousGameMode) {
        controller.gameInstance.gameMode = previousGameMode;
      }
    }
  }

  @override
  void dispose() {
    _addressController.dispose();
    _portController.dispose();
    unawaited(_eventsSubscription?.cancel());
    if (!_handedOff) {
      if (_coordinator != null) {
        unawaited(GameController().disposeRemoteMatch());
      }
      _restorePreviousGameMode();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final S s = S.of(context);
    final bool hosting = _role == RemoteRole.host && _hostActive;
    final bool controlsLocked = _working || hosting;
    return PopScope(
      canPop: !controlsLocked || _handedOff,
      child: AlertDialog(
        constraints: const BoxConstraints.tightFor(width: 368),
        title: Text(s.localNetworkSettings),
        content: SizedBox(
          key: const Key('lan_dialog_content'),
          width: 320,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                SegmentedButton<RemoteRole>(
                  key: const Key('lan_role_selector'),
                  segments: <ButtonSegment<RemoteRole>>[
                    ButtonSegment<RemoteRole>(
                      value: RemoteRole.host,
                      label: Text(s.host),
                      icon: const Icon(Icons.wifi_tethering),
                    ),
                    ButtonSegment<RemoteRole>(
                      value: RemoteRole.join,
                      label: Text(s.join),
                      icon: const Icon(Icons.wifi_find),
                    ),
                  ],
                  selected: <RemoteRole>{_role},
                  onSelectionChanged: controlsLocked
                      ? null
                      : (Set<RemoteRole> value) =>
                            unawaited(_changeRole(value.single)),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  key: ValueKey<String?>(_selectedBindAddress),
                  initialValue: _selectedBindAddress,
                  decoration: InputDecoration(labelText: s.serverIp),
                  items: _localAddresses
                      .map(
                        (String address) => DropdownMenuItem<String>(
                          value: address,
                          child: Text(address),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: controlsLocked || _localAddresses.isEmpty
                      ? null
                      : (String? value) {
                          setState(() => _selectedBindAddress = value);
                        },
                ),
                IndexedStack(
                  key: const Key('lan_role_panels'),
                  index: _role == RemoteRole.host ? 0 : 1,
                  alignment: Alignment.topCenter,
                  children: <Widget>[
                    SizedBox(
                      width: double.infinity,
                      child: SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(_hostPlaysWhite ? s.white : s.black),
                        value: _hostPlaysWhite,
                        onChanged: controlsLocked
                            ? null
                            : (bool value) {
                                setState(() => _hostPlaysWhite = value);
                              },
                      ),
                    ),
                    SizedBox(
                      width: double.infinity,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          const SizedBox(height: 12),
                          FilledButton.icon(
                            key: const Key('lan_discover_button'),
                            onPressed: _working ? null : _discover,
                            icon: const Icon(Icons.radar),
                            label: Text(s.discover),
                          ),
                          const SizedBox(height: 12),
                          if (_discovered.isNotEmpty)
                            DropdownButtonFormField<RemoteEndpoint>(
                              initialValue: _selectedEndpoint,
                              decoration: InputDecoration(labelText: s.host),
                              items: _discovered
                                  .map(
                                    (
                                      RemoteEndpoint endpoint,
                                    ) => DropdownMenuItem<RemoteEndpoint>(
                                      value: endpoint,
                                      child: Text(
                                        '${endpoint.label} '
                                        '(${endpoint.address}:${endpoint.port})',
                                      ),
                                    ),
                                  )
                                  .toList(growable: false),
                              onChanged: _working
                                  ? null
                                  : (RemoteEndpoint? value) {
                                      setState(() => _selectedEndpoint = value);
                                    },
                            )
                          else
                            TextField(
                              key: const Key('lan_address_field'),
                              controller: _addressController,
                              enabled: !_working,
                              decoration: InputDecoration(
                                labelText: s.serverIp,
                              ),
                              keyboardType: TextInputType.url,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('lan_port_field'),
                  controller: _portController,
                  enabled: !controlsLocked && _selectedEndpoint == null,
                  decoration: InputDecoration(labelText: s.port),
                  keyboardType: TextInputType.number,
                ),
                ConstrainedBox(
                  key: const Key('lan_status_panel'),
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Align(
                    alignment: Alignment.bottomLeft,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        if (_working)
                          const Padding(
                            padding: EdgeInsets.only(top: 2),
                            child: SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        if (_working && _status.isNotEmpty)
                          const SizedBox(width: 8),
                        if (_status.isNotEmpty)
                          Expanded(
                            child: Text(
                              _status,
                              key: const Key('remote_status_text'),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: controlsLocked
                ? null
                : () => Navigator.of(context).pop(false),
            child: Text(s.close),
          ),
          FilledButton(
            key: Key(
              hosting
                  ? 'lan_stop_host_button'
                  : _role == RemoteRole.host
                  ? 'lan_host_button'
                  : 'lan_join_button',
            ),
            onPressed: _working
                ? null
                : hosting
                ? _stopHost
                : _role == RemoteRole.host
                ? _startHost
                : _connect,
            child: Text(
              hosting
                  ? s.stopHosting
                  : _role == RemoteRole.host
                  ? s.startHosting
                  : s.connect,
            ),
          ),
        ],
      ),
    );
  }
}
