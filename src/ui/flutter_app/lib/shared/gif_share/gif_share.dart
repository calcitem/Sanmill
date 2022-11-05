import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
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
  final String gifFileName = "share.gif";

  final int frameRate = 5;

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

  /// 用户点动图分享的时候调用
  Future<bool> shareGif() async {
    final img.PngDecoder decoder = img.PngDecoder();
    for (final Uint8List data in pngs) {
      final img.Image? decodeImage = decoder.decodeImage(data);
      if (decodeImage != null) {
        images.add(decodeImage);
      }
    }

    final img.Animation animation = img.Animation();
    images.forEach((img.Image image) {
      animation.addFrame(image);
    });
    final List<int>? gifData =
        img.encodeGifAnimation(animation, samplingFactor: 160);
    if (gifData != null) {
      return _writeGifToFile(gifData);
    } else {
      return false;
    }
  }

  Future<bool> _writeGifToFile(List<int> gif) async {
    final PermissionStatus status = await Permission.storage.request();
    if (status == PermissionStatus.granted) {
      final Directory docDir = await getTemporaryDirectory();
      final File imgGif = File('${docDir.path}/$gifFileName');
      await imgGif.writeAsBytes(gif);
      Share.shareFiles(['${docDir.path}/$gifFileName']);
      return true;
    } else {
      return false;
    }
  }
}
