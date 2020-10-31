import '../services/player.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info/package_info.dart';
import '../common/toast.dart';
import '../common/color-consts.dart';
import '../common/config.dart';
import '../services/audios.dart';
import 'edit-page.dart';

class SettingsPage extends StatefulWidget {
  @override
  _SettingsPageState createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  //
  String _version = 'Ver 1.00';

  @override
  void initState() {
    super.initState();
    loadVersionInfo();
  }

  loadVersionInfo() async {
    //
    final packageInfo = await PackageInfo.fromPlatform();
    setState(() {
      _version = 'Version ${packageInfo.version} (${packageInfo.buildNumber})';
    });
  }

  changeDifficult() {
    //
    callback(int stepTime) async {
      //
      Navigator.of(context).pop();

      setState(() {
        Config.stepTime = stepTime;
      });

      Config.save();
    }

    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SizedBox(height: 10),
          RadioListTile(
            activeColor: ColorConsts.Primary,
            title: Text('初级'),
            groupValue: Config.stepTime,
            value: 5000,
            onChanged: callback,
          ),
          Divider(),
          RadioListTile(
            activeColor: ColorConsts.Primary,
            title: Text('中级'),
            groupValue: Config.stepTime,
            value: 15000,
            onChanged: callback,
          ),
          Divider(),
          RadioListTile(
            activeColor: ColorConsts.Primary,
            title: Text('高级'),
            groupValue: Config.stepTime,
            value: 30000,
            onChanged: callback,
          ),
          Divider(),
          SizedBox(height: 56),
        ],
      ),
    );
  }

  switchMusic(bool value) async {
    //
    setState(() {
      Config.bgmEnabled = value;
    });

    if (Config.bgmEnabled) {
      //Audios.loopBgm('bg_music.mp3');
    } else {
      Audios.stopBgm();
    }

    Config.save();
  }

  switchTone(bool value) async {
    //
    setState(() {
      Config.toneEnabled = value;
    });

    Config.save();
  }

  changeName() async {
    //
    final newName = await Navigator.of(context).push(
      MaterialPageRoute(
          builder: (context) =>
              EditPage('棋手姓名', initValue: Player.shared.name)),
    );

    if (newName != null) nameChanged(newName);
  }

  nameChanged(String newName) async {
    //
    setState(() {
      Player.shared.name = newName;
    });

    Player.shared.saveAndUpload();
  }

  showAbout() {
    //
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text('关于「直棋 」', style: TextStyle(color: ColorConsts.Primary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(height: 5),
            Text('版本', style: TextStyle(fontFamily: '')),
            Text('$_version', style: TextStyle(fontFamily: '')),
            SizedBox(height: 15),
            Text('官网', style: TextStyle(fontFamily: '')),
            GestureDetector(
              onTap: () {
                Clipboard.setData(
                  ClipboardData(text: 'http://www.calcitem.com'),
                );
                Toast.toast(context, msg: '网址已复制！');
              },
              child: Text(
                "http://www.calcitem.com",
                style: TextStyle(fontFamily: '', color: Colors.blue),
              ),
            ),
          ],
        ),
        actions: <Widget>[
          FlatButton(
              child: Text('好的'), onPressed: () => Navigator.of(context).pop()),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    //
    final TextStyle headerStyle =
        TextStyle(color: ColorConsts.Secondary, fontSize: 20.0);
    final TextStyle itemStyle = TextStyle(color: ColorConsts.Primary);

    return Scaffold(
      backgroundColor: ColorConsts.LightBackground,
      appBar: AppBar(title: Text('设置')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const SizedBox(height: 10.0),
            Text("人机难度", style: headerStyle),
            const SizedBox(height: 10.0),
            Card(
              color: ColorConsts.BoardBackground,
              elevation: 0.5,
              margin: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 0),
              child: Column(
                children: <Widget>[
                  ListTile(
                    title: Text("游戏难度", style: itemStyle),
                    trailing:
                        Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
                      Text(Config.stepTime <= 5000
                          ? '初级'
                          : Config.stepTime <= 15000 ? '中级' : '高级'),
                      Icon(Icons.keyboard_arrow_right,
                          color: ColorConsts.Secondary),
                    ]),
                    onTap: changeDifficult,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text("声音", style: headerStyle),
            Card(
              color: ColorConsts.BoardBackground,
              margin: const EdgeInsets.symmetric(vertical: 10),
              child: Column(
                children: <Widget>[
                  SwitchListTile(
                    activeColor: ColorConsts.Primary,
                    value: Config.bgmEnabled,
                    title: Text("背景音乐", style: itemStyle),
                    onChanged: switchMusic,
                  ),
                  _buildDivider(),
                  SwitchListTile(
                    activeColor: ColorConsts.Primary,
                    value: Config.toneEnabled,
                    title: Text("提示音效", style: itemStyle),
                    onChanged: switchTone,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text("排行榜", style: headerStyle),
            Card(
              color: ColorConsts.BoardBackground,
              margin: const EdgeInsets.symmetric(vertical: 10),
              child: Column(
                children: <Widget>[
                  ListTile(
                    title: Text("棋手姓名", style: itemStyle),
                    trailing:
                        Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
                      Text(Player.shared.name),
                      Icon(Icons.keyboard_arrow_right,
                          color: ColorConsts.Secondary),
                    ]),
                    onTap: changeName,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text("关于", style: headerStyle),
            Card(
              color: ColorConsts.BoardBackground,
              margin: const EdgeInsets.symmetric(vertical: 10),
              child: Column(
                children: <Widget>[
                  ListTile(
                    title: Text("关于「直棋」", style: itemStyle),
                    trailing:
                        Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
                      Text(_version ?? ''),
                      Icon(Icons.keyboard_arrow_right,
                          color: ColorConsts.Secondary),
                    ]),
                    onTap: showAbout,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 60.0),
          ],
        ),
      ),
    );
  }

  Container _buildDivider() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      width: double.infinity,
      height: 1.0,
      color: ColorConsts.LightLine,
    );
  }
}
