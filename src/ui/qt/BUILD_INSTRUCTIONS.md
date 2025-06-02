# Build Instructions for Multi-language Support

## Prerequisites

### Installing Qt Development Tools
To build the translation files, you need Qt development tools installed:

#### Windows
1. Download Qt from https://www.qt.io/download
2. Install Qt with the "Qt Linguist" component
3. Add Qt tools to your PATH environment variable

#### Linux (Ubuntu/Debian)
```bash
sudo apt-get install qttools5-dev-tools
```

#### macOS (with Homebrew)
```bash
brew install qt5
```

## Building Translation Files

### Method 1: Using Build Scripts (Recommended)

#### Windows
```cmd
build_translations.bat
```

#### Linux/macOS
```bash
chmod +x build_translations.sh
./build_translations.sh
```

### Method 2: Manual Compilation
If you have Qt tools in your PATH:

```bash
lrelease translations/mill-pro_en.ts -qm translations/mill-pro_en.qm
lrelease translations/mill-pro_de.ts -qm translations/mill-pro_de.qm
lrelease translations/mill-pro_hu.ts -qm translations/mill-pro_hu.qm
lrelease translations/mill-pro_zh_CN.ts -qm translations/mill-pro_zh_CN.qm
```

### Method 3: Using CMake (Automatic)
When building the entire project with CMake, translation files are automatically compiled:

```bash
mkdir build
cd build
cmake ..
make  # or nmake on Windows
```

## Testing the Implementation

### 1. Verify Files Structure
After building, ensure these files exist:
```
translations/
├── mill-pro_en.qm
├── mill-pro_de.qm
├── mill-pro_hu.qm
└── mill-pro_zh_CN.qm
```

### 2. Test Language Switching
1. Build and run the application
2. Go to **Options** → **Language**
3. Try switching between different languages
4. Verify that UI text changes immediately
5. Restart the app to ensure language preference is saved

### 3. Check Console Output
If translations fail to load, check the console for error messages like:
```
Failed to load translation file for language: de
```

## Troubleshooting

### Translation Files Not Loading
1. **Check file paths**: Ensure `.qm` files are in the `translations/` directory
2. **Verify resources**: Make sure `gamewindow.qrc` includes the translation files
3. **Rebuild resources**: Clean and rebuild the project to regenerate resources

### lrelease Not Found
1. **Install Qt development tools** (see Prerequisites above)
2. **Add to PATH**: Add Qt bin directory to your system PATH
3. **Use full path**: Specify the full path to lrelease in build scripts

### UI Not Updating
1. **Check MOC**: Ensure the project is built with Qt's MOC (Meta-Object Compiler)
2. **Signal connections**: Verify language change signals are properly connected
3. **Retranslate calls**: Ensure `retranslateUi()` is called after language changes

### Build Errors
1. **Qt version**: Ensure you're using Qt 5.15+ or Qt 6.x
2. **CMake version**: Use CMake 3.10 or later
3. **LinguistTools**: Verify Qt LinguistTools component is installed

## Development Workflow

### Adding New Translatable Text
1. **Mark for translation**: Wrap strings with `tr()`:
   ```cpp
   QString message = tr("Your new text here");
   ```

2. **Update source files**: Run lupdate to extract new strings:
   ```bash
   lupdate *.cpp *.h *.ui -ts translations/mill-pro_en.ts
   ```

3. **Translate**: Open `.ts` files in Qt Linguist or edit manually

4. **Compile**: Run lrelease to generate `.qm` files

5. **Test**: Build and test the application

### Adding New Languages
1. **Create translation file**:
   ```bash
   lupdate *.cpp *.h *.ui -ts translations/mill-pro_[CODE].ts
   ```

2. **Update LanguageManager**: Add new language enum and mappings

3. **Update resources**: Add new `.qm` file to `gamewindow.qrc`

4. **Update build files**: Add to CMakeLists.txt and build scripts

## Current Implementation Status

✅ **Completed**:
- Language management framework
- English, German, Hungarian, Chinese translations
- UI integration with language menu
- Persistent language settings
- Build infrastructure

🔄 **To be done**:
- Complete all UI strings translation
- Test with actual Qt build environment
- Generate proper binary .qm files
- Performance optimization for large translation files

## Notes for Developers

- Translation files (`.ts`) are human-readable XML files
- Compiled files (`.qm`) are binary and optimized for runtime
- Use Qt Linguist for professional translation workflow
- Test all languages to ensure UI layout compatibility
- Consider text expansion when translating to other languages 