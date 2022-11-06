// This file is part of Sanmill.
// Copyright (C) 2019-2022 The Sanmill developers (see AUTHORS file)
//
// Sanmill is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Sanmill is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'utils.dart';

class GifShare {
  factory GifShare() => _instance ?? GifShare._internal();

  GifShare._internal() {
    _instance = this;
  }

  static GifShare? _instance;

  final WidgetsToImageController controller = WidgetsToImageController();
  final List<Uint8List> pngs = <Uint8List>[];
  final List<img.Image> images = <img.Image>[];
  Uint8List? bytes;

  final int frameRate = 1;

  Future<void> captureView({bool first = false}) async {
    if (first) {
      releaseData();
    }
    final Uint8List? bytes = await controller.capture();
    if (bytes != null) {
      for (int i = 0; i < frameRate; i++) {
        pngs.add(bytes);
      }
    }
  }

  void releaseData() {
    bytes = null;
    pngs.clear();
    images.clear();
  }

  /// Call when "Share GIF" is tapped.
  Future<bool> shareGif() async {
    final img.PngDecoder decoder = img.PngDecoder();

    if (pngs.isNotEmpty) {
      pngs.removeRange(0, 1); // TODO: WAR
    }

    for (final Uint8List data in pngs) {
      final img.Image? decodeImage = decoder.decodeImage(data);
      if (decodeImage != null) {
        images.add(decodeImage);
      }
    }

    final img.Animation animation = img.Animation();
    // ignore: prefer_foreach
    for (final img.Image image in images) {
      image.duration = 2000;
      animation.addFrame(image);
    }
    final List<int>? gifData =
        img.encodeGifAnimation(animation, samplingFactor: 160);
    if (gifData != null) {
      return _writeGifToFile(gifData);
    } else {
      return false;
    }
  }

  Future<bool> _writeGifToFile(List<int> gif) async {
    final String time = DateTime.now().millisecondsSinceEpoch.toString();
    final String gifFileName = "Mill-$time.gif";
    final Directory docDir = await getApplicationDocumentsDirectory();
    final File imgGif = File('${docDir.path}/$gifFileName');
    await imgGif.writeAsBytes(gif);
    Share.shareXFiles(<XFile>[XFile('${docDir.path}/$gifFileName')]);
    return true;
  }
}
