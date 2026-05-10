# Hardcoded Strings Lint

A Flutter analyzer plugin that detects hardcoded strings in widget constructors, encouraging better internationalization and code maintainability.

## Overview

`hardcoded_strings_lint` is built on top of Dart's official [`analysis_server_plugin`][asp] system, so its diagnostics surface natively in `dart analyze` and inside the Dart Analysis Server (VS Code, IntelliJ, etc.) without any extra commands.

[asp]: https://pub.dev/packages/analysis_server_plugin

## Features

### Smart Detection

- Flags hardcoded strings passed directly to Flutter widget constructor arguments.
- Skips strings inside callback bodies (e.g. `onTap: () { logger.info('...'); }`).
- Walks the inheritance chain so custom `Widget` subclasses are detected.

### Intelligent Filtering

- **Technical patterns skipped**: URLs, emails, hex colors, snake_case, CONSTANT_CASE, dotted notation, file paths.
- **Short strings skipped**: empty and ≤ 2 characters.
- **Map keys skipped**: `map['k']` and `{'k': value}`.
- **Acceptable widget properties skipped**: `semanticsLabel`, `restorationId`, `heroTag`, `key`, `debugLabel`, `tooltip`, `fontFamily`, `package`, `asset`, `textDirection`, `textAlign`, and others.

### Quick Fixes

- **Add ignore comment** — inserts the prefixed `// ignore: hardcoded_strings_lint/avoid_hardcoded_strings_in_widgets` above the offending line.
- **Ignore for whole file** — inserts `// ignore_for_file: hardcoded_strings_lint/avoid_hardcoded_strings_in_widgets` at the top of the file (or appends to an existing `ignore_for_file` comment).
- **Ignore in `analysis_options.yaml`** — disables the rule project-wide by writing `diagnostics: { avoid_hardcoded_strings_in_widgets: false }` into your `analysis_options.yaml`.
- **Extract to variable** — extracts the literal to a `const` local (inside a method) or a `static const` field (inside a class), naming the variable from the string contents (e.g. `'Hello, World!'` → `helloWorldText`).

## Installation

### 1. Configure `analysis_options.yaml`

Add the plugin under the **top-level** `plugins:` block (not under `analyzer:`):

```yaml
plugins:
  hardcoded_strings_lint: ^2.1.0
```

The plugin's diagnostic is enabled by default. To explicitly disable or re-enable it use the nested `diagnostics:` map:

```yaml
plugins:
  hardcoded_strings_lint:
    version: ^2.0.0
    diagnostics:
      avoid_hardcoded_strings_in_widgets: true
```

### Custom warning messages

Override the lint message and correction hint to use project-specific language (e.g. pointing to your own i18n docs):

```yaml
plugins:
  hardcoded_strings_lint:
    options:
      message: "Hardcoded string! Externalize to your ARB file."
      correction_message: "See docs/i18n.md for instructions."
    diagnostics:
      avoid_hardcoded_strings_in_widgets: true
```

Both `message` and `correction_message` are optional. Omitting either keeps that field's built-in default. An empty string also falls back to the default.

### 2. Resolve and analyze

```bash
dart pub get
dart analyze
```

That's it — no separate `dart run …` command, no `dev_dependencies` entry, no `analyzer.plugins` block.

> **Restart the analyzer** in your IDE after first installing the plugin or changing the `plugins:` section.

## Usage

```dart
class WelcomeScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Welcome to Our App'), // ⚠️ flagged
      ),
      body: Column(
        children: [
          Text('Hello, World!'), // ⚠️ flagged
          ElevatedButton(
            onPressed: () {},
            child: Text('Get Started'), // ⚠️ flagged
          ),
        ],
      ),
    );
  }
}
```

```dart
class WelcomeScreen extends StatelessWidget {
  static const _welcomeTitle = 'Welcome to Our App';
  static const _helloText = 'Hello, World!';
  static const _getStartedText = 'Get Started';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_welcomeTitle), // ✅
        backgroundColor: Colors.blue, // ✅ technical value
      ),
      body: Column(
        children: [
          Text(_helloText), // ✅
          ElevatedButton(
            onPressed: () {},
            child: Text(_getStartedText), // ✅
          ),
          Image.asset('assets/logo.png'), // ✅ asset path
        ],
      ),
    );
  }
}
```

## Ignoring warnings

The plugin uses the analyzer's native ignore-comment system. The `hardcoded_strings_lint/` prefix is required — bespoke shorthands like `// hardcoded.ok` are no longer recognized.

### Per line

```dart
// ignore: hardcoded_strings_lint/avoid_hardcoded_strings_in_widgets
Text('This is acceptable hardcoded text'),
```

### Per file

```dart
// ignore_for_file: hardcoded_strings_lint/avoid_hardcoded_strings_in_widgets

class DebugScreen extends StatelessWidget { /* ... */ }
```

## Smart filtering rules

### Technical patterns automatically skipped

- URLs: `https://example.com`, `file://path`
- Email addresses: `user@example.com`
- Hex colors: `#FF5722`, `#ffffff`
- File paths: `/assets/images/logo.png`
- snake_case / CONSTANT_CASE identifiers
- Dotted notation: `package.asset`

