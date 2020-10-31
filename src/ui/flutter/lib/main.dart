import 'dart:io';

import 'package:flutter/services.dart';

import './routes/main-menu.dart';
import 'package:flutter/material.dart';

import 'services/audios.dart';
import 'services/player.dart';

void main() {
  //
  runApp(SanmillApp());

  SystemChrome.setPreferredOrientations(
    [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown],
  );

  if (Platform.isAndroid) {
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(statusBarColor: Colors.transparent),
    );
  }

  SystemChrome.setEnabledSystemUIOverlays([]);
}

class SanmillApp extends StatefulWidget {
  //
  static const StatusBarHeight = 28.0;

  @override
  _SanmillAppState createState() => _SanmillAppState();
}

class _SanmillAppState extends State<SanmillApp> {
  //
  @override
  void initState() {
    super.initState();
    //Audios.loopBgm('bg_music.mp3');
    Player.loadProfile();
  }

  @override
  Widget build(BuildContext context) {
    //
    return MaterialApp(
      theme: ThemeData(primarySwatch: Colors.brown),
      debugShowCheckedModeBanner: false,
      home: WillPopScope(
        onWillPop: () async {
          Audios.release();
          return true;
        },
        child: MainMenu(),
      ),
    );
  }
}
