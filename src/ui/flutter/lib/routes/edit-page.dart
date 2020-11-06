import 'package:flutter/material.dart';

import '../common/color-consts.dart';

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
      borderSide: BorderSide(color: ColorConst.secondaryColor),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, style: TextStyle(fontFamily: '')),
        actions: <Widget>[
          FlatButton(
            child: Text('确定',
                style: TextStyle(fontFamily: '', color: Colors.white)),
            onPressed: () => onSubmit(_textController.text),
          )
        ],
      ),
      backgroundColor: ColorConst.lightBackgroundColor,
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
                  color: ColorConst.primaryColor, fontSize: 16, fontFamily: ''),
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
