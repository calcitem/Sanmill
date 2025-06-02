# Multi-language Support for Mill Game

This directory contains the internationalization (i18n) files for the Mill Game Qt application.

## Supported Languages

- **English** (en) - Default language
- **German** (de) - Deutsch
- **Hungarian** (hu) - Magyar  
- **Simplified Chinese** (zh_CN) - 简体中文

## File Structure

```
translations/
├── languagemanager.h          # Language manager header
├── languagemanager.cpp        # Language manager implementation
├── mill-pro_en.ts            # English translation source
├── mill-pro_de.ts            # German translation source
├── mill-pro_hu.ts            # Hungarian translation source
├── mill-pro_zh_CN.ts         # Chinese translation source
├── mill-pro_en.qm            # English compiled translation (generated)
├── mill-pro_de.qm            # German compiled translation (generated)
├── mill-pro_hu.qm            # Hungarian compiled translation (generated)
├── mill-pro_zh_CN.qm         # Chinese compiled translation (generated)
└── README.md                  # This file
```

## Building Translation Files

### Windows
Run the batch script to compile translation files:
```batch
build_translations.bat
```

### Linux/macOS
Run the shell script to compile translation files:
```bash
chmod +x build_translations.sh
./build_translations.sh
```

### Using CMake
The translation files are automatically built when using CMake:
```bash
mkdir build
cd build
cmake ..
make
```

To update translation files:
```bash
make update_translations
```

## How to Use

### For Users
1. Launch the Mill Game application
2. Go to **Options** menu → **Language**
3. Select your preferred language
4. The interface will be immediately updated to the selected language
5. Your language preference is automatically saved

### For Developers

#### Adding New Translatable Text
1. Wrap user-visible strings with `tr()`:
   ```cpp
   QString message = tr("Game Over");
   ```

2. Update translation files:
   ```bash
   lupdate *.cpp *.h *.ui -ts translations/mill-pro_en.ts
   ```

3. Translate the new strings in all `.ts` files

4. Compile updated translations:
   ```bash
   lrelease translations/*.ts
   ```

#### Adding a New Language
1. Create a new `.ts` file:
   ```bash
   lupdate *.cpp *.h *.ui -ts translations/mill-pro_[LANGUAGE_CODE].ts
   ```

2. Add the language to `LanguageManager`:
   - Add enum value in `languagemanager.h`
   - Add language code mapping in `languagemanager.cpp`
   - Add language name in `getLanguageName()`

3. Update resource file (`gamewindow.qrc`) to include the new `.qm` file

4. Update CMakeLists.txt to include the new translation file

## Language Codes

| Language | Code | Native Name |
|----------|------|-------------|
| English | en | English |
| German | de | Deutsch |
| Hungarian | hu | Magyar |
| Simplified Chinese | zh_CN | 简体中文 |

## Features

- **Automatic Language Detection**: Loads the last selected language on startup
- **Real-time Switching**: Language changes take effect immediately without restart
- **Persistent Settings**: Language preference is saved using QSettings
- **Fallback Support**: Falls back to English if translation files are missing
- **Resource Embedding**: Translation files are embedded in the application binary

## Technical Implementation

### LanguageManager Class
The `LanguageManager` singleton class handles:
- Loading and switching between languages
- Managing QTranslator instances
- Saving/loading language preferences
- Providing language information to the UI

### Integration with Qt
- Uses Qt's standard internationalization framework
- Supports Qt Linguist for professional translation workflow
- Automatically retranslates UI elements when language changes
- Handles both programmatic and UI file translations

## Translation Guidelines

1. **Context is Important**: Provide meaningful context in translation files
2. **Keep it Consistent**: Use consistent terminology throughout
3. **Consider UI Space**: Some languages require more space than others
4. **Test Thoroughly**: Test all languages to ensure UI layout works properly
5. **Use Professional Tools**: Qt Linguist provides a better translation experience than editing XML directly

## Troubleshooting

### Translation Not Loading
- Check if `.qm` files exist in the translations directory
- Verify translation files are included in resources
- Check console output for loading errors

### UI Not Updating
- Ensure `changeEvent()` is properly implemented in windows
- Check if `retranslateUi()` is called after language change
- Verify signal/slot connections for language changes

### Build Errors
- Ensure Qt LinguistTools are installed
- Check CMakeLists.txt for proper Qt version detection
- Verify all translation files are listed correctly

## Contributing

When contributing translations:
1. Use Qt Linguist for editing translation files
2. Test your translations in the actual application
3. Ensure all strings are translated (no "unfinished" entries)
4. Follow the existing translation style and tone
5. Consider cultural differences, not just literal translations 