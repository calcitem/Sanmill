// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../generated/intl/l10n.dart';
import '../../../remote_play/bluetooth_adapter.dart';
import '../../../remote_play/bluetooth_transport.dart';
import '../../../remote_play/remote_match_coordinator.dart';
import '../../../remote_play/remote_models.dart';
import '../../../remote_play/remote_transport.dart';
import '../../../shared/services/logger.dart';
import '../../services/mill.dart';

class BluetoothConfigDialog extends StatefulWidget {
  const BluetoothConfigDialog({super.key});

  @override
  State<BluetoothConfigDialog> createState() => _BluetoothConfigDialogState();
}

class _BluetoothConfigDialogState extends State<BluetoothConfigDialog> {
  late RemoteRole _role;
  bool _hostPlaysWhite = true;
  bool _hostActive = false;
  bool _working = false;
  bool _handedOff = false;
  String _status = '';
  List<RemoteEndpoint> _devices = const <RemoteEndpoint>[];
  RemoteEndpoint? _selectedDevice;
  RemoteMatchCoordinator? _coordinator;
  StreamSubscription<RemoteMatchEvent>? _eventsSubscription;
  GameMode? _previousGameMode;

  bool get _supportsHost =>
      !kIsWeb && defaultTargetPlatform != TargetPlatform.linux;

