import 'package:flutter/material.dart';
import 'package:sanmill/common/config.dart';
import 'package:sanmill/generated/l10n.dart';
import 'package:sanmill/style/app_theme.dart';
import 'package:sanmill/style/colors.dart';

class HelpScreen extends StatefulWidget {
  @override
  _HelpScreenState createState() => _HelpScreenState();
}

class _HelpScreenState extends State<HelpScreen> {
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.nearlyWhite,
      child: SafeArea(
        top: false,
        child: Scaffold(
          backgroundColor: Color(Config.darkBackgroundColor),
          body: ListView(
            children: <Widget>[
              AppTheme.sizedBox,
              Container(
                padding: const EdgeInsets.only(
                    top: 48, left: 16, right: 16, bottom: 16),
                child: Text(
                  S.of(context).howToPlay,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: UIColors.burlyWoodColor,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.only(
                    top: 16, left: 16, right: 16, bottom: 16),
                child: Text(
                  S.of(context).helpContent,
                  textAlign: TextAlign.left,
                  style: TextStyle(
                    fontSize: 16,
                    color: UIColors.burlyWoodColor,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
