# Plan: Migrate to `analysis_server_plugin` (v2.0.0)

## Overview

Clean break from `custom_lint_builder` → `analysis_server_plugin`. Preserve all v1 detection + both fixes. Add unit tests using `analyzer_testing` harness.

**Spec**: `ai_specs/migrate-to-analysis-server-plugin.md` (read for full requirements)

## Context

- **Structure**: Flat `lib/` + `lib/src/` (Dart package, not Flutter app).
- **State**: N/A — pure analyzer plugin, no UI, no I/O, no async state.
- **Reference impls**:
  - v1 monolith: `lib/src/hardcoded_strings_lint_base.dart` (logic to port verbatim).
  - v1 entry: `lib/hardcoded_strings_lint.dart` (replace `createPlugin()`).
  - External pattern: `many_lints` package on pub.dev; Dart SDK `pkg/analysis_server_plugin/doc/{writing_rules,writing_fixes,testing_rules,using_plugins}.md`.
- **Assumptions/Gaps**:
  - `analyzer ^12.x` keeps unsuffixed accessors (`.element`, `.supertype`, `.name`) — verify; do NOT add `.element2`/`.name2`.
  - Exact `analyzer` floor = whatever `analysis_server_plugin ^0.3.15` resolves to (check at impl time).
  - Fix-test API: follow `analyzer_testing` exposes (`assertFixContents` or equivalent) per `testing_rules.md`.
  - `analyzer_testing` version: pick one compatible with `analyzer ^12.x` at impl time.

## Plan

### Phase 1: End-to-end vertical slice — minimal plugin reports one diagnostic ✅

