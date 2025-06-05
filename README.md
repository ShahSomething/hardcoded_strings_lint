# Hardcoded Strings Lint

A custom Flutter lint rule that identifies and prevents hardcoded strings in widget constructors, promoting better internationalization practices and code maintainability.

## Overview

The `hardcoded_strings_lint` package provides a sophisticated lint rule that automatically detects hardcoded string literals in Flutter widgets and suggests fixes to improve code quality. This tool is essential for Flutter applications that need to support multiple languages or maintain clean, professional codebases.

## Features

### 🔍 **Smart Detection**
- Identifies hardcoded strings specifically in Flutter widget contexts
- Distinguishes between user-facing text and technical strings
- Ignores acceptable technical properties and configuration values

### 🎯 **Intelligent Filtering**
- **Skips technical strings**: URLs, email addresses, hex colors, file paths, identifiers
- **Ignores short strings**: Single characters, operators, and very short text (≤2 characters)
- **Excludes map keys**: Strings used as keys in maps or index expressions
- **Respects acceptable properties**: Asset names, debug labels, technical identifiers

### 🛠️ **Built-in Quick Fixes**
- **Add ignore comment**: Quickly suppress the warning for specific cases
- **Extract to variable**: Automatically extract hardcoded strings to local variables or class constants

### 💡 **Flexible Ignore System**
- Support for multiple ignore comment patterns
- Line-specific and file-level ignores
- Case-insensitive pattern matching

## Installation

### 1. Add Dependencies

Add the following to your project's `pubspec.yaml`:

```yaml
dev_dependencies:
  custom_lint: ^0.7.5
  hardcoded_strings_lint: ^1.0.0
```

### 2. Configure Analysis Options

Add to your `analysis_options.yaml`:

```yaml
analyzer:
  plugins:
    - custom_lint

# Optional: Configure additional linter rules
linter:
  rules:
    # Your existing rules
```

### 3. Install Dependencies

```bash
flutter pub get
```

## Usage

Once installed and configured, the lint rule will automatically analyze your Flutter code and highlight hardcoded strings in widget constructors.

### Example: Problematic Code

```dart
class WelcomeScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Welcome to Our App'), // ⚠️ Hardcoded string detected
      ),
      body: Column(
        children: [
          Text('Hello, World!'), // ⚠️ Hardcoded string detected
          ElevatedButton(
            onPressed: () {},
            child: Text('Get Started'), // ⚠️ Hardcoded string detected
          ),
        ],
      ),
    );
  }
}
```

### Example: Acceptable Code

```dart
class WelcomeScreen extends StatelessWidget {
  // Using extracted constants
  static const String _welcomeTitle = 'Welcome to Our App';
  static const String _helloText = 'Hello, World!';
  static const String _getStartedText = 'Get Started';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_welcomeTitle), // ✅ Using constant
        backgroundColor: Colors.blue, // ✅ Technical value, ignored
      ),
      body: Column(
        children: [
          Text(_helloText), // ✅ Using constant
          ElevatedButton(
            onPressed: () {},
            child: Text(_getStartedText), // ✅ Using constant
          ),
          Image.asset('assets/logo.png'), // ✅ Asset path, ignored
        ],
      ),
    );
  }
}
```

## Ignoring Warnings

### Method 1: Ignore Comments

```dart
// ignore: avoid_hardcoded_strings_in_widgets
Text('This is acceptable hardcoded text')

// Or using alternative patterns:
// ignore: hardcoded.string
Text('Debug text only')

// hardcoded.ok
Text('Temporary placeholder')
```

### Method 2: File-level Ignore

```dart
// ignore_for_file: avoid_hardcoded_strings_in_widgets

class DebugScreen extends StatelessWidget {
  // All hardcoded strings in this file will be ignored
}
```

## Smart Filtering Rules

### Automatically Ignored Strings

