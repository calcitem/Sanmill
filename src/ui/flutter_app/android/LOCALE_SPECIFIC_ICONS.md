# Locale-Specific Icons Implementation

This document describes the implementation of locale-specific icons for the Sanmill Android app.

## Overview

The app now supports different icon designs based on the user's locale:
- **Nine Men's Morris**: Default icon for most regions
- **Twelve Men's Morris**: Special icon for specific regions where this variant is more popular

## Supported Locales for Twelve Men's Morris

The following locales use the Twelve Men's Morris icon design:

| Locale | Language/Region | Country/Area |
|--------|----------------|--------------|
| `af` | Afrikaans | South Africa |
| `zu` | Zulu | South Africa |
| `fa` | Persian/Farsi | Iran |
| `si` | Sinhala | Sri Lanka |
| `ko` | Korean | South Korea |
| `id` | Indonesian | Indonesia |
| `zh` | Chinese | China (Simplified & Traditional) |
| `mn` | Mongolian | Mongolia |

## Technical Implementation

### Directory Structure

```
android/app/src/main/res/
├── drawable/                          # Default Nine Men's Morris icons
│   ├── ic_launcher_background.xml
│   ├── ic_launcher_foreground.xml
│   └── ic_launcher_foreground_twelve.xml
├── drawable-v33/                      # Default monochrome icons (Android 13+)
│   ├── ic_launcher_monochrome.xml
│   └── ic_launcher_monochrome_twelve.xml
├── drawable-{locale}/                 # Locale-specific foreground icons
│   └── ic_launcher_foreground.xml     # Twelve Men's Morris design
└── drawable-{locale}-v33/             # Locale-specific monochrome icons
    └── ic_launcher_monochrome.xml     # Twelve Men's Morris design
```

### How Android Selects Icons

Android's resource selection mechanism automatically chooses the appropriate icon based on:

1. **Locale matching**: If the user's device locale matches one of the supported locales (af, zu, fa, si, ko, id, zh, mn), Android will use the Twelve Men's Morris icon from the corresponding `drawable-{locale}/` directory.

2. **Fallback**: For all other locales, Android falls back to the default Nine Men's Morris icon in the `drawable/` directory.

3. **API level**: For Android 13+ devices, the system will also use the appropriate monochrome version from `drawable-{locale}-v33/` or `drawable-v33/`.

### Icon Design Differences

#### Nine Men's Morris (Default)
- Three nested squares
- Straight connecting lines only
- Traditional mill game layout
- Simpler, cleaner design

#### Twelve Men's Morris (Locale-specific)
- Three nested rectangles
- Diagonal connecting lines (key difference)
- Additional connection points
- More complex board layout
- Represents the extended variant of the game

## Benefits

1. **Cultural Relevance**: Shows appropriate game variant for different regions
2. **Automatic Selection**: No user configuration needed - works based on device locale
3. **Backward Compatibility**: Maintains support for all Android versions
4. **Themed Icons**: Full support for Android 13+ Material You theming

## Testing

To test the locale-specific icons:

1. Change your device language to one of the supported locales
2. Install/reinstall the app
3. The appropriate icon should appear automatically
4. On Android 13+, enable themed icons to see the monochrome version

## Maintenance

When adding new locales or updating icons:

1. Create new `drawable-{locale}/` and `drawable-{locale}-v33/` directories
2. Copy the appropriate icon files
3. Update this documentation
4. Test on devices with the target locale

## File Sizes

All icon files are vector drawables (XML), ensuring:
- Small file size (~4KB each)
- Perfect scaling at all resolutions
- No bitmap assets needed
- Efficient APK size impact 