- **Goal**: Wire new `Plugin` + `AnalysisRule` skeleton; prove `dart analyze` on `example/` flags one hardcoded string. No fixes yet, no full filter set.
- [x] `pubspec.yaml` — bump `version: 2.0.0`, `sdk: ^3.10.0`; drop `custom_lint_builder` + `analyzer_plugin`; add `analysis_server_plugin: ^0.3.15`, `analyzer: ^12.x` (use lower bound from resolution); add `dev_dependencies`: `analyzer_testing`, `test_reflective_loader: ^0.2.x`; keep `test`, `lints`. _(Note: `analysis_server_plugin ^0.3.15` actually requires `analyzer 13.0.0` and Dart SDK `^3.11.0`; pubspec uses these resolved floors.)_
- [x] `lib/src/avoid_hardcoded_strings_rule.dart` — new file. `AvoidHardcodedStrings extends AnalysisRule`. Static `const LintCode code` with `severity: DiagnosticSeverity.WARNING` (analyzer 13's `LintCode` accepts `severity:`; `registerWarningRule` only governs default-enabled status, not display severity). Override `diagnosticCode => code`. `registerNodeProcessors` calls `addSimpleStringLiteral`/`addAdjacentStrings`/`addStringInterpolation` with one shared `_Visitor extends SimpleAstVisitor<void>`. _(Note: Phase 1 also includes `_isPassedToWidget` because the test source must `import 'package:flutter/widgets.dart'` to type-resolve `Text(...)`, and that import string would otherwise be reported.)_
- [x] `lib/hardcoded_strings_lint.dart` — replace `createPlugin()` with top-level `final plugin = HardcodedStringsPlugin();` + `class HardcodedStringsPlugin extends Plugin`. Override `name => 'hardcoded_strings_lint'` + `register(PluginRegistry registry)` calling `registry.registerWarningRule(rule)`. _(Note: file is `lib/main.dart` instead — analyzer's plugin loader generates a shim that imports `package:<plugin>/main.dart`. Using a different filename causes AOT compilation failure when the analyzer tries to load the plugin.)_
- [x] Delete `lib/src/hardcoded_strings_lint_base.dart` after extraction is complete (Phase 2 may still consult it; final delete at end of Phase 2). _(Deleted in Phase 1: with the v1 imports gone, the file errored out `dart analyze`; v1 logic remains available in conversation context for porting.)_
- [x] `example/pubspec.yaml` — drop `custom_lint`, `analyzer`, and the `hardcoded_strings_lint:` dependency entry; bump `sdk: ^3.10.0`. _(SDK bumped to `^3.11.0` to match resolved analyzer floor.)_
- [x] `example/analysis_options.yaml` — remove `analyzer.plugins: [custom_lint]`; add nested `plugins:\n  hardcoded_strings_lint:\n    path: ../\n    diagnostics:\n      avoid_hardcoded_strings_in_widgets: true`.
- [x] TDD: rule reports diagnostic for `Text('Hello world')` — write failing test using `AnalysisRuleTest` from `analyzer_testing` (assigns `rule = AvoidHardcodedStrings()` in `setUp`), then make pass.
- [x] TDD: rule does NOT report for `Text('a')` (length ≤ 2) → then implement guard.
- [x] TDD: rule does NOT report for `Text('')` → then implement guard.
- [x] Verify: `dart pub get && dart analyze && dart test` in pkg root; `dart pub get && dart analyze` in `example/` produces hardcoded-string warning on `lib/main.dart`.

### Phase 2: Port full detection filter set + delete v1 monolith

- **Goal**: Behavior parity with v1 — widget walk, callback skip, technical/property/map-key filters. Delete legacy file.
- [ ] `lib/src/avoid_hardcoded_strings_rule.dart` — port verbatim from v1 (`hardcoded_strings_lint_base.dart`):
  - `_isPassedToWidget` (ArgumentList ancestor walk + FunctionExpression/FunctionBody early-out + InstanceCreationExpression check + widget-type check + direct-arg / NamedExpression match).
  - `_isFlutterWidget` + `_extendsWidget` + `_isWidgetBaseClass` allowlist (12 classes verbatim). Confirm `supertype.element` resolves under `analyzer ^12.x` — do NOT switch to suffixed accessors.
  - `_isAcceptableWidgetProperty` (22-property allowlist verbatim).
  - `_isTechnicalString` (10-regex set verbatim).
  - `_isMapKey` (`IndexExpression.index` + `MapLiteralEntry.key`).
  - Order in visitor: empty/short → `_isPassedToWidget` → `_isMapKey` → `_isAcceptableWidgetProperty` → `_isTechnicalString` → report (match v1).
  - Do NOT port `_hasIgnoreComment` / `_containsIgnoreComment`.
- [ ] Delete `lib/src/hardcoded_strings_lint_base.dart`.
- [ ] TDD per filter (one RED→GREEN cycle each):
  - URL / email / hex / snake_case / CONSTANT_CASE / dotted-notation skipped.
  - `Hero(tag:)`, `Image.asset(...)`, `Semantics(label:)` skipped.
  - `map['k']` and `{'k': v}` skipped.
  - `BlocListener(listener: (ctx, st) { logger.info('skip me'); })` NOT flagged (v1.0.4 regression test).
  - `print('hi')` and `myFn('hi')` (non-widget) NOT flagged.
  - Custom `class MyWidget extends StatelessWidget` flagged on its `Text(...)` arg (chain walk).
  - Adjacent strings `Text('foo' 'bar')` — visit each fragment.
  - Interpolation `Text('Hello $name')` NOT flagged (`stringValue == null` guard).
  - `// ignore: hardcoded_strings_lint/avoid_hardcoded_strings_in_widgets` suppresses (analyzer-native; verify via `analyzer_testing` ignore handling).
- [ ] Error-handling: when `staticType == null` or element unresolvable, skip silently (match v1).
- [ ] Verify: `dart analyze` (zero issues), `dart test` (all pass), `dart analyze` in `example/` (still flags expected strings).

### Phase 3: Quick fixes + fix tests

- **Goal**: Both quick fixes wired through `registerFixForRule` + tested.
- [ ] `lib/src/fixes.dart` — new file.
  - `class AddIgnoreCommentFix extends ResolvedCorrectionProducer`. Constructor `AddIgnoreCommentFix({required super.context});`. Static `const FixKind _kind = FixKind('dart.fix.addIgnoreHardcodedString', DartFixKindPriority.standard, "Add '// ignore' comment")`. `applicability => CorrectionApplicability.singleLocation`. `compute(ChangeBuilder)`: derive line indent, insert `'$indent// ignore: hardcoded_strings_lint/avoid_hardcoded_strings_in_widgets\n'` at `lineStart` (port from v1 `_AddIgnoreCommentFix.run`).
  - `class ExtractToVariableFix extends ResolvedCorrectionProducer`. Same constructor signature. Static `const FixKind _kind` with name `'dart.fix.extractHardcodedStringToVariable'`, label `'Extract to variable'`, priority lower than ignore. `applicability => CorrectionApplicability.singleLocation`. `compute`: walk ancestors for `MethodDeclaration` (BlockFunctionBody) → insert `\n    const $name = <src>;\n` after `block.leftBracket`, replace literal with `$name`. Else `ClassDeclaration` → insert `\n  static const $name = <src>;\n` after `leftBracket`, replace literal. Else no-op (no throw).
  - `_generateVariableName` — port verbatim (strip non-word/space, lowercase, first 3 words, camelCase, `Text` suffix; fallback `'textValue'`).
  - Both fixes: skip when `node.stringValue == null` (no edit).
- [ ] `lib/hardcoded_strings_lint.dart` — in `register`, add `registry.registerFixForRule(<rule>.code, AddIgnoreCommentFix.new)` and same for `ExtractToVariableFix.new` (tear-offs, not instances).
- [ ] TDD (one cycle per behavior):
  - Ignore-fix produces correct comment text above line.
  - Ignore-fix preserves leading indentation on deeply-indented line.
  - Extract-fix at method scope: `const helloWorldText = 'Hello world';` at block start + literal replaced with identifier.
  - Extract-fix at class scope: `static const ...` after class `{` + literal replaced.
  - Extract-fix `_generateVariableName('Hello, World!')` → `helloWorldText`.
  - Extract-fix `'!!!!!'` (>2 chars to bypass short-skip) → fallback `textValue`.
  - Extract-fix with no enclosing method/class: no-op, no throw.
- [ ] Verify: `dart analyze && dart test` (all pass).

### Phase 4: Docs, CHANGELOG, manual verification

- **Goal**: User-facing docs reflect new model; `## [2.0.0]` entry; manual IDE/CLI checklist.
- [ ] `README.md`:
  - Bump install snippet version to `^2.0.0`.
  - Replace `dev_dependencies` install instructions with `analysis_options.yaml`-based config (new `plugins:` block with nested `diagnostics:` exactly as in `<requirements>` #9).
  - Sweep `custom_lint`: line 39 (install snippet), 51 (`analyzer.plugins`), 68 (`dart run custom_lint`), 278–281 (Troubleshooting bullets). After edit, `grep -n "custom_lint" README.md` → 0 outside "Migrating from 1.x" section.
  - Rewrite Troubleshooting → "Rule Not Running": (a) ensure listed in `plugins:` block, (b) restart analyzer/IDE, (c) `dart pub get`, (d) `dart analyze`. No `dart run custom_lint`.
  - Update every example ignore comment to `// ignore: hardcoded_strings_lint/avoid_hardcoded_strings_in_widgets`. Remove `// hardcoded.ok` and `// ignore: hardcoded.string` examples.
  - Add `## Migrating from 1.x` section: why (custom_lint deprecation), before/after `pubspec.yaml` diff, before/after `analysis_options.yaml` diff, ignore-prefix note, removed bespoke shorthands note, no more `dart run custom_lint`.
  - Add Troubleshooting one-liner for SDK issue [#62173](https://github.com/dart-lang/sdk/issues/62173) (multi-options-file workspaces may break ignore comments).
- [ ] `CHANGELOG.md` — prepend `## [2.0.0] - 2026-05-10` (Keep a Changelog format matching existing `## [1.0.4] - 2025-10-09`):
  - BREAKING: migrated to `analysis_server_plugin`.
  - BREAKING: SDK floor `^3.10.0` / Flutter 3.38+.
  - BREAKING: ignore comment requires `hardcoded_strings_lint/` prefix.
  - BREAKING: removed `// hardcoded.ok` and `// ignore: hardcoded.string` shorthands.
  - `dart run custom_lint` no longer required.
- [ ] Manual verification (per spec `<validation>` checklist):
  - `dart pub get` resolves cleanly in pkg root + `example/`.
  - `dart analyze` zero issues in pkg root.
  - `dart analyze` in `example/` produces expected warnings on `example/lib/main.dart`.
  - Open `example/lib/main.dart` in IDE: WARNING-icon diagnostics inline.
  - Lightbulb shows both fixes; apply each → expected output.
  - `// ignore: hardcoded_strings_lint/avoid_hardcoded_strings_in_widgets` suppresses.
- [ ] Verify: `dart analyze && dart test`.

## Risks / Out of scope

- **Risks**:
  - `analysis_server_plugin ^0.3.15` is pre-1.0 — minor bumps may break. Pin tightly; document volatility in README.
  - `analyzer ^12.x` element-model accessor surprises if SDK shifted again — fallback: fix to current unsuffixed names, do NOT add suffixed.
  - `analyzer_testing` fix-test API not yet inspected — exact assertion helper TBD at impl time.
- **Out of scope**: new lint rules; new acceptable-property/technical-pattern entries; bulk-fix support; user-configurable rule params; backward-compat shims for `createPlugin()`; updates to `example/lib/main.dart`; generated/part-file handling.
