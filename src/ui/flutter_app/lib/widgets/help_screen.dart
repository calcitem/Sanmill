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
      color: UIColors.nearlyWhite,
      child: SafeArea(
        top: false,
        child: Scaffold(
          backgroundColor: Color(Config.darkBackgroundColor),
          body: ListView(
            children: <Widget>[
              const SizedBox(height: AppTheme.sizedBoxHeight),
              Container(
                padding: const EdgeInsets.only(
                  top: 48,
                  left: 16,
                  right: 16,
                  bottom: 16,
                ),
                child: Text(
                  S.of(context).howToPlay,
                  style: TextStyle(
                    fontSize: Config.fontSize + 4,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.helpTextColor,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.only(
                  top: 16,
                  left: 16,
                  right: 16,
                  bottom: 16,
                ),
                child: Text(
                  S.of(context).helpContent,
                  style: TextStyle(
                    fontSize: Config.fontSize,
                    color: AppTheme.helpTextColor,
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
