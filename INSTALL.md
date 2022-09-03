# Installation

## Flutter app for Android

You can download the Android app from the links below:

[Google Play Store](https://play.google.com/apps/testing/com.calcitem.sanmill)

[F-Droid](https://f-droid.org/packages/com.calcitem.sanmill)

[GitHub Actions](https://github.com/calcitem/Sanmill/actions/workflows/flutter.yml?query=is%3Asuccess+branch%3Amaster)

The signing keys of the above sources are different. If the app you installed is from a different source, you need to uninstall the original app and reinstall it.

## Flutter app for Windows

You can use Microsoft Visual Studio 2022 to build `src\ui\flutter_app\build\windows\Mill.sln` by yourself.

## Qt Application for Windows

> **Note**
> 
> Qt Application is mainly used for algorithm verification and testing, and there are some bugs in the GUI. Please understand.

Download [Qt Runtime](https://github.com/calcitem/Sanmill-Runtime/archive/master.zip) .

Unzip Sanmill-Runtime-master.zip

Get executable file from [GitHub Actions](https://github.com/calcitem/Sanmill/actions/workflows/qt-on-windows.yml) or [AppVeyor](https://ci.appveyor.com/project/calcitem/sanmill/build/artifacts) .

Put `MillGame.exe` into the `Sanmill-Runtime-master` directory, and click `MillGame.exe` to run.

If you cannot run, try to install [Microsoft Visual C++ Redistributable packages for Visual Studio 2015, 2017, 2019, and 2022](https://docs.microsoft.com/en-US/cpp/windows/latest-supported-vc-redist?view=msvc-170). Download [vc_redist.x64.exe](https://aka.ms/vs/17/release/vc_redist.x64.exe) and install it.
