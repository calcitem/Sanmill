# CustomDrawer Widget API Documentation

## Overview

`CustomDrawer` is the application's navigation drawer that provides access to all main features, settings, and auxiliary pages. It's a customizable, animated drawer with a header, menu items, and responsive design.

**Location**: `lib/custom_drawer/custom_drawer.dart` (library with multiple parts)

**Type**: Composite widget (multiple related components)

**Dependencies**: None (self-contained)

## Architecture

The CustomDrawer is composed of several coordinated widgets:

```
CustomDrawerWidget (main drawer)
  ├── CustomDrawerHeader (header section)
  ├── CustomDrawerItem (menu items)
  ├── CustomDrawerIcon (item icons)
  └── CustomDrawerValue (reactive values)
```

## Main Components

### 1. CustomDrawerWidget

The main drawer container.

**File**: `widgets/custom_drawer_widget.dart`

**Usage**:
```dart
Scaffold(
  drawer: const CustomDrawerWidget(),
  body: YourContent(),
)
```

**Features**:
- Smooth opening/closing animations
- Responsive width (adapts to screen size)
- Scrollable content
- Auto-close on selection

---

### 2. CustomDrawerHeader

The drawer header displaying app branding and info.

**File**: `widgets/custom_drawer_header.dart`

**Features**:
- App logo/icon
- App name with animated text
- Version information
- Gradient background

**Example**:
```dart
CustomDrawerHeader(
  title: S.of(context).appName,
  subtitle: 'Version $appVersion',
)
```

---

### 3. CustomDrawerItem

Individual menu items in the drawer.

**File**: `widgets/custom_drawer_item.dart`

**Constructor**:
```dart
CustomDrawerItem({
  required this.icon,
  required this.title,
  this.subtitle,
  this.onTap,
  this.selected = false,
  Key? key,
})
```

**Parameters**:
- `icon` (IconData): Icon to display
- `title` (String): Item text
- `subtitle` (String?): Optional subtitle
- `onTap` (VoidCallback?): Tap handler
- `selected` (bool): Whether item is currently selected

**Example**:
```dart
CustomDrawerItem(
  icon: FluentIcons.settings_24_regular,
  title: S.of(context).settings,
  onTap: () {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => SettingsPage()),
    );
  },
)
```

---

### 4. CustomDrawerIcon

Styled icon widget for drawer items.

**File**: `widgets/custom_drawer_icon.dart`

**Features**:
- Consistent sizing
- Theme-aware coloring
- Optional badge/indicator

---

### 5. CustomDrawerValue

Reactive value display for drawer items (e.g., current difficulty level).

**File**: `widgets/custom_drawer_value.dart`

**Example**:
```dart
CustomDrawerValue<int>(
  valueListenable: difficultyNotifier,
  builder: (value) => Text('Level: $value'),
)
```

---

## Complete Usage Example

### Basic Drawer Setup

```dart
import 'package:flutter/material.dart';
import '../custom_drawer/custom_drawer.dart';

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: Text('Sanmill')),
        drawer: _buildDrawer(context),
        body: GamePage(),
      ),
    );
  }

  Widget _buildDrawer(BuildContext context) {
    return Drawer(
      child: Column(
        children: [
          // Header
          CustomDrawerHeader(
            title: S.of(context).appName,
            subtitle: 'v7.0.0',
          ),

          // Menu items
          Expanded(
            child: ListView(
              children: [
                CustomDrawerItem(
                  icon: FluentIcons.play_circle_24_regular,
                  title: S.of(context).newGame,
                  onTap: () {
                    Navigator.pop(context);
                    _startNewGame();
                  },
                ),

                CustomDrawerItem(
                  icon: FluentIcons.settings_24_regular,
                  title: S.of(context).generalSettings,
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => GeneralSettingsPage(),
                      ),
                    );
                  },
                ),

                CustomDrawerItem(
                  icon: FluentIcons.color_24_regular,
                  title: S.of(context).appearanceSettings,
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AppearanceSettingsPage(),
                      ),
                    );
                  },
                ),

                const Divider(),

                CustomDrawerItem(
                  icon: FluentIcons.info_24_regular,
                  title: S.of(context).about,
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AboutPage(),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
```

---

## Typical Drawer Structure

```dart
Drawer(
  child: Column(
    children: [
      // 1. Header
      CustomDrawerHeader(...),

      // 2. Scrollable menu
      Expanded(
        child: ListView(
          children: [
            // Game actions
            CustomDrawerItem(icon: play, title: "New Game"),
            CustomDrawerItem(icon: load, title: "Load Game"),
            
            Divider(),
            
            // Settings
            CustomDrawerItem(icon: settings, title: "General"),
            CustomDrawerItem(icon: palette, title: "Appearance"),
            CustomDrawerItem(icon: rules, title: "Rules"),
            
            Divider(),
            
            // Info
            CustomDrawerItem(icon: help, title: "How to Play"),
            CustomDrawerItem(icon: info, title: "About"),
          ],
        ),
      ),
    ],
  ),
)
```

---

## Styling and Theming

### Theme Integration

