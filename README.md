## Overview

[![Graphic](fastlane/metadata/android/en-US/images/featureGraphic.png)](https://www.youtube.com/channel/UCbGKXwhh1DkuINyZw05kyHw/featured)

<a href="https://github.com/calcitem/Sanmill/actions/workflows/flutter.yml?query=branch%3Amaster+is%3Asuccess+event%3Apush" target="_blank">
<img src="src/ui/flutter_app/assets/badges/get-it-on-github.png" alt="Get it on GitHub" height="80"/></a>

<a href="https://play.google.com/store/apps/details?id=com.calcitem.sanmill" target="_blank">
<img src="https://play.google.com/intl/en_us/badges/images/generic/en-play-badge.png" alt="Get it on Google Play" height="80"/></a>

<a href="https://f-droid.org/packages/com.calcitem.sanmill/" target="_blank">
<img src="src/ui/flutter_app/assets/badges/get-it-on-fdroid.png" alt="Get it on F-Droid" height="80"/></a>

</br>

<a href="https://apps.apple.com/us/app/mill-n-mens-morris/id1662297339?itsct=apps_box_badge&amp;itscg=30200" target="_blank">
<img src="src/ui/flutter_app/assets/badges/download-on-the-app-store-en-us.svg" alt="Download on the App Store" height="54"/></a>

<a href="https://www.microsoft.com/en-us/p/mill-n-mens-morris/9nv3wz4zdtjh" target="_blank">
<img src="src/ui/flutter_app/assets/badges/git-it-from-microsoft-en-us.svg" alt="Get it from the Microsoft Store" height="54"/></a>

<a href="https://snapcraft.io/mill">
  <img alt="Get it from the Snap Store" src="https://snapcraft.io/static/images/badges/en/snap-store-black.svg" />
</a>

<a href="https://cafebazaar.ir/app/com.calcitem.sanmill" target="_blank">
<img src="src/ui/flutter_app/assets/badges/get-it-on-cafebazaar.png" alt="Get it on CafeBazaar" height="54"/></a>

[![snapcraft](https://snapcraft.io/mill/badge.svg)](https://snapcraft.io/mill)

[![Codemagic build status](https://api.codemagic.io/apps/5fafbd77605096975ff9d1ba/5fafbd77605096975ff9d1b9/status_badge.svg)](https://codemagic.io/apps/5fafbd77605096975ff9d1ba/5fafbd77605096975ff9d1b9/latest_build)

[![Translation status](https://hosted.weblate.org/widgets/sanmill/-/svg-badge.svg)](https://hosted.weblate.org/engage/sanmill/)

[![Readme-Chinese](https://img.shields.io/badge/README-简体中文-red.svg)](README-zh_CN.md)

[Sanmill](https://github.com/calcitem/Sanmill) is a free, powerful N men's morris game with a Flutter GUI and a native Rust AI engine. It is distributed under the **GNU General Public License version 3** (GPL v3), ensuring that it remains free software. Users can modify and redistribute the software, provided they adhere to the GPL terms.

[**Nine men's morris**](https://en.wikipedia.org/wiki/Nine_men%27s_morris) is a [strategy](https://en.wikipedia.org/wiki/Abstract_strategy_game) [board game](https://en.wikipedia.org/wiki/Board_games) for two players dating back to the [Roman Empire](https://en.wikipedia.org/wiki/Roman_Empire). The game is also known as **nine-man morris**, **mill**, **mills**, **the mill game**, **merels**, **merrills**, **merelles**, **marelles**, **morelles**, and **ninepenny marl** in English.

![image](https://github.com/calcitem/calcitem/raw/master/Sanmill/res/sanmill.gif)

## Files

This distribution of Sanmill consists of the following files:

* `Readme.md`: The file you are currently reading.
* `Copying.txt`: A text file containing the GNU General Public License version 3.
* `crates`: The Rust/TGF workspace containing the rules engine, search code,
  FRB API crate, and headless CLI.
* `src/ui/flutter_app`: The Flutter frontend.
* `scripts`: Build, test, and repository maintenance scripts.

## Frontend Options

Sanmill's supported frontend is the Flutter app. Debugging and headless
engine work use the Rust CLI in `crates/tgf-cli`.

## How to Build

### Console Engine

```shell
bash scripts/build_console_engine.sh
```

When reporting an issue or a bug, please provide information about the version and compiler used to create your executable. You can obtain this information by running:

```shell
target/release/tgf compiler
```

### Flutter App

To build the Flutter app, run `./flutter-init.sh`, and then use Android Studio or Visual Studio Code to open `src/ui/flutter_app`.
The script automatically provisions Flutter **3.38.7** in `.tools/flutter` when the required SDK
isn't already available on your system, ensuring the repository always uses the expected version.

We use compile-time environment configs to enable specific parts of the code:

* `test` to prepare the app for Monkey and Appium testing. (References to external sites will be disabled.)
* `dev_mode` to show the developer mode without needing to enable it first.
* `catcher` to control the use of Catcher. (Enabled by default; disable if necessary.)

All environment configs can be combined and take boolean values, like:

```shell
flutter run --dart-define catcher=false dev_mode=true
```

Launch configurations for Android Studio or Visual Studio Code are available. Select the needed one in the `Run and Debug` or `Run/Debug Configurations` tab.

### Rust / TGF Engine Workspace

Sanmill is being migrated toward TGF (TabletopGameFramework), a Rust + FRB
framework shared by Mill and future tabletop games.  The Rust workspace lives
under `crates/`:

```shell
cargo test --workspace
cargo clippy --workspace --all-targets --all-features -- -D warnings
```

Mill rules and search are fully implemented in Rust (`crates/tgf-mill`,
`crates/tgf-search`).  The AI uses PVS with aspiration windows, null-move
pruning, MTD(f), MCTS, and iterative deepening.  The perfect database is kept
as a vendored C++ library behind the Rust `perfect-db` wrapper.

The Flutter bridge is generated by flutter_rust_bridge (FRB).  `./flutter-init.sh`
will build the Rust workspace and run FRB code generation when `cargo` and
`flutter_rust_bridge_codegen` are available.  You can also run code generation
manually:

```shell
cd src/ui/flutter_app
flutter_rust_bridge_codegen generate
```

Rust performance smoke results use the same TOML schema as
`tests/perf_baseline.toml`:

```shell
python scripts/record_rust_perf_baseline.py --output target/tgf_perf_result.toml
python scripts/check_perf_baseline.py   --baseline tests/perf_baseline.toml   --result target/tgf_perf_result.toml
```

For the framework API contract, see `docs/FRAMEWORK_API.md`.

## Understanding the Code Base and Participating in the Project

Sanmill's improvements have been a community effort. You can contribute in several ways:

### Improving the Code

* [Sanmill Wiki](https://github.com/calcitem/Sanmill/wiki): Contains explanations of techniques used in Sanmill, with background information.
* [GitHub Repository](https://github.com/calcitem/Sanmill): The latest source can always be found here.
* [Discussions](https://github.com/calcitem/Sanmill/discussions): Join discussions about Sanmill.

## Terms of Use

Sanmill is distributed under the **GNU General Public License version 3** (GPL v3). This allows you to use, modify, and distribute the software, provided you include the full source code or a pointer to where the source can be found. Any changes to the source code must also be made available under the GPL.

For full details, see the GPL v3 in the `Copying.txt` file.

**Note on App Store Distribution**: As an additional permission under section 7 of the GPL v3, you are allowed to distribute the software through app stores, even if they have restrictive terms that are incompatible with the GPL. However, the source code must also be available under the GPL, either through the app store or another channel without those restrictive terms.

All unofficial builds and forks of the app must be clearly labeled as unofficial (e.g., "Sanmill UNOFFICIAL") or use a different name altogether. They must use a different application ID to avoid conflicts with official releases.

## Crash Reporting and Privacy

Sanmill collects non-sensitive crash information to help improve the software. The information collected may include:

- Device type and operating system version
- The actions leading up to the crash
- The crash error message

Users can review the crash report contents before sending. No personally identifiable information (PII) is collected, and all data is anonymized to ensure user privacy. Users can choose not to send crash reports if they prefer.

This data is used solely for improving the quality and stability of Sanmill and is not shared with any third parties.

## Free Software Philosophy

Sanmill is free software, and we emphasize the importance of free software as a matter of freedom. We encourage the use of GPL v3 or later as a license for contributions and discourage the use of non-free licenses.
