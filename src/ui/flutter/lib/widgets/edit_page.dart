/*
  This file is part of Sanmill.
  Copyright (C) 2019-2021 The Sanmill developers (see AUTHORS file)

  Sanmill is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  Sanmill is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

import 'package:flutter/material.dart';
import 'package:sanmill/generated/l10n.dart';
import 'package:sanmill/style/colors.dart';

class EditPage extends StatefulWidget {
  //
  final String title, initValue;
  EditPage(this.title, {this.initValue});

  @override
  _EditPageState createState() => _EditPageState();
}

class _EditPageState extends State<EditPage> {
  //
  TextEditingController _textController;
  FocusNode _commentFocus = FocusNode();

  onSubmit(String input) {
    Navigator.of(context).pop(input);
  }

  @override
  void initState() {
    //
    _textController = TextEditingController();
    _textController.text = widget.initValue;

    Future.delayed(
      Duration(milliseconds: 10),
      () => FocusScope.of(context).requestFocus(_commentFocus),
    );

    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    //
    final inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(25),
      borderSide: BorderSide(color: UIColors.secondaryColor),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, style: TextStyle(fontFamily: '')),
        actions: <Widget>[
          FlatButton(
            child: Text(S.of(context).ok,
                style: TextStyle(fontFamily: '', color: Colors.white)),
            onPressed: () => onSubmit(_textController.text),
          )
        ],
      ),
      backgroundColor: UIColors.lightBackgroundColor,
      body: Container(
        margin: EdgeInsets.all(16),
        child: Column(
          children: <Widget>[
            TextField(
              controller: _textController,
              decoration: InputDecoration(
                contentPadding:
                    EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                enabledBorder: inputBorder,
                focusedBorder: inputBorder,
              ),
              style: TextStyle(
                  color: UIColors.primaryColor, fontSize: 16, fontFamily: ''),
              onSubmitted: (input) => onSubmit(input),
              focusNode: _commentFocus,
            ),
          ],
        ),
      ),
    );
  }

  @override
  void deactivate() {
    FocusScope.of(context).requestFocus(FocusNode());
    super.deactivate();
  }
}
