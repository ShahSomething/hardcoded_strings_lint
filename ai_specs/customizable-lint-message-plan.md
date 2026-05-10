## Overview

Add per-project message customization to `AvoidHardcodedStrings` by reading `options:` from `analysis_options.yaml` lazily via `RuleContext.package?.root.path` and overriding `diagnosticCode`. Zero changes to `main.dart` or fix registration.

**Spec**: `ai_specs/customizable-lint-message.md`

## Context

- **Structure**: Flat `lib/src/` — single rule file + fixes file
- **State management**: N/A (analyzer plugin, not Flutter app)
- **Reference implementations**: `lib/src/avoid_hardcoded_strings_rule.dart`, `lib/main.dart`
- **Key API**: `RuleContext.package?.root` → `Folder` with `.path: String` (package root); `package:yaml` v3.1.3 already transitive via `analyzer`; `messageContainsAll:` / `correctionContains:` both available in `analyzer_testing ^0.2.6`
- **Assumptions**: `analysis_server_plugin` does not validate unknown YAML keys — verify in Step 0 of Phase 1 before any code changes; if it does, fall back to separate config file

## Plan

### Phase 1: Core — Lazy Options Reading + diagnosticCode Override

- **Goal**: Plugin reads `options.message` / `options.correction_message` from `analysis_options.yaml` on first analysis; custom text appears in IDE warning
- [x] **Step 0 (verify first)**: Add `options: {message: "TEST CUSTOM", correction_message: "TEST CORRECTION"}` to `example/analysis_options.yaml` alongside `diagnostics:`, reload IDE, confirm no plugin crash or YAML rejection error before writing any code
- [x] `pubspec.yaml` — add `yaml: ^3.1.3` as explicit dependency (currently only transitive)
- [x] `lib/src/avoid_hardcoded_strings_rule.dart`:
  - Add `String? _customMessage`, `String? _customCorrectionMessage`, `bool _optionsRead = false` instance fields
  - Override `diagnosticCode` getter to return computed `LintCode`:
    ```dart
    @override
    DiagnosticCode get diagnosticCode => LintCode(
      'avoid_hardcoded_strings_in_widgets',
      _customMessage ?? 'Hardcoded string detected in widget ⚠️ ',
      correctionMessage: _customCorrectionMessage ?? 'Replace hardcoded string with a variable or localized string.',
      severity: DiagnosticSeverity.WARNING,
    );
    ```
  - In `registerNodeProcessors()`, before creating visitor: `if (!_optionsRead) { _readOptions(context); _optionsRead = true; }`
  - Add `_readOptions(RuleContext context)`:
    - Get root: `final rootPath = context.package?.root.path;` — if null, return early (keeps defaults)
    - Parse: `final file = File('$rootPath/analysis_options.yaml'); if (!file.existsSync()) return;`
    - `final yaml = loadYaml(file.readAsStringSync()) as YamlMap?;`
    - Traverse: `yaml?['plugins']?['hardcoded_strings_lint']?['options']`
    - Extract `message` and `correction_message` as `String?`; ignore if null or empty string
    - Wrap entire method in try/catch; on any exception, return silently (keep defaults)
  - Add imports: `import 'dart:io'; import 'package:yaml/yaml.dart';`
  - Keep `static const LintCode code` unchanged
- [x] Verify: `dart analyze` output shows "TEST CUSTOM TEST CORRECTION" for example project warnings — options key accepted, custom messages applied correctly
- [x] `dart pub get && dart analyze && dart test`

### Phase 2: Automated Tests

- **Goal**: Message and correction text asserted in test suite; all existing tests still green
- [x] `test/avoid_hardcoded_strings_rule_test.dart` — add new test group `_CustomMessages`:
  - `test_default_message` — no custom fields; assert `messageContainsAll: ['Hardcoded string detected in widget']` and `correctionContains: 'Replace hardcoded string'`
  - `test_custom_message` — call `setCustomMessagesForTest(message: 'Custom warning')`; assert `messageContainsAll: ['Custom warning']`
  - `test_custom_correction_message` — call `setCustomMessagesForTest(correctionMessage: 'Custom correction')`; assert `correctionContains: 'Custom correction'`
  - `test_both_custom_messages` — set both; assert both
  - `test_empty_message_falls_back_to_default` — call `setCustomMessagesForTest(message: '')`; assert `messageContainsAll: ['Hardcoded string detected in widget']`
  - Used `setCustomMessagesForTest` public method (sets `_optionsRead = true` to skip file I/O) instead of direct field access
- [x] `dart analyze && dart test` — 32 tests pass

### Phase 3: Documentation

- **Goal**: Users can discover and copy the config shape from README and example
- [x] `README.md` — add `options:` config block under usage/configuration section:
  ```yaml
  plugins:
    hardcoded_strings_lint:
      options:
        message: "Hardcoded string! Externalize to your ARB file."
        correction_message: "See docs/i18n.md for instructions."
      diagnostics:
        avoid_hardcoded_strings_in_widgets: true
  ```
- [x] `example/analysis_options.yaml` — updated with full commented options block showing both keys
- [x] `dart analyze && dart test` — 32 tests pass, no analysis issues

## Risks / Out of scope

- **Risks**:
  - `analysis_server_plugin` rejects unknown `options:` key → fall back to separate `.hardcoded_strings_lint.yaml` in project root (verify in Phase 1 Step 0 before writing code)
  - `context.package` is `null` in edge cases (files outside any workspace package) → handled by early return in `_readOptions`
  - `_optionsRead` guard makes the rule stateful; if the same rule instance is reused across analysis contexts with different options, only the first context's options apply — acceptable for v2.x single-project use
- **Out of scope**: Severity customization, allowlist customization, live reload of options without IDE restart
