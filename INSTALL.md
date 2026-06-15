# Installation

## Flutter app for Android

You can download the Android app from the links below:

[Google Play Store](https://play.google.com/apps/testing/com.calcitem.sanmill)

[F-Droid](https://f-droid.org/packages/com.calcitem.sanmill)

[Cafe Bazaar](https://cafebazaar.ir/app/com.calcitem.sanmill)

[GitHub Actions](https://github.com/calcitem/Sanmill/actions/workflows/flutter.yml?query=is%3Asuccess+branch%3Amaster)

The signing keys of the above sources are different. If the app you installed is from a different source, you need to uninstall the original app and reinstall it.

## Flutter app for Windows

You can run `./flutter-windows-init.sh` and use Android Studio to build or use Microsoft Visual Studio 2022 to build `src\ui\flutter_app\build\windows\sanmill.sln`.

## Flutter app for Linux

You can run the `./flutter-linux-init.sh` script to initialize the Flutter environment, and then use Android Studio or the following commands to build the project:

```shell
cd src/ui/flutter_app
flutter build linux -v
```