  @override
  void initState() {
    super.initState();
    _role = _supportsHost ? RemoteRole.host : RemoteRole.join;
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
        .createRemoteCoordinator(
          kind: RemoteTransportKind.bluetooth,
          role: _role,
        );
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
            RemoteConnectionState.ready => s.remoteMatchReady,
            _ => _status,
          };
        });
      case RemoteMatchReady():
        _finishHandoff();
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
      case RemotePeerApprovalRequested():
        setState(() => _status = s.remoteWaitingApproval);
      case RemoteMatchUpgradeRequired():
        setState(() => _status = s.remoteProtocolUpgradeRequired);
      case RemoteTakeBackApprovalRequested() ||
          RemoteRestartApprovalRequested() ||
          RemoteOpponentResigned() ||
          RemoteOpponentConnectionChanged() ||
          RemoteOpponentLeft() ||
          RemoteReconnectExhausted() ||
          RemoteOnlineFailure():
        break;
    }
  }

  Future<void> _startHost() async {
    await _run(() async {
      final RemoteMatchCoordinator coordinator = await _ensureCoordinator();
      try {
        await GameController().startRemoteHost(
          coordinator: coordinator,
          hostPlaysWhite: _hostPlaysWhite,
          advertisedLabel: 'Sanmill ${coordinator.localPeer.label}',
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

  Future<void> _scan() async {
    await _run(() async {
      final RemoteMatchCoordinator coordinator = await _ensureCoordinator();
      if (mounted) {
        setState(() {
          _status = S.of(context).bluetoothScanning;
          _devices = const <RemoteEndpoint>[];
          _selectedDevice = null;
        });
      }
      final List<RemoteEndpoint> devices = await coordinator.discover();
      if (!mounted) {
        return;
      }
      setState(() {
        _devices = devices;
        _selectedDevice = devices.isEmpty ? null : devices.first;
        _status = devices.isEmpty ? S.of(context).bluetoothNoDevices : '';
      });
    });
  }

  Future<void> _join() async {
    final RemoteEndpoint? device = _selectedDevice;
    if (device == null) {
      setState(() => _status = S.of(context).bluetoothNoDevices);
      return;
    }
    await _run(() async {
      final RemoteMatchCoordinator coordinator = await _ensureCoordinator();
      setState(() => _status = S.of(context).waiting);
      await coordinator.join(device);
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
    } on BluetoothUnavailableException catch (error) {
      if (mounted) {
        setState(() {
          _status = switch (error.availability) {
            BluetoothAvailability.unauthorized =>
              S.of(context).bluetoothPermissionDenied,
            _ => S.of(context).bluetoothPoweredOff,
          };
        });
      }
    } on Object catch (error, stackTrace) {
      logger.e(
        '[Remote][BLE][UI] operation failed: $error',
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

  Future<void> _changeRole(RemoteRole role) async {
    if (_role == role ||
        _working ||
        _hostActive ||
        (role == RemoteRole.host && !_supportsHost)) {
      return;
    }
    await _run(() async {
      await _disposeCoordinator();
      if (mounted) {
        setState(() {
          _role = role;
          _devices = const <RemoteEndpoint>[];
          _selectedDevice = null;
          _status = '';
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

  @override
  void dispose() {
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
        title: Text(s.bluetoothSettings),
        content: SizedBox(
          key: const Key('bluetooth_dialog_content'),
          width: 320,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                SegmentedButton<RemoteRole>(
                  key: const Key('bluetooth_role_selector'),
                  segments: <ButtonSegment<RemoteRole>>[
                    if (_supportsHost)
                      ButtonSegment<RemoteRole>(
                        value: RemoteRole.host,
                        label: Text(s.host),
                        icon: const Icon(Icons.bluetooth_connected),
                      ),
                    ButtonSegment<RemoteRole>(
                      value: RemoteRole.join,
                      label: Text(s.join),
                      icon: const Icon(Icons.bluetooth_searching),
                    ),
                  ],
                  selected: <RemoteRole>{_role},
                  onSelectionChanged: controlsLocked
                      ? null
                      : (Set<RemoteRole> value) =>
                            unawaited(_changeRole(value.single)),
                ),
                if (!_supportsHost) ...<Widget>[
                  const SizedBox(height: 12),
                  Text(
                    s.bluetoothHostNotSupported,
                    key: const Key('bluetooth_host_unsupported'),
                  ),
                ],
                const SizedBox(height: 16),
                IndexedStack(
                  key: const Key('bluetooth_role_panels'),
                  index: _role == RemoteRole.host ? 0 : 1,
                  alignment: Alignment.topCenter,
                  children: <Widget>[
                    SizedBox(
                      width: double.infinity,
                      child: _supportsHost
                          ? SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(_hostPlaysWhite ? s.white : s.black),
                              value: _hostPlaysWhite,
                              onChanged: controlsLocked
                                  ? null
                                  : (bool value) {
                                      setState(() => _hostPlaysWhite = value);
                                    },
                            )
                          : const SizedBox.shrink(),
                    ),
                    SizedBox(
                      width: double.infinity,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          FilledButton.icon(
                            key: const Key('bluetooth_scan_button'),
                            onPressed: _working ? null : _scan,
                            icon: const Icon(Icons.radar),
                            label: Text(s.bluetoothScan),
                          ),
                          if (_devices.isNotEmpty) ...<Widget>[
                            const SizedBox(height: 12),
                            DropdownButtonFormField<RemoteEndpoint>(
                              key: const Key('bluetooth_device_selector'),
                              initialValue: _selectedDevice,
                              items: _devices
                                  .map(
                                    (
                                      RemoteEndpoint device,
                                    ) => DropdownMenuItem<RemoteEndpoint>(
                                      value: device,
                                      child: Text(
                                        '${device.label}'
                                        '${device.metadata['rssi'] == null ? '' : '  ${device.metadata['rssi']} dBm'}',
                                      ),
                                    ),
                                  )
                                  .toList(growable: false),
                              onChanged: _working
                                  ? null
                                  : (RemoteEndpoint? value) {
                                      setState(() => _selectedDevice = value);
                                    },
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                if (_status.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 16),
                  Text(_status, key: const Key('remote_status_text')),
                ],
                if (_working) ...<Widget>[
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(),
                ],
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
                  ? 'bluetooth_stop_host_button'
                  : _role == RemoteRole.host
                  ? 'bluetooth_host_button'
                  : 'bluetooth_join_button',
            ),
            onPressed: _working
                ? null
                : hosting
                ? _stopHost
                : _role == RemoteRole.host
                ? _startHost
                : _join,
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