#### Technical Patterns
- **URLs**: `https://example.com`, `file://path`
- **Email addresses**: `user@example.com`
- **Hex colors**: `#FF5722`, `#ffffff`
- **File paths**: `/assets/images/logo.png`
- **Identifiers**: `snake_case_id`, `CONSTANT_VALUE`

#### Widget Properties
The following widget properties are considered acceptable for hardcoded strings:

```dart
// Accessibility and semantics
Semantics(label: 'Navigation button') // ✅ Ignored

// Technical identifiers
Hero(tag: 'hero_tag') // ✅ Ignored
Widget(key: Key('unique_key')) // ✅ Ignored

// Asset references
Image.asset('assets/logo.png') // ✅ Ignored

```

## Quick Fixes

### 1. Add Ignore Comment
Automatically adds an ignore comment above the flagged line:

```dart
// Before quick fix:
Text('Hello World')

// After applying "Add ignore comment":
// ignore: avoid_hardcoded_strings_in_widgets
Text('Hello World')
```

### 2. Extract to Variable
Automatically extracts the string to a variable:

```dart
// Before quick fix:
Text('Welcome to our application')

// After applying "Extract to variable" (method scope):
Widget build(BuildContext context) {
  const welcomeToOurApplicationText = 'Welcome to our application';
  return Text(welcomeToOurApplicationText);
}

// After applying "Extract to variable" (class scope):
class MyWidget extends StatelessWidget {
  static const welcomeToOurApplicationText = 'Welcome to our application';
  
  Widget build(BuildContext context) {
    return Text(welcomeToOurApplicationText);
  }
}
```

## Configuration

### Acceptable Properties

The rule comes pre-configured with a comprehensive list of widget properties where hardcoded strings are acceptable:

- **Accessibility**: `semanticsLabel`, `excludeSemantics`
- **Technical IDs**: `restorationId`, `heroTag`, `key`, `debugLabel`
- **Assets**: `fontFamily`, `package`, `asset`
- **Layout**: `textDirection`, `textAlign`, `crossAxisAlignment`

### Technical String Patterns

The following patterns are automatically recognized as technical:
- URLs and schemes
- Email addresses
- Hex color codes
- File paths and extensions
- CONSTANT_CASE identifiers
- snake_case identifiers
- Dotted notation (package.asset)

## Best Practices

### 1. Use Localization
```dart
// Recommended approach
Text(AppLocalizations.of(context).welcomeMessage)

// Alternative with constants
static const String welcomeMessage = 'Welcome';
Text(welcomeMessage)
```

### 2. Group Related Strings
```dart
class AppStrings {
  static const String appTitle = 'My App';
  static const String welcomeMessage = 'Welcome';
  static const String loginButton = 'Login';
}
```

### 3. Use Ignore Comments Sparingly
```dart
// Good use case - debug/development only
// ignore: avoid_hardcoded_strings_in_widgets
Text('DEBUG: Current state: $state')

// Consider localization instead for user-facing text
Text(context.l10n.welcomeMessage) // Better approach
```

## Troubleshooting

### Common Issues

#### 1. Rule Not Running
- Ensure `custom_lint` is added to `dev_dependencies`
- Verify `analyzer.plugins` includes `custom_lint` in `analysis_options.yaml`
- Run `flutter pub get` after configuration changes
- Run `dart run custom_lint`

#### 2. False Positives
- Use ignore comments for legitimate hardcoded strings
- Check if the string matches technical patterns
- Consider if the widget property should be in the acceptable list

#### 3. Performance
- The rule is optimized to skip non-widget contexts
- Large files may take slightly longer to analyze
- Consider using ignore_for_file for generated files

## Contributing

This package is part of a larger Flutter project. For contributions:

1. Follow the existing code style
2. Add tests for new functionality
3. Update documentation for any new features
4. Ensure backward compatibility

## License
This package is released under the MIT License. See [LICENSE](LICENSE) for details.

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for version history and updates.

---

**Note**: This lint rule is designed to improve code quality and internationalization readiness. While it provides intelligent filtering, manual review of suggestions is recommended to ensure the best outcome for your specific use case.
