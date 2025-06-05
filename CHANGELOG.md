
# Changelog

All notable changes to the hardcoded_strings_lint package will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
