// lib/pages/game_lan_page.dart
// ignore_for_file: prefer_final_locals

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../../../shared/services/logger.dart';
import 'game_lan_service.dart';

enum RoomAction { create, join }

class GameLANPage extends StatefulWidget {
  const GameLANPage({super.key});

  @override
  GameLANPageState createState() => GameLANPageState();
}

class GameLANPageState extends State<GameLANPage> {
  GameLANService? _lanService;
  StreamSubscription<String>? _moveSubscription;
  StreamSubscription<bool>? _connectionSubscription;
  bool _isConnected = false;
  String _connectionStatus = "未连接";
  List<InternetAddress> _availableHosts = <InternetAddress>[];
  InternetAddress? _selectedHost;
  String _receivedMessage = "";
  DeviceRole? _currentRole;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showRoomSelectionDialog();
    });
  }

  @override
  void dispose() {
    _moveSubscription?.cancel();
    _connectionSubscription?.cancel();
    _lanService?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("LAN 对战"),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(_connectionStatus),
            if (_isConnected && _selectedHost != null)
              Text(
                "已连接到: ${_selectedHost!.address}",
                style: const TextStyle(color: Colors.green, fontSize: 16),
              ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () async {
                await _showRoomSelectionDialog();
              },
              child: const Text("选择房间操作"),
            ),
            if (_isConnected)
              Column(
                children: <Widget>[
                  ElevatedButton(
                    onPressed: _disconnect,
                    child: const Text("断开连接"),
                  ),
                  ElevatedButton(
                    onPressed: _sendHelloMessage,
                    child: const Text("发送消息"),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _receivedMessage.isNotEmpty
                        ? "收到: $_receivedMessage"
                        : "暂无消息",
                    style: const TextStyle(color: Colors.black, fontSize: 16),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }



  /// Sends a "Hello" message
  Future<void> _sendHelloMessage() async {
    if (_isConnected && _lanService != null) {
      try {
        await _lanService!.sendMessage("Hello from ${_getLocalIP()}");
      } catch (e) {
        _showErrorDialog("发送消息失败: $e");
      }
    } else {
      _showErrorDialog("尚未连接到任何房间。");
    }
  }

  /// Disconnects from the current connection
  Future<void> _disconnect() async {
    await _lanService?.disconnect();
    _moveSubscription?.cancel();
    _connectionSubscription?.cancel();
    setState(() {
      _isConnected = false;
      _connectionStatus = "未连接";
      _selectedHost = null;
      _receivedMessage = "";
      _lanService = null;
      _currentRole = null;
    });
  }

  /// Shows a dialog to choose room action: Create or Join
  Future<void> _showRoomSelectionDialog() async {
    final RoomAction? selectedAction = await showDialog<RoomAction>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("LAN 对战"),
          content: const Text("您想创建一个新房间还是加入一个已有的房间？"),
          actions: <Widget>[
            TextButton(
              child: const Text("创建房间"),
              onPressed: () => Navigator.of(context).pop(RoomAction.create),
            ),
            TextButton(
              child: const Text("加入房间"),
              onPressed: () => Navigator.of(context).pop(RoomAction.join),
            ),
          ],
        );
      },
    );

    if (selectedAction == RoomAction.create) {
      await _handleCreateRoom();
    } else if (selectedAction == RoomAction.join) {
      await _handleJoinRoom();
    } else {
      _showErrorDialog("未选择任何操作，请重试。");
    }
  }

  /// Handles room creation logic
  Future<void> _handleCreateRoom() async {
    try {
      _currentRole = DeviceRole.host;
      _lanService = GameLANService.getInstance(_currentRole!);
      await _lanService!.initialize();

      // Subscribe to streams after initialization
      _moveSubscription = _lanService!.moveStream.listen((String message) {
        setState(() {
          _receivedMessage = message;
        });
      });

      _connectionSubscription = _lanService!.connectionStream.listen((bool isConnected) {
        setState(() {
          _isConnected = isConnected;
          _connectionStatus = isConnected ? "已连接" : "未连接";
          if (!isConnected) {
            _receivedMessage = "";
          }
        });
        if (isConnected) {
          _showConnectedDialog();
        }
      });

      if (!context.mounted) {
        return;
      }

      // Show room creation dialog
      await showDialog<void>(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text("创建房间"),
            content: const Text("房间已创建，等待对手连接..."),
            actions: <Widget>[
              TextButton(
                child: const Text("继续"),
                onPressed: () {
                  Navigator.of(context).pop();
                },
              ),
            ],
          );
        },
      );

      setState(() {
        _connectionStatus = "房间已创建，等待对手连接...";
      });
    } catch (e) {
      logger.e("创建房间时出错: $e");
      _showErrorDialog("创建房间失败，请重试。");
    }
  }

  /// Handles joining a room logic
  Future<void> _handleJoinRoom() async {
    try {
      _currentRole = DeviceRole.client;
      _lanService = GameLANService.getInstance(_currentRole!);
      await _lanService!.initialize();

      // Discover available hosts
      await _discoverHosts();

      if (_availableHosts.isEmpty) {
        _showErrorDialog("未发现可用的房间。");
        return;
      }

      // Select a host to join
      final InternetAddress? selectedAddress = await _showHostSelectionDialog(_availableHosts);
      if (selectedAddress == null) {
        _showErrorDialog("未选择任何房间。");
        return;
      }

      setState(() {
        _selectedHost = selectedAddress;
      });

      // Connect to the selected host
      await _lanService!.connectToHost(selectedAddress);

      // Subscribe to streams after connection
      _moveSubscription = _lanService!.moveStream.listen((String message) {
        setState(() {
          _receivedMessage = message;
        });
      });

      _connectionSubscription = _lanService!.connectionStream.listen((bool isConnected) {
        setState(() {
          _isConnected = isConnected;
          _connectionStatus = isConnected ? "已连接" : "未连接";
          if (!isConnected) {
            _receivedMessage = "";
          }
        });
        if (isConnected) {
          _showConnectedDialog();
        }
      });
    } catch (e) {
      logger.e("加入房间时出错: $e");
      _showErrorDialog("加入房间失败，请重试。");
    }
  }

  /// Discovers available hosts (for Client)
  Future<void> _discoverHosts() async {
    _showDiscoveringDialog();
    final List<InternetAddress> hosts = await _lanService!.discoverHosts();
    if (mounted) {
      Navigator.of(context, rootNavigator: true).pop(); // Close discovering dialog
    }
    setState(() {
      _availableHosts = hosts;
    });
  }

  /// Shows a dialog to select a host from the discovered list
  Future<InternetAddress?> _showHostSelectionDialog(List<InternetAddress> hosts) async {
    return showDialog<InternetAddress>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("选择一个房间"),
          content: SingleChildScrollView(
            child: Column(
              children: hosts.map((InternetAddress address) {
                return ListTile(
                  title: Text(address.address),
                  subtitle: Text('局域网 IP: ${address.address}'),
                  onTap: () {
                    Navigator.pop(context, address);
                  },
                );
              }).toList(),
            ),
          ),
        );
      },
    );
  }

  /// Shows a dialog indicating successful connection
  Future<void> _showConnectedDialog() async {
    await showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("已连接"),
          content: Text(_currentRole == DeviceRole.host
              ? "对手已连接到您的房间。"
              : "成功连接到房主。"),
          actions: <Widget>[
            TextButton(
              child: const Text("确定"),
              onPressed: () {
                Navigator.of(context).pop();
                // Navigate to the game page or continue game logic here
              },
            ),
          ],
        );
      },
    );
  }

  /// Shows a dialog indicating that hosts are being discovered
  void _showDiscoveringDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return const AlertDialog(
          title: Text("发现房间中..."),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              CircularProgressIndicator(),
              SizedBox(height: 20),
              Text("正在搜索局域网中的房间..."),
            ],
          ),
        );
      },
    );
  }

  /// Shows an error dialog with the provided message
  Future<void> _showErrorDialog(String message) async {
    await showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("错误"),
          content: Text(message),
          actions: <Widget>[
            TextButton(
              child: const Text("确定"),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  /// Retrieves the local IP address
  Future<String> _getLocalIP() async {
    try {
      List<NetworkInterface> interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      );

      for (final NetworkInterface interface in interfaces) {
        for (final InternetAddress addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4 &&
              !addr.isLoopback &&
              !addr.isLinkLocal) {
            return addr.address;
          }
        }
      }
    } catch (e) {
      logger.e("Error getting local IP: $e");
    }
    return '未知';
  }

}
