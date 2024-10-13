import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:multicast_dns/multicast_dns.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../shared/services/logger.dart';

enum DeviceRole { host, client }

class GameLANService {
  GameLANService._privateConstructor(this.role);

  static GameLANService? _instance;

  static GameLANService getInstance(DeviceRole role) {
    if (_instance == null || _instance!.role != role) {
      _instance = GameLANService._privateConstructor(role);
    }
    return _instance!;
  }

  static const String _logTag = "[LANService]";

  final DeviceRole role;

  ServerSocket? _serverSocket;
  Socket? _tcpSocket;
  RawDatagramSocket? _udpSocket;
  final StreamController<String> _messageController = StreamController<String>.broadcast();
  Stream<String> get moveStream => _messageController.stream;

  final StreamController<bool> _connectionController = StreamController<bool>.broadcast();
  Stream<bool> get connectionStream => _connectionController.stream;

  final List<InternetAddress> _availableHosts = <InternetAddress>[];
  List<InternetAddress> get availableHosts => _availableHosts;

  static const int _tcpPort = 4567;
  MDnsClient? _mdnsClient;

  Future<void> initialize() async {
    // Request necessary permissions before starting
    if (await _requestLocationPermissions()) {
      if (role == DeviceRole.host) {
        await _startHosting();
      } else {
        await _startDiscovery();
      }
    } else {
      logger.e("$_logTag Location permissions not granted.");
      throw Exception("Location permissions are required for LAN service.");
    }
  }

  /// Requests necessary location permissions for Android 13+ compliance
  Future<bool> _requestLocationPermissions() async {
    // 逐个请求权限，以便于调试和管理
    final permissionStatus = await [
      Permission.locationWhenInUse,
      Permission.locationAlways,
    ].request();

    // 检查是否所有必要的权限都已授予
    bool granted = permissionStatus[Permission.locationWhenInUse]?.isGranted == true ||
        permissionStatus[Permission.locationAlways]?.isGranted == true;

    // 如果权限未授予，提示用户并返回 false
    if (!granted) {
      print("Location permissions are required for the application to function properly.");
      openAppSettings(); // 可选：引导用户打开应用设置手动授予权限
    }

    return granted;
  }


  Future<void> _startHosting() async {
    try {
      _mdnsClient = MDnsClient();
      await _mdnsClient!.start();

      // Set up TCP server
      _serverSocket = await ServerSocket.bind(InternetAddress.anyIPv4, _tcpPort);
      logger.i("$_logTag TCP Server started on port $_tcpPort");

      _serverSocket!.listen((Socket socket) {
        logger.i("$_logTag Client connected from ${socket.remoteAddress.address}:${socket.remotePort}");
        _tcpSocket = socket;
        _connectionController.add(true);

        socket.listen((Uint8List data) {
          final String message = utf8.decode(data).trim();
          logger.i("$_logTag Received message: $message");
          _messageController.add(message);
        }, onDone: () {
          logger.w("$_logTag Client disconnected.");
          _connectionController.add(false);
          _tcpSocket = null;
        });
      });
    } catch (e) {
      logger.e("$_logTag Error starting host: $e");
      rethrow;
    }
  }

  Future<void> _startDiscovery() async {
    try {
      _mdnsClient = MDnsClient();
      await _mdnsClient!.start();

      _mdnsClient!.lookup<PtrResourceRecord>(
        ResourceRecordQuery.serverPointer('_http._tcp.local'),
      ).listen((PtrResourceRecord record) async {
        await for (final SrvResourceRecord srv in _mdnsClient!.lookup<SrvResourceRecord>(
          ResourceRecordQuery.service(record.domainName),
        )) {
          logger.i("$_logTag Found host at ${srv.target}:${srv.port}");
          final InternetAddress address = InternetAddress(srv.target);
          if (!_availableHosts.contains(address)) {
            _availableHosts.add(address);
            logger.i("$_logTag Discovered host: ${srv.target}");
          }
        }
      });
    } catch (e) {
      logger.e("$_logTag Error discovering hosts: $e");
      rethrow;
    }
  }

  Future<void> sendMessage(String message) async {
    if (_tcpSocket != null) {
      _tcpSocket!.write('$message\n');
      logger.i("$_logTag Sent message: $message");
    } else {
      logger.w("$_logTag Not connected to any host.");
      throw Exception("Not connected to any host.");
    }
  }

  /// Disconnects from the current connection
  Future<void> disconnect() async {
    _tcpSocket?.destroy();
    _serverSocket?.close();
    _udpSocket?.close();
    _tcpSocket = null;
    _serverSocket = null;
    _udpSocket = null;
    logger.i("$_logTag Disconnected from current connection.");
  }

  /// Connects to the specified host (for Client)
  Future<void> connectToHost(InternetAddress host, {int port = _tcpPort}) async {
    try {
      _tcpSocket = await Socket.connect(host, port);
      logger.i("$_logTag Connected to host ${host.address}:$port");
      _connectionController.add(true);

      _tcpSocket!.listen((Uint8List data) {
        final String message = utf8.decode(data).trim();
        logger.i("$_logTag Received message: $message");
        _messageController.add(message);
      }, onDone: () {
        logger.w("$_logTag Disconnected from host.");
        _connectionController.add(false);
        _tcpSocket = null;
      });
    } catch (e) {
      logger.e("$_logTag Error connecting to host: $e");
      rethrow;
    }
  }

  /// Discovers available hosts (for Client)
  Future<List<InternetAddress>> discoverHosts() async {
    final List<InternetAddress> discoveredHosts = <InternetAddress>[];

    if (_mdnsClient == null) {
      _mdnsClient = MDnsClient();
      await _mdnsClient!.start();
    }

    await for (final PtrResourceRecord ptr in _mdnsClient!.lookup<PtrResourceRecord>(
      ResourceRecordQuery.serverPointer('_http._tcp.local'),
    )) {
      await for (final SrvResourceRecord srv in _mdnsClient!.lookup<SrvResourceRecord>(
        ResourceRecordQuery.service(ptr.domainName),
      )) {
        logger.i("$_logTag Found host at ${srv.target}:${srv.port}");
        final InternetAddress address = InternetAddress(srv.target);
        if (!discoveredHosts.contains(address)) {
          discoveredHosts.add(address);
        }
      }
    }

    return discoveredHosts;
  }

  void dispose() {
    _mdnsClient?.stop();
    _tcpSocket?.destroy();
    _serverSocket?.close();
    _udpSocket?.close();
    _messageController.close();
    _connectionController.close();
    logger.i("$_logTag LANService disposed.");
  }
}
