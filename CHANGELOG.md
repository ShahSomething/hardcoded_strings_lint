
# Changelog

All notable changes to the hardcoded_strings_lint package will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.1.0] - 2026-05-10
### Added
- **Customizable lint messages**: Override the warning text and correction hint per-project via an `options:` block in `analysis_options.yaml`. Both `message` and `correction_message` are optional; omitting either keeps the built-in default.
- **"Ignore for whole file" quick fix** (`IgnoreForFileFix`): Inserts an `// ignore_for_file: hardcoded_strings_lint/avoid_hardcoded_strings_in_widgets` comment at the top of the current file, or appends to an existing `ignore_for_file` comment if one is already present.
- **"Ignore in `analysis_options.yaml`" quick fix** (`IgnoreInAnalysisOptionsFix`): Writes `diagnostics: { avoid_hardcoded_strings_in_widgets: false }` into the plugin section of `analysis_options.yaml`, disabling the rule project-wide without touching source files.
- `yaml_edit: ^2.2.4` direct dependency (used by `IgnoreInAnalysisOptionsFix` to safely edit YAML).

## [2.0.0] - 2026-05-10
### Changed
- **BREAKING**: Migrated from `custom_lint_builder` to Dart's official [`analysis_server_plugin`][asp] system. The plugin is now loaded through a top-level `plugins:` block in `analysis_options.yaml` instead of being a `dev_dependency` registered under `analyzer.plugins`. See the README's "Migrating from 1.x" section for the full diff.
- **BREAKING**: Minimum Dart SDK is now `^3.11.0` (Flutter 3.41+). The constraint comes from `analysis_server_plugin: ^0.3.15` → `analyzer: 13.0.0`, which itself requires Dart 3.11.
- **BREAKING**: Ignore comments now require the `hardcoded_strings_lint/` plugin-name prefix (an `analysis_server_plugin` requirement). Use `// ignore: hardcoded_strings_lint/avoid_hardcoded_strings_in_widgets` instead of the bare rule name.
- **BREAKING**: Removed the bespoke `// hardcoded.ok` and `// ignore: hardcoded.string` shorthand patterns. Suppression now uses the analyzer's native ignore-comment handling exclusively.

### Removed
- The `createPlugin()` factory and the `package:hardcoded_strings_lint/hardcoded_strings_lint.dart` library entry. The plugin is loaded from `package:hardcoded_strings_lint/main.dart` per the `analysis_server_plugin` convention.
- `dart run custom_lint` is no longer required (or supported). Diagnostics surface natively in `dart analyze` and the Dart Analysis Server.

### Added
- Unit test suite covering the rule (19 tests) and both quick fixes (8 tests), built on the official `analyzer_testing` harness.

[asp]: https://pub.dev/packages/analysis_server_plugin

## [1.0.4] - 2025-10-09
### Improved
- Refined widget argument detection logic to prevent false positives
- Strings inside callback or function bodies are no longer incorrectly flagged as hardcoded strings
- Enhanced accuracy in detecting hardcoded strings passed to widget constructors

## [1.0.3] - 2025-09-18
### Improved
- Extract to variable fix now generates camelCase variable names instead of snake_case
### Updated
- Documentation

## [1.0.2] - 2025-09-18
### Updated
- Updated dependencies

## [1.0.1] - 2025-06-05
### Documentation
Updated documentation


## [1.0.0] - 2025-06-05

### Added
- Initial release of hardcoded_strings_lint package
- Custom lint rule `avoid_hardcoded_strings_in_widgets` to detect hardcoded strings in Flutter widgets
- Smart filtering system that ignores technical strings, map keys, and acceptable widget properties
- Built-in quick fixes:
  - Add ignore comment functionality
  - Extract to variable functionality (both method and class scope)
- Comprehensive ignore comment support with multiple patterns
- Intelligent detection of Flutter widget contexts
- Technical string pattern recognition (URLs, emails, hex colors, file paths, identifiers)
- Support for acceptable widget properties (semantics, debug labels, asset references, etc.)
- Automatic filtering of short strings (≤2 characters) and empty strings

### Features
- **Smart Detection**: Identifies hardcoded strings specifically in Flutter widget constructors
- **Intelligent Filtering**: Distinguishes between user-facing text and technical configuration
- **Quick Fixes**: Automated solutions for common hardcoded string issues
- **Flexible Ignores**: Multiple ignore comment patterns for different use cases
- **Performance Optimized**: Only analyzes strings in widget contexts

### Technical Details
- Built on `custom_lint_builder` ^0.7.5
- Compatible with `analyzer` ^7.4.5
- Integrates seamlessly with Flutter's analysis system
- Supports both line-specific and file-level ignores
