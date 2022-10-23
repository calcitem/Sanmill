import 'package:flutter/material.dart';

import '../generated/intl/l10n.dart';
import '../services/database/database.dart';
import '../shared/custom_drawer/custom_drawer.dart';
import '../shared/theme/app_theme.dart';

class HowToPlayScreen extends StatelessWidget {
  const HowToPlayScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlockSemantics(
      child: Scaffold(
        resizeToAvoidBottomInset: false,
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
      ),
    );
  }
}
