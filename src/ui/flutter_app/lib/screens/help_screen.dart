import 'package:flutter/material.dart';
import 'package:sanmill/generated/intl/l10n.dart';
import 'package:sanmill/services/database/database.dart';
import 'package:sanmill/shared/custom_drawer/custom_drawer.dart';
import 'package:sanmill/shared/theme/app_theme.dart';

class HelpScreen extends StatelessWidget {
  const HelpScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        elevation: 0.0,
        backgroundColor: DB().colorSettings.darkBackgroundColor,
        leading: DrawerIcon.of(context)?.icon,
        title: Text(
          S.of(context).howToPlay,
          style: AppTheme.helpTextStyle,
        ),
        iconTheme: const IconThemeData(
          color: AppTheme.helpTextColor,
        ),
      ),
      backgroundColor: DB().colorSettings.darkBackgroundColor,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Text(
          S.of(context).helpContent,
          style: AppTheme.helpTextStyle,
        ),
      ),
    );
  }
}