### Acceptable widget properties

```dart
Text('hi', semanticsLabel: 'A long accessibility label'), // ✅
Scaffold(restorationId: 'home_scaffold'),                 // ✅
```

Full allowlist: `semanticsLabel`, `excludeSemantics`, `restorationId`, `heroTag`, `key`, `debugLabel`, `fontFamily`, `package`, `name`, `asset`, `tooltip`, `textDirection`, `locale`, `materialType`, `clipBehavior`, `crossAxisAlignment`, `mainAxisAlignment`, `textAlign`, `textBaseline`, `overflow`, `softWrap`, `textScaleFactor`.

## Quick fixes

### Add ignore comment

```dart
// Before:
Text('Hello World')

// After:
// ignore: hardcoded_strings_lint/avoid_hardcoded_strings_in_widgets
Text('Hello World')
```

### Ignore for whole file

```dart
// ignore_for_file: hardcoded_strings_lint/avoid_hardcoded_strings_in_widgets

class DebugScreen extends StatelessWidget { /* ... */ }
```

If `ignore_for_file:` is already present in the file the rule name is appended to the existing comment rather than adding a second one.

### Ignore in `analysis_options.yaml`

Disables the rule for the entire project by adding the following to your `analysis_options.yaml`:

```yaml
plugins:
  hardcoded_strings_lint:
    diagnostics:
      avoid_hardcoded_strings_in_widgets: false
```

The fix creates the `plugins`, `hardcoded_strings_lint`, and `diagnostics` keys if any are absent, and is a no-op if the rule is already disabled.

### Extract to variable

```dart
// Before (inside a build method):
Text('Welcome to our application')

// After:
@override
Widget build(BuildContext context) {
  const welcomeToOurText = 'Welcome to our application';
  return Text(welcomeToOurText);
}

// Before (inside a class, outside a method):
class MyWidget extends StatelessWidget {
  final Widget header = Text('Welcome to our application');
}

// After:
class MyWidget extends StatelessWidget {
  static const welcomeToOurText = 'Welcome to our application';
  final Widget header = Text(welcomeToOurText);
}
```

## Migrating from 1.x

Version 2.0.0 is a clean break. The package is now built on Dart's official `analysis_server_plugin` system instead of the deprecated `custom_lint_builder` ecosystem.

**Why the break**: `custom_lint` is no longer actively developed. The Dart team's `analysis_server_plugin` is the official replacement, ships with Dart 3.10 (Flutter 3.38) and later, and removes the need for a separate `dart run custom_lint` step.

### `pubspec.yaml`

```diff
 environment:
-  sdk: ^3.6.0
+  sdk: ^3.11.0  # Flutter 3.41+

 dev_dependencies:
-  custom_lint: ^0.8.1
-  analyzer: ^8.1.1
-  hardcoded_strings_lint: ^1.0.4
```

The plugin is no longer a `dev_dependency` — it's loaded entirely through `analysis_options.yaml`.

### `analysis_options.yaml`

```diff
-analyzer:
-  plugins:
-    - custom_lint
+plugins:
+  hardcoded_strings_lint: ^2.0.0
```

Note the `plugins:` block is now a **top-level** key, not nested under `analyzer:`.

### Ignore comments

The ignore syntax now requires the `hardcoded_strings_lint/` prefix:

```diff
-// ignore: avoid_hardcoded_strings_in_widgets
-// ignore: hardcoded.string
-// hardcoded.ok
+// ignore: hardcoded_strings_lint/avoid_hardcoded_strings_in_widgets
```

The bespoke `// hardcoded.ok` and `// ignore: hardcoded.string` shorthands are removed.

### No more `dart run custom_lint`

`dart analyze` and the Dart Analysis Server pick up the plugin automatically. There's nothing else to run.

## Troubleshooting

### Rule not running

1. Confirm `hardcoded_strings_lint` is listed under `plugins:` in `analysis_options.yaml`.
2. Restart the Dart Analysis Server / your IDE — plugin changes only take effect after a restart.
3. Run `dart pub get`.
4. Run `dart analyze` to surface diagnostics from the command line.

### Ignore comments not taking effect

This can happen in workspaces with multiple `analysis_options.yaml` files (see [dart-lang/sdk#62173](https://github.com/dart-lang/sdk/issues/62173)). The fix is tracked upstream; for now, hoist the `plugins:` block to a single root analysis options file.

### False positives

- Verify the string really matches a technical pattern listed above. If not, add an ignore comment or rename the value to fit a pattern (e.g. `snake_case`).
- Consider whether the widget argument should be added to the acceptable allowlist; PRs welcome.

## Best practices

```dart
// Recommended: localization
Text(AppLocalizations.of(context).welcomeMessage)

// Or grouped constants
class AppStrings {
  static const appTitle = 'My App';
  static const welcomeMessage = 'Welcome';
  static const loginButton = 'Login';
}

// Use ignore comments sparingly — debug/dev only
// ignore: hardcoded_strings_lint/avoid_hardcoded_strings_in_widgets
Text('DEBUG: state=$state')
```

## License

This package is released under the MIT License. See [LICENSE](LICENSE) for details.

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for version history.
