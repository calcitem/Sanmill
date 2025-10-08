# Flutter UI for Sanmill

This is a N Men's Morris game implemented in Flutter. The following is the directory structure of the project:

```text
├── android
├── assets
│   ├── audios
│   ├── badges
│   ├── files
│   └── licenses
├── build
├── command
├── lib
│   ├── appearance_settings
│   ├── custom_drawer
│   ├── game_page
│   ├── general_settings
│   ├── generated
│   ├── home
│   ├── l10n
│   ├── misc
│   ├── rule_settings
│   └── shared
└── ...
```

## Key Directories

- **android**: Contains the Android-specific implementation and resources.

- **assets**: Holds the various assets used by the application, such as audio files, badges, and licenses.

- **build**: Stores the build output for the Flutter application.

- lib

  : Contains the Dart source code for the application. It is further divided into various subdirectories for different functionalities:

  - **appearance_settings**: Contains the appearance settings related code, including models and widgets.
  - **custom_drawer**: Holds the custom drawer implementation and related widgets.
  - **game_page**: Contains the game page implementation, services, and widgets.
  - **general_settings**: Holds the general settings related code, including models and widgets.
  - **generated**: Stores generated files, such as assets and internationalization files.
  - **home**: Contains the home page implementation.
  - **l10n**: Holds the localization files for different languages.
  - **misc**: Contains miscellaneous code.
  - **rule_settings**: Holds the rule settings related code, including models and widgets.
  - **shared**: Contains shared code, such as config, database, dialogs, services, themes, and utilities.

## Usage

1. Run `flutter pub get` to install the required dependencies.
2. Run `flutter run` to build and run the application on an emulator or a connected device.

For more information on building and running a Flutter application, please refer to the [official Flutter documentation](https://flutter.dev/docs).

## Contributing

Contributions are welcome! Please feel free to submit a pull request or open an issue to report a bug or request a new feature.
