# Plan: Fix Broken Built-in Ignore Quick Fixes

## Overview

Add two working custom `CorrectionProducer` subclasses: `IgnoreForFileFix` (inserts `// ignore_for_file:` with plugin prefix) and `IgnoreInAnalysisOptionsFix` (writes `diagnostics.avoid_hardcoded_strings_in_widgets: false` via `YamlEditor`). Built-in options 3–5 remain broken by framework; option 1 already covers "ignore this line".

**Spec**: `ai_specs/fix-broken-builtin-ignore-quickfixes.md`

## Context

- **Structure**: flat `lib/src/` — one rule file, one fixes file
- **State management**: N/A — analysis plugin
- **Reference implementations**:
  - `lib/src/fixes.dart` — existing `AddIgnoreCommentFix`, `ExtractToVariableFix` pattern to follow
  - `~/.pub-cache/…/analysis_server_plugin-0.3.15/lib/src/correction/ignore_diagnostic.dart` — `IgnoreDiagnosticInFile` (insertion algorithm) and `IgnoreInAnalysisOptionsFile` (`addYamlFileEdit` + `YamlEditor` pattern)
- **Assumptions/Gaps**:
  - `yaml_edit` is a transitive dep but not a direct dep — must add to `pubspec.yaml` before use
  - `addYamlFileEdit` is available on `ChangeBuilder` from `analyzer_plugin ^0.14.9` ✓
  - `analysisOptions as AnalysisOptionsImpl` gives `.file` reference for locating `analysis_options.yaml` ✓
  - Test helper `newAnalysisOptionsYamlFile(testPackageRootPath, content)` available from `analyzer_testing` ✓

## Plan

### Phase 1: IgnoreForFileFix

- **Goal**: Working "Ignore for whole file" fix — inserts `// ignore_for_file: hardcoded_strings_lint/avoid_hardcoded_strings_in_widgets`

- [x] `pubspec.yaml` — add `yaml_edit: ^2.2.4` to direct dependencies (^3.0.0 not published; used ^2.2.4)
- [x] `lib/src/fixes.dart` — add constant `_ignoreForFileCommentText`; implement `IgnoreForFileFix extends ResolvedCorrectionProducer`:
  - new `FixKind('dart.fix.ignoreForFileHardcodedString', DartFixKindPriority.ignore - 1, "Ignore for whole file")`
  - `applicability = singleLocation`
  - `compute`: use `builder.addDartFileEdit(file, ...)` — mirrors `IgnoreDiagnosticInFile` insertion logic
  - guard: if file content already contains `_ignoreForFileCommentText` → return early (no-op)
- [x] `lib/main.dart` — `registry.registerFixForRule(AvoidHardcodedStrings.code, IgnoreForFileFix.new)`
- [x] TDD: `test/fixes_test.dart` `IgnoreForFileFixTest` — RED then GREEN for each:
  - `test_inserts_ignore_for_file_comment` — fresh file → comment inserted at top
  - `test_inserts_after_header_blank_line` — file with copyright comment → inserted after header blank line
  - `test_appends_to_existing_ignore_for_file_comment` — existing `// ignore_for_file: some_other_rule` → appended, not duplicated
  - `test_no_op_when_comment_already_present` — file with exact comment → zero edits produced (or diagnostic suppressed)
- [x] Verify: `dart pub get && dart analyze && dart test`

### Phase 2: IgnoreInAnalysisOptionsFix

- **Goal**: Working "Ignore in analysis_options.yaml" fix — writes `diagnostics.avoid_hardcoded_strings_in_widgets: false` under plugin section

- [x] `lib/src/fixes.dart` — implement `IgnoreInAnalysisOptionsFix extends ResolvedCorrectionProducer`:
  - new `FixKind('dart.fix.ignoreInAnalysisOptionsHardcodedString', DartFixKindPriority.ignore - 2, "Ignore in \`analysis_options.yaml\`")`
  - `applicability = singleLocation`
  - `compute`: null/FileSystemException/YamlException guards; precise nested path handling preserving existing settings; loops over `editor.edits` with insertion/replacement dispatch
- [x] `lib/main.dart` — `registry.registerFixForRule(AvoidHardcodedStrings.code, IgnoreInAnalysisOptionsFix.new)`
- [x] TDD: `test/fixes_test.dart` `IgnoreInAnalysisOptionsFixTest` — RED then GREEN for each:
  - `test_writes_full_nested_path_when_plugins_absent` — no plugins key → inserts full nested map
  - `test_writes_disable_entry_to_existing_plugin_section` — plugin block present, no `diagnostics` → adds entry, preserves existing settings
  - `test_no_op_when_already_disabled` — entry already `false` → zero edits produced
  - `test_no_op_on_malformed_yaml` — malformed YAML content → no crash, zero edits
  - NOTE: `test_no_op_when_analysis_options_file_absent` not automated — test infra always creates the file; null guard verified by code review
- [x] Verify: `dart analyze && dart test`

## Risks / Out of scope

- **Risks**:
  - `YamlEditor.update()` has known edge-case bugs (AssertionError) — wrap in `try/catch AssertionError` and return early, same as built-in implementation
  - `addYamlFileEdit` callback receives `YamlFileEditBuilder`; its API (`addSimpleInsertion`) differs from `DartFileEditBuilder` — verify correct method name at implementation time
  - Tests for `IgnoreInAnalysisOptionsFix` depend on `AnalysisOptionsImpl.file` being non-null in the test environment — may need `newAnalysisOptionsYamlFile` setup in each test
- **Out of scope**: built-in options 3–5 remain broken; option 1 (`AddIgnoreCommentFix`) unchanged; `_ignoreCommentText` constant unchanged