CustomDrawer automatically adapts to app theme:

```dart
// Light theme: Light background, dark text
// Dark theme: Dark background, light text
```

### Custom Colors

To customize colors, use `Theme`:

```dart
Theme(
  data: Theme.of(context).copyWith(
    drawerTheme: DrawerThemeData(
      backgroundColor: Colors.blue[50],
    ),
  ),
  child: Drawer(...),
)
```

---

## Animations

### Opening Animation

The drawer slides in from the left with a smooth easing curve:

```dart
// Duration: 300ms
// Curve: Curves.easeInOut
```

### Item Tap Feedback

Items provide visual feedback on tap:
- Ripple effect
- Slight scale animation

---

## Accessibility

### Screen Reader Support

Each drawer item has semantic labels:

```dart
Semantics(
  label: title,
  button: true,
  enabled: onTap != null,
  child: ListTile(...),
)
```

### Keyboard Navigation

Drawer supports keyboard navigation on desktop:
- Tab: Navigate between items
- Enter: Activate item
- Escape: Close drawer

---

## Best Practices

### DO: Keep Menu Flat

```dart
// ✅ Good: Flat structure
Drawer(
  child: ListView(
    children: [
      MenuItem("New Game"),
      MenuItem("Settings"),
      MenuItem("About"),
    ],
  ),
)

// ❌ Bad: Nested menus
Drawer(
  child: ListView(
    children: [
      MenuItem("Game", children: [
        MenuItem("New"),
        MenuItem("Load"),
      ]),
    ],
  ),
)
```

### DO: Use Dividers to Group

```dart
// ✅ Good
MenuItem("New Game"),
MenuItem("Load Game"),
Divider(),  // Separates game actions from settings
MenuItem("Settings"),
```

### DO: Close Drawer After Navigation

```dart
// ✅ Good
onTap: () {
  Navigator.pop(context);  // Close drawer first
  Navigator.push(context, ...);  // Then navigate
}

// ❌ Bad
onTap: () {
  Navigator.push(context, ...);  // Drawer stays open!
}
```

### DON'T: Hardcode Strings

```dart
// ❌ Bad
CustomDrawerItem(title: "Settings")

// ✅ Good
CustomDrawerItem(title: S.of(context).settings)
```

---

## Common Patterns

### Pattern 1: Simple Navigation

```dart
CustomDrawerItem(
  icon: FluentIcons.home_24_regular,
  title: S.of(context).home,
  onTap: () {
    Navigator.pop(context);
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => HomePage()),
    );
  },
)
```

### Pattern 2: With Confirmation Dialog

```dart
CustomDrawerItem(
  icon: FluentIcons.delete_24_regular,
  title: S.of(context).clearHistory,
  onTap: () async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(S.of(context).confirmClearHistory),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(S.of(context).cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(S.of(context).confirm),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      clearHistory();
    }
  },
)
```

### Pattern 3: With Dynamic Value Display

```dart
ValueListenableBuilder<int>(
  valueListenable: DB().listenGeneralSettings,
  builder: (context, _, __) {
    final level = DB().generalSettings.aiLevel;
    
    return CustomDrawerItem(
      icon: FluentIcons.brain_circuit_24_regular,
      title: S.of(context).aiDifficulty,
      subtitle: 'Level: $level',
      onTap: () {
        // Navigate to difficulty settings
      },
    );
  },
)
```

---

## Testing

### Widget Test

```dart
testWidgets('CustomDrawer opens and closes', (tester) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        drawer: Drawer(
          child: CustomDrawerItem(
            icon: Icons.home,
            title: 'Home',
            onTap: () {},
          ),
        ),
        body: Container(),
      ),
    ),
  );

  // Open drawer
  await tester.tap(find.byType(DrawerButton));
  await tester.pumpAndSettle();

  expect(find.text('Home'), findsOneWidget);

  // Close drawer
  await tester.drag(find.text('Home'), const Offset(-300, 0));
  await tester.pumpAndSettle();

  expect(find.text('Home'), findsNothing);
});
```

---

## Troubleshooting

### Issue: Drawer Not Opening

**Cause**: No `Scaffold` ancestor or drawer not set  
**Solution**: Ensure Scaffold has `drawer` property set

```dart
Scaffold(
  drawer: Drawer(...),  // Must be set
)
```

### Issue: Items Not Tappable

**Cause**: `onTap` is null  
**Solution**: Provide onTap callback

```dart
CustomDrawerItem(
  title: "Item",
  onTap: () {  // Must provide handler
    // Handle tap
  },
)
```

### Issue: Drawer Stays Open After Navigation

**Cause**: Forgot to close drawer  
**Solution**: Call `Navigator.pop(context)` before navigating

```dart
onTap: () {
  Navigator.pop(context);  // Close drawer
  Navigator.push(...);      // Then navigate
}
```

---

## Related Components

- [HomePage](../../home/home.md): Main landing page
- [Settings Pages](../../../*_settings/): Various settings pages
- [Navigation](../../workflows/navigation.md): Navigation patterns

---

**Maintainer**: Sanmill Development Team  
**License**: GPL v3

