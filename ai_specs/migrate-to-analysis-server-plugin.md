<goal>
Migrate `hardcoded_strings_lint` from the deprecated `custom_lint` / `custom_lint_builder` ecosystem to Dart's official `analysis_server_plugin`, releasing as v2.0.0.

Why this matters:
- `custom_lint` is no longer actively developed; the Dart team has shipped `analysis_server_plugin` as the official replacement for third-party lint plugins.
- Diagnostics will surface natively in `dart analyze` and the IDE without users needing to run `dart run custom_lint` separately.
- The package was reported by a user as needing migration. Future users on Dart 3.10+ will expect the modern plugin model.

Who benefits:
- Existing users of `hardcoded_strings_lint` v1.x who upgrade to Dart 3.10+/Flutter 3.38+.
- New adopters who would otherwise be blocked by the deprecated dependency.

What the outcome is used for:
- A v2.0.0 release on pub.dev that preserves all current detection behavior and both quick fixes, with a clean migration path from v1.x.
</goal>

<background>
Current package state (v1.0.4):
- Built on `custom_lint_builder: ^0.8.1`, `analyzer: ^8.1.1`, Dart SDK `^3.6.0`.
- Single rule `avoid_hardcoded_strings_in_widgets` (severity: WARNING) that walks `StringLiteral` AST nodes and flags hardcoded strings passed directly to Flutter widget constructor arguments.
- Two quick fixes:
  - `_AddIgnoreCommentFix` — inserts `// ignore: avoid_hardcoded_strings_in_widgets` above the offending line.
  - `_ExtractToVariableFix` — extracts the literal to a `const` local (in methods) or `static const` field (in classes), with a generated camelCase identifier.
- Detection logic includes: widget-arg traversal that skips callback bodies, technical-string regex filter (URLs, emails, hex, paths, identifiers), map-key skip, acceptable-property allowlist (e.g. `key`, `heroTag`, `restorationId`, `semanticsLabel`), short-string skip (≤2 chars), and a custom ignore-comment matcher recognizing several legacy patterns including `// hardcoded.ok`.

Target stack (analysis_server_plugin):
- `analysis_server_plugin: ^0.3.15` (publisher: tools.dart.dev, official Dart team).
- `analyzer: ^12.x`, `analyzer_plugin: ^0.14.x`.
- Min Dart SDK `^3.10.0` (Flutter 3.38+) — forced by the new plugin's constraints. Acknowledged breaking change.

Decisions already made (do not re-litigate):
- **Clean break, v2.0.0**. Drop `custom_lint_builder` entirely. No dual-support. v1.x users who can't bump SDK stay pinned to 1.0.4.
- **Add unit tests** for the rule and both fixes. The package currently has zero tests.
- **Quick-fix emits new prefixed ignore syntax**: `// ignore: hardcoded_strings_lint/avoid_hardcoded_strings_in_widgets` (the `<plugin_name>/` prefix is required by analysis_server_plugin's ignore parser).
- **Drop the custom `_hasIgnoreComment` matcher**. Rely on the analyzer's native `// ignore:` / `// ignore_for_file:` handling. The bespoke `// hardcoded.ok` and `// ignore: hardcoded.string` shorthands are removed; documented in CHANGELOG as a breaking change.
- **Keep rule name** `avoid_hardcoded_strings_in_widgets` unchanged.
- **README**: dedicated "Migrating from 1.x" section with before/after `pubspec.yaml` and `analysis_options.yaml` diffs, plus the new ignore-comment prefix note.
- **Example app**: update `pubspec.yaml` and `analysis_options.yaml` only. Leave `lib/main.dart` alone.

Files to examine:
- @lib/hardcoded_strings_lint.dart — current entry point (`createPlugin`).
- @lib/src/hardcoded_strings_lint_base.dart — rule + fix implementations (full rewrite target).
- @pubspec.yaml — dependency / SDK constraints to bump.
- @example/pubspec.yaml, @example/analysis_options.yaml — consumer-side config to update.
- @README.md — Installation, Ignoring Warnings, Configuration sections to revise.
- @CHANGELOG.md — append v2.0.0 entry.

External references for the implementer:
- analysis_server_plugin pub.dev page: https://pub.dev/packages/analysis_server_plugin
- Dart SDK plugin docs (dart-lang/sdk): `pkg/analysis_server_plugin/doc/writing_rules.md` and `writing_fixes.md`.
- Reference migration in the wild: `many_lints` package on pub.dev.
- LeanCode blog post on migrating to analysis_server_plugin (search: "Migrating to Dart Analyzer Plugin System").

Constraints / known gotchas:
- analysis_server_plugin is pre-1.0; pin `analysis_server_plugin` to a tight version range (e.g. `^0.3.15`) and document the volatility.
- Bulk-fix is not yet supported — both fixes must use `CorrectionApplicability.singleLocation`.
- Severity must be locked at registration time via `registry.registerWarningRule(rule)` to preserve the current WARNING level. (`registerWarningRule` is inherited from `RegistryMixin` in `pkg/analyzer/lib/src/lint/registry.dart` and re-exported via `PluginRegistry` — no extra import required.)
- **Element-model accessors are unchanged from v1.** `analyzer 8.0.0` removed element model V1 *and* removed the suffixed accessors (`.element2`, `.element3`, `.name2`, `.name3`); analyzer 12 keeps the unsuffixed names (`.element`, `.supertype`, `.name`) as canonical. v1's `_extendsWidget` walk via `current.supertype.element as ClassElement` is expected to compile as-is under `analyzer ^12.x` — verify, but do **not** preemptively migrate to suffixed forms.
- The `LintCode` constructor in `analyzer ^12.x` no longer accepts `errorSeverity:`. Severity is set at registration time. Drop the existing `errorSeverity: DiagnosticSeverity.WARNING` argument from the `LintCode` literal.
- No `TypeChecker` helper from custom_lint_builder; widget-type detection must use raw analyzer types.
- `analyzer_plugin` is currently a transitive dependency listed in `pubspec.yaml` but the source has zero direct `package:analyzer_plugin/...` imports. It is a clean drop in v2.0.0 — no conditional needed.
- The new ignore-comment syntax requires the `hardcoded_strings_lint/` prefix; existing user ignore comments in v1.x format will silently stop working. This is documented; not a code-level concern.
</background>

<requirements>
**Functional:**

1. The package builds and analyzes successfully under `analyzer ^12.x` and `analysis_server_plugin ^0.3.15` with Dart SDK `^3.10.0`.

2. The plugin entry point is exposed as a top-level `final plugin = HardcodedStringsPlugin();` in `lib/hardcoded_strings_lint.dart`. The `Plugin` subclass overrides `name` (returning `'hardcoded_strings_lint'`) and `register(PluginRegistry)`, which must:
   - Construct an instance of the rule class.
   - Call `registry.registerWarningRule(rule)` to register the rule with WARNING severity. This method is inherited from `RegistryMixin` (in `pkg/analyzer/lib/src/lint/registry.dart`) and re-exported via `PluginRegistry`; no extra import is needed.
   - Call `registry.registerFixForRule(<rule>.code, AddIgnoreCommentFix.new)`. The first parameter is typed `DiagnosticCode` (the supertype of `LintCode`); passing `<rule>.code` works covariantly.
   - Call `registry.registerFixForRule(<rule>.code, ExtractToVariableFix.new)`.
   - Pass constructor tear-offs (`MyFix.new`), not instances — `registerFixForRule`'s second parameter is a `ProducerGenerator`.

3. The rule is implemented as a single `AnalysisRule` subclass in `lib/src/avoid_hardcoded_strings_rule.dart`:
   - Static `const LintCode code` with `'avoid_hardcoded_strings_in_widgets'` as the rule name, problem message `'Hardcoded string detected in widget ⚠️ '`, correction message `'Replace hardcoded string with a variable or localized string.'`. **Do not** pass `errorSeverity:` — that constructor parameter is removed in `analyzer ^12.x`; severity is set at registration time via `registerWarningRule`.
   - Constructor passes `name: 'avoid_hardcoded_strings_in_widgets'` and a description string to `super(...)`.
   - Override `DiagnosticCode get diagnosticCode => code;` (the override returns the `DiagnosticCode` supertype; returning a `LintCode` instance is valid covariantly).
   - Override `registerNodeProcessors(RuleVisitorRegistry registry, RuleContext context)` and register the **same visitor instance for all three string-literal subtypes** to preserve v1 detection parity. `RuleVisitorRegistry` has **no `addStringLiteral`** umbrella method — you must call all three explicitly:
     - `registry.addSimpleStringLiteral(this, visitor);`
     - `registry.addAdjacentStrings(this, visitor);`
     - `registry.addStringInterpolation(this, visitor);`
     The visitor must extend `SimpleAstVisitor<void>` and override `visitSimpleStringLiteral`, `visitAdjacentStrings`, and `visitStringInterpolation` accordingly. (For `StringInterpolation`, `node.stringValue` is null so the existing early-skip guards naturally suppress reporting — preserve that behavior.)
   - The visitor reports diagnostics via `rule.reportAtNode(node)`.

4. The visitor preserves all current filtering behavior, ported verbatim where the API allows:
   - `_isPassedToWidget(node)` — must still walk to the nearest `ArgumentList` ancestor, return false if any `FunctionExpression` or `FunctionBody` is encountered between `node` and that ancestor, require the `ArgumentList`'s parent to be an `InstanceCreationExpression`, and require the constructed type to extend a Flutter widget base class.
   - `_isFlutterWidget` / `_extendsWidget` — walk the supertype chain and match against the existing `_isWidgetBaseClass` allowlist (`Widget`, `StatelessWidget`, `StatefulWidget`, `InheritedWidget`, `RenderObjectWidget`, `LeafRenderObjectWidget`, `SingleChildRenderObjectWidget`, `MultiChildRenderObjectWidget`, `ProxyWidget`, `ParentDataWidget`, `InheritedTheme`, `PreferredSizeWidget`). Adjust the element-access API to whatever `analyzer ^12.x` exposes; do not silently drop classes that no longer have the same accessor.
   - `_isAcceptableWidgetProperty(node)` — preserve the full property allowlist verbatim (`semanticsLabel`, `excludeSemantics`, `restorationId`, `heroTag`, `key`, `debugLabel`, `fontFamily`, `package`, `name`, `asset`, `tooltip`, `textDirection`, `locale`, `materialType`, `clipBehavior`, `crossAxisAlignment`, `mainAxisAlignment`, `textAlign`, `textBaseline`, `overflow`, `softWrap`, `textScaleFactor`).
   - `_isTechnicalString(value)` — preserve the full regex set verbatim (URL, email, hex, number+unit, CONSTANT_CASE, snake_case, file path, dotted notation, file extension, identifier-with-numbers/underscores).
   - `_isMapKey(node)` — preserve `IndexExpression.index` and `MapLiteralEntry.key` checks.
   - Skip empty strings and strings of length ≤ 2.

5. **Remove** the custom `_hasIgnoreComment` and `_containsIgnoreComment` methods entirely. Do not re-implement them. The analyzer handles `// ignore: hardcoded_strings_lint/avoid_hardcoded_strings_in_widgets` and `// ignore_for_file:` natively.

6. The "Add ignore comment" fix is a `ResolvedCorrectionProducer` subclass in `lib/src/fixes.dart`:
   - Static `const FixKind` named `'dart.fix.addIgnoreHardcodedString'`, label `"Add '// ignore' comment"`, priority `DartFixKindPriority.standard`.
   - `applicability => CorrectionApplicability.singleLocation`.
   - `compute(ChangeBuilder)` inserts `// ignore: hardcoded_strings_lint/avoid_hardcoded_strings_in_widgets\n` (with leading indentation matching the offending line) above the line containing the diagnostic. Indentation derivation logic ports from v1 (`_AddIgnoreCommentFix.run`).
   - Constructor signature `AddIgnoreCommentFix({required super.context});` so the constructor tear-off `AddIgnoreCommentFix.new` is a valid `ProducerGenerator`.

7. The "Extract to variable" fix is a `ResolvedCorrectionProducer` subclass in `lib/src/fixes.dart`:
   - Static `const FixKind` named `'dart.fix.extractHardcodedStringToVariable'`, label `'Extract to variable'`, priority lower than the ignore fix.
   - `applicability => CorrectionApplicability.singleLocation`.
   - `compute(ChangeBuilder)` walks ancestors to find the enclosing `MethodDeclaration` or `ClassDeclaration` (matching v1 behavior). For methods with a `BlockFunctionBody`, insert `\n    const $variableName = <original source>;\n` after the block's `leftBracket` and replace the literal's source range with `$variableName`. For class declarations, insert `\n  static const $variableName = <original source>;\n` after the class's `leftBracket`.
   - `_generateVariableName(stringValue)` — port verbatim: strip non-word/space, lowercase, take first 3 words, camelCase, append `Text` suffix; fallback to `'textValue'` for empty input.

8. Update `pubspec.yaml`:
   - `version: 2.0.0`.
   - `environment.sdk: ^3.10.0`.
   - Drop `custom_lint_builder`.
   - **Drop `analyzer_plugin` unconditionally.** Verified: the current source has zero direct `package:analyzer_plugin/...` imports. It is a leftover transitive dep from the custom_lint setup.
   - Add `analysis_server_plugin: ^0.3.15`.
   - Bump `analyzer` to `^12.1.0` (or whatever is pulled in by `analysis_server_plugin ^0.3.15`'s lower bound — check resolution and use that floor).

9. Update the example app:
   - `example/pubspec.yaml`: drop `custom_lint` and `analyzer` direct dependencies. The `hardcoded_strings_lint: { path: ../ }` entry moves from `dependencies` to nothing — the new plugin model loads through `analysis_options.yaml` only. Bump `environment.sdk` to `^3.10.0`.
   - `example/analysis_options.yaml`: remove `analyzer.plugins: [custom_lint]`. Add a top-level `plugins:` block. **Critical YAML structure**: `diagnostics:` is *nested under the plugin name*, not a sibling:
     ```yaml
     plugins:
       hardcoded_strings_lint:
         path: ../
         diagnostics:
           avoid_hardcoded_strings_in_widgets: true
     ```
     Path-based local plugins are supported by `analysis_server_plugin` (see `pkg/analysis_server_plugin/doc/using_plugins.md`). Absolute paths are recommended in the official docs but relative paths resolve against the analysis options file's location. No workaround needed for local development.
   - Leave `example/lib/main.dart` unchanged.

10. Update `README.md`:
    - Bump version reference to `^2.0.0` in the install snippet.
    - Replace the `dev_dependencies` install instructions with the new `analysis_options.yaml`-based plugin config.
    - **Mandatory full-file `custom_lint` sweep.** Currently `custom_lint` is referenced at lines **39** (`custom_lint: ^0.8.1` in install snippet), **51** (`analyzer.plugins: - custom_lint`), **68** (`dart run custom_lint`), and **278–281** (Troubleshooting bullets: "Ensure `custom_lint` is added to `dev_dependencies`", "Verify `analyzer.plugins` includes `custom_lint`...", "Run `dart run custom_lint`"). After edits, `grep -n "custom_lint" README.md` must return **zero matches** unless inside the "Migrating from 1.x" historical-context section.
    - Rewrite the **Troubleshooting → Rule Not Running** section for the new plugin model: (a) ensure `hardcoded_strings_lint` is listed under `plugins:` in `analysis_options.yaml`, (b) restart the analyzer / IDE, (c) run `dart pub get`, (d) run `dart analyze`. No `dart run custom_lint` step.
    - Update every example ignore comment in the README to use the new prefixed form: `// ignore: hardcoded_strings_lint/avoid_hardcoded_strings_in_widgets`. Remove the `// hardcoded.ok` and `// ignore: hardcoded.string` examples (those shorthands no longer work).
    - Add a new top-level section "## Migrating from 1.x" containing:
      - One-paragraph summary of why (custom_lint deprecation, official plugin system).
      - Before/after diff of `pubspec.yaml` (drop `custom_lint`, drop `dev_dependencies` entry, mention SDK floor bump).
      - Before/after diff of `analysis_options.yaml` (remove `analyzer.plugins`, add `plugins:` block — using the correctly nested `diagnostics:` structure shown in requirement #9).
      - Note on the new ignore-comment prefix and that bespoke `// hardcoded.ok` shorthand is removed.
      - Note that `dart run custom_lint` is no longer needed.

11. Update `CHANGELOG.md`: prepend a `## [2.0.0] - <release date>` entry following the existing Keep a Changelog format used in `CHANGELOG.md` (e.g. `## [1.0.4] - 2025-10-09`). Document:
    - Migrated to `analysis_server_plugin` (BREAKING).
    - SDK floor bumped to `^3.10.0` / Flutter 3.38+ (BREAKING).
    - Ignore comment syntax now requires `hardcoded_strings_lint/` prefix (BREAKING).
    - Removed legacy `// hardcoded.ok` and `// ignore: hardcoded.string` shortcut patterns (BREAKING).
    - `dart run custom_lint` no longer required.

12. Add unit tests under `test/` using the **official `package:analyzer_testing` harness**, not raw `parseString`:
    - `test/avoid_hardcoded_strings_rule_test.dart` — covers all major detection branches (see `<validation>`).
    - `test/fixes_test.dart` — covers both quick fixes' output.
    - Add to `dev_dependencies`:
      - `analyzer_testing: <version compatible with analyzer ^12.x>` (resolve at implementation time).
      - `test_reflective_loader: ^0.2.x` (used by `analyzer_testing`'s `AnalysisRuleTest` base class).
      - Keep `test: ^1.26.3` and `lints: ^6.0.0` (verify they resolve under SDK 3.10).
    - Test pattern: extend `AnalysisRuleTest` (from `package:analyzer_testing`), override `setUp` to assign `rule = AvoidHardcodedStrings()`, then write per-test methods that call `assertDiagnostics(code, [lint(offset, length)])` for positive cases and `assertNoDiagnostics(code)` for negative cases. This harness handles registry plumbing AND element resolution — `parseString` does not provide resolved element types and would not exercise the widget-detection logic.
    - For fix tests, use the fix-specific harness from `analyzer_testing` (e.g. `assertFixContents` or equivalent — implementer should follow `pkg/analysis_server_plugin/doc/testing_rules.md` for the canonical pattern).

**Error Handling:**

13. If `analysis_server_plugin` cannot resolve the type of a constructor invocation (`staticType` is null or `Element` is null), treat the call as a non-widget and skip — match v1 behavior, do not throw.

14. The "Extract to variable" fix must no-op gracefully (do not throw, do not produce a partial edit) if no enclosing `MethodDeclaration` or `ClassDeclaration` is found. Match v1 behavior.

15. Both fixes must handle the case where `node.stringValue` is null (interpolated/adjacent strings) — the fix should either skip producing an edit or apply only when `stringValue` is non-null. Same as v1.

**Edge Cases:**

16. String literals inside callback bodies of widget constructor arguments (e.g. `BlocListener(listener: (ctx, state) { logger.info('skip me'); })`) must NOT be flagged. The `FunctionExpression`/`FunctionBody` walk-up check is critical — preserve and test.

17. String literals used as map keys (`map['key']` or `{'key': value}`) must NOT be flagged. Test both forms.

18. String literals matching technical patterns (URLs, emails, hex colors, file paths, snake_case, CONSTANT_CASE, package.asset) must NOT be flagged regardless of whether they are passed to a widget. Test at least one example per pattern category.

19. String literals on properties in the acceptable-property allowlist (e.g. `Hero(tag: 'my_tag')`, `Image.asset('assets/logo.png')`, `Semantics(label: 'Nav')`) must NOT be flagged. Test at least three.

20. Ignore comments using the new prefixed form (`// ignore: hardcoded_strings_lint/avoid_hardcoded_strings_in_widgets`) must suppress the diagnostic. This is handled by the analyzer; verify in an integration-style test against the example app rather than a unit test.

21. The "Add ignore comment" fix on a deeply indented line (e.g. inside multiple `Column(children:[…])` levels) must preserve the original indentation when inserting the comment. Test.

22. The "Extract to variable" fix on a string with non-word characters (e.g. `'Hello, World!'`) must produce a clean camelCase identifier (`helloWorldText`). Test.

23. The "Extract to variable" fix on a numeric-only or punctuation-only string must fall back to `'textValue'` without crashing.

**Validation:**

24. All input parameters use the analyzer's standard `AnalysisRule` / `RuleContext` plumbing — no manual constructor-argument validation required.
</requirements>

<boundaries>
Edge cases:
- **Adjacent string literals** (`'foo' 'bar'`): the rule visits each `SimpleStringLiteral` individually under v1's `addStringLiteral`. Decide explicitly whether to register `addAdjacentStrings` separately or rely on per-fragment visitation; document the choice and ensure it matches v1's observed behavior.
- **String interpolation** (`'Hello $name'`): currently, `node.stringValue` returns null for non-pure interpolations, so the early-skip guards prevent reporting. Preserve this behavior.
- **Const constructors and `const` widgets**: the static type / element resolution still works for `const` invocations. No special-case needed.
- **Nested widget constructors as arguments** (`Padding(child: Text('hi'))`): the inner string belongs to `Text`'s argument list, not `Padding`'s. The `thisOrAncestorOfType<ArgumentList>()` returns the *nearest* one, which is correct. Preserve and test.
- **Generated files / part files**: out of scope for this migration. The analyzer's `// ignore_for_file:` handling remains the user's escape hatch.

Error scenarios:
- **`analysis_server_plugin` API drift**: if a minor version bump between `0.3.15` and the time of release introduces breaking changes, pin the dependency exactly (e.g. `analysis_server_plugin: '0.3.15'`) and document the volatility in the README.
- **Element model API**: under `analyzer ^12.x`, the unsuffixed accessors (`.element`, `.supertype`, `.name`) are canonical — the suffixed `.element2` / `.element3` / `.name2` / `.name3` were *removed* in `analyzer 8.0.0`. v1's supertype walk should compile as-is; if it doesn't, fix to whatever the current unsuffixed API exposes — do **not** add suffixed accessors.
- **Ignore-comment workspace bug** (SDK issue [#62173](https://github.com/dart-lang/sdk/issues/62173)): the `// ignore: plugin_name/rule_code` form has known misbehavior when a project has multiple `analysis_options.yaml` files in the same workspace. Add a one-line caveat to README → Troubleshooting noting that users in workspaces may see ignore comments not take effect; tracking upstream.
- **Plugin not loading in IDE**: out of scope for this spec; users are expected to restart their analyzer per standard plugin workflow.

Limits:
- **No new lint rules** added in this migration. Behavior parity only.
- **No new acceptable-property entries** or technical-string patterns. Behavior parity only.
- **No bulk fix support** — `CorrectionApplicability.singleLocation` for both fixes (analysis_server_plugin doesn't support bulk yet).
- **No user-configurable rule parameters** — the new plugin system only supports enable/disable booleans. The hard-coded allowlists and regex patterns stay hard-coded.
</boundaries>

<implementation>
Files to create:
- `lib/src/avoid_hardcoded_strings_rule.dart` — new home for the `AnalysisRule` subclass and its visitor.
- `lib/src/fixes.dart` — new home for `AddIgnoreCommentFix` and `ExtractToVariableFix` (`ResolvedCorrectionProducer` subclasses).
- `test/avoid_hardcoded_strings_rule_test.dart` — unit tests for detection.
- `test/fixes_test.dart` — unit tests for fixes.

Files to modify:
- `lib/hardcoded_strings_lint.dart` — replace `createPlugin()` factory with top-level `plugin` instance and `Plugin` subclass.
- `pubspec.yaml` — version bump, SDK floor bump, dependency swap.
- `example/pubspec.yaml` — drop `custom_lint` / `analyzer`, bump SDK floor.
- `example/analysis_options.yaml` — replace `analyzer.plugins` block with `plugins:` block.
- `README.md` — update install / config / ignore sections, add "Migrating from 1.x" section.
- `CHANGELOG.md` — prepend `## 2.0.0` entry.

Files to delete:
- `lib/src/hardcoded_strings_lint_base.dart` — the old monolith. Its content is split between `avoid_hardcoded_strings_rule.dart` and `fixes.dart`. Delete after extracting the salvageable detection logic.

Patterns / libraries to use:
- `package:analyzer/analysis_rule/analysis_rule.dart` — `AnalysisRule`, `LintCode`.
- `package:analyzer/analysis_rule/rule_context.dart` — `RuleContext`.
- `package:analyzer/analysis_rule/rule_visitor_registry.dart` — `RuleVisitorRegistry`.
- `package:analyzer/dart/ast/ast.dart`, `package:analyzer/dart/ast/visitor.dart` — `SimpleAstVisitor`, AST node types.
- `package:analysis_server_plugin/plugin.dart` — `Plugin` base class.
- `package:analysis_server_plugin/registry.dart` — `PluginRegistry` and `register*Rule` / `registerFixForRule` APIs.
- `package:analysis_server_plugin/edit/correction_producer.dart` (or equivalent path) — `ResolvedCorrectionProducer`, `FixKind`, `DartFixKindPriority`, `CorrectionApplicability`, `ChangeBuilder`. Verify the exact import paths against the published `0.3.15` package layout.

What to avoid and why:
- **Do not preserve the custom `_hasIgnoreComment` matcher.** The analyzer handles `// ignore:` natively; duplicating it leaks v1 behavior into v2 and confuses users about which form is canonical.
- **Do not import from `package:custom_lint_builder/...`.** The migration's whole point is removing this dependency. The implementer must replace every such import.
- **Do not reuse the v1 file `hardcoded_strings_lint_base.dart` as-is.** Splitting the rule and fixes into separate files matches the new ecosystem's conventions and keeps each `ResolvedCorrectionProducer` focused.
- **Do not introduce new abstractions** — no shared base classes for the two fixes, no helper singletons. The two fixes have minimal shared state; a one-line shared constant for the ignore-comment template is the maximum.
- **Do not bump `analysis_server_plugin` to a non-existent or unstable version.** Verify `^0.3.15` resolves at implementation time; if a newer stable version exists, prefer it but pin tightly.
- **Do not add backward-compat shims** for the deprecated `createPlugin()` entry. v2.0.0 is a clean break; both old and new entry points cannot coexist.
- **Do not change the rule name, problem message, or correction message.** The user-facing diagnostic text is part of the v1.x contract that should be preserved verbatim where possible.
</implementation>

<validation>
**Test framework**: `package:analyzer_testing` (official harness for `AnalysisRule` plugins) plus `package:test_reflective_loader`. Reference: `pkg/analysis_server_plugin/doc/testing_rules.md`.

Pattern:
- Test classes extend `AnalysisRuleTest` (or its lint-rule subclass) from `package:analyzer_testing`.
- `setUp` assigns `rule = AvoidHardcodedStrings()` and configures the in-memory test resource provider.
- Each test method calls `assertDiagnostics(code, [lint(offset, length)])` for cases that must report, or `assertNoDiagnostics(code)` for cases that must not.
- Fix tests use the fix-specific harness (`assertFixContents` or equivalent — follow whatever `analyzer_testing` exposes at the chosen version) to assert on the post-fix source.

Why this harness, not `parseString`: the rule depends on `staticType` for widget-element detection. `parseString` returns unresolved AST. `resolveFile2` works but requires a heavyweight `AnalysisContextCollection` per test. `analyzer_testing` handles registry plumbing, element resolution, and ignore-comment processing in a single base class.

**Baseline automated coverage outcomes** (mandatory):

*Logic / business rules — `test/avoid_hardcoded_strings_rule_test.dart`:*
- ✅ Reports a diagnostic for `Text('Hello world')`.
- ✅ Does NOT report for `Text('a')` (≤2 chars).
- ✅ Does NOT report for `Text('')` (empty).
- ✅ Does NOT report for `Text('https://example.com')` (URL pattern).
- ✅ Does NOT report for `Text('user@example.com')` (email pattern).
- ✅ Does NOT report for `Text('#FF5722')` (hex color).
- ✅ Does NOT report for `Text('snake_case_value')` (snake_case pattern).
- ✅ Does NOT report for `Text('CONSTANT_VALUE')` (CONSTANT_CASE).
- ✅ Does NOT report for `Text('package.asset')` (dotted notation).
- ✅ Does NOT report for `Hero(tag: 'my_tag', child: ...)` (acceptable property).
- ✅ Does NOT report for `Image.asset('assets/logo.png')` (acceptable property).
- ✅ Does NOT report for `Semantics(label: 'Nav', child: ...)` (acceptable property).
- ✅ Does NOT report for `map['some key']` (IndexExpression).
- ✅ Does NOT report for `{'some key': value}` (MapLiteralEntry).
- ✅ Does NOT report for `BlocListener(listener: (ctx, state) { logger.info('skip me'); })` (string inside FunctionBody — critical regression test for the v1.0.4 fix).
- ✅ Does NOT report for non-widget calls: `print('hello')`, `myFunction('hello')`.
- ✅ Reports for custom widgets that extend `StatelessWidget` / `StatefulWidget`.
- ✅ Reports for adjacent strings passed to a widget: `Text('foo' 'bar')` (verifies `addAdjacentStrings` registration from requirement #3 — visit each fragment).
- ✅ Does NOT report for interpolated strings: `Text('Hello \$name')` (`StringInterpolation` has `stringValue == null`, so the empty-string guard skips it).
- ✅ Suppression test (integration-flavored, run via `analyzer_testing`'s ignore-comment support): `// ignore: hardcoded_strings_lint/avoid_hardcoded_strings_in_widgets\nText('Hello world')` produces no diagnostics.

*Fix behavior — `test/fixes_test.dart`:*
- ✅ "Add ignore comment" inserts `// ignore: hardcoded_strings_lint/avoid_hardcoded_strings_in_widgets` above the line and preserves the line's leading indentation.
- ✅ "Extract to variable" inside a method body produces `const helloWorldText = 'Hello world';` at the start of the block and replaces the literal call site with `helloWorldText`.
- ✅ "Extract to variable" at class scope produces `static const helloWorldText = 'Hello world';` after the class's `{` and replaces the literal call site with `helloWorldText`.
- ✅ "Extract to variable" generates `textValue` for an all-punctuation string `'!!!'` (length > 2 to bypass short-string skip — use `'!!!!!'`).
- ✅ "Extract to variable" with no enclosing method or class no-ops without throwing.

*UI behavior*: N/A — this is a pure analyzer plugin with no UI.

*Critical user journeys*: the canonical journey is "user enables the lint, hardcoded string in a widget is flagged in their IDE, user applies a quick fix". Validate this manually once after implementation by running the example app's analyzer against `example/lib/main.dart` and confirming:
- Diagnostics appear under `dart analyze` output (no separate `dart run custom_lint` needed).
- Both quick fixes appear in the IDE's lightbulb menu when the cursor is on a flagged string.
- Adding `// ignore: hardcoded_strings_lint/avoid_hardcoded_strings_in_widgets` above a flagged line suppresses the diagnostic.

**TDD expectations** (since the rule is pure logic with deterministic outputs):
- Behavior-first slices, in order: (1) reports on basic widget hardcoded string → (2) skips short / empty / map-key strings → (3) skips technical patterns → (4) skips acceptable properties → (5) skips strings inside callback bodies → (6) skips strings in non-widget calls. Each slice is one RED → GREEN → REFACTOR cycle.
- For fixes: (1) ignore-comment fix produces the expected text → (2) ignore-comment fix preserves indentation → (3) extract fix at method scope → (4) extract fix at class scope → (5) extract fix's variable-name generation edge cases.
- Testability seams: the visitor logic is exposed through the `AnalysisRule` API. No additional injection seams are required because the rule has no external dependencies (no I/O, no time, no randomness).
- Mocking policy: prefer real `analyzer.parseString` results over mocked AST — fakes here would be more error-prone than the real parser. No external boundaries to mock.
- Justified exceptions: integration-level "ignore-comment suppresses diagnostic" is verified manually against the example app, not unit-tested, because reproducing the analyzer's ignore-handling pipeline in a unit test is disproportionate effort.

**Manual verification checklist** (run after the unit tests pass):
- [ ] `dart pub get` in package root resolves cleanly.
- [ ] `dart analyze` on the package itself reports no issues.
- [ ] `dart pub get` in `example/` resolves cleanly.
- [ ] `dart analyze` on `example/` reports the expected diagnostics on `lib/main.dart`'s hardcoded strings.
- [ ] Open `example/lib/main.dart` in VS Code or IntelliJ — diagnostics appear inline with the WARNING severity icon.
- [ ] Cursor on a flagged string → lightbulb shows both "Add ignore comment" and "Extract to variable".
- [ ] Apply "Add ignore comment" → produces `// ignore: hardcoded_strings_lint/avoid_hardcoded_strings_in_widgets` with correct indentation, and the diagnostic disappears.
- [ ] Apply "Extract to variable" inside a `build` method → produces a `const` local at the top of the method and replaces the literal.
</validation>

<done_when>
- `pubspec.yaml` declares `version: 2.0.0`, `sdk: ^3.10.0`, depends on `analysis_server_plugin: ^0.3.15` and `analyzer: ^12.x`, no longer depends on `custom_lint_builder` or `analyzer_plugin`. All `dev_dependencies` (including new `analyzer_testing`, `test_reflective_loader`, retained `test`, `lints`) resolve cleanly under the new SDK / analyzer floor; any forced version bumps are recorded in the CHANGELOG.
- `lib/hardcoded_strings_lint.dart` exposes a top-level `final plugin = HardcodedStringsPlugin();`. No `createPlugin()` factory remains.
- `lib/src/hardcoded_strings_lint_base.dart` is deleted; its logic is split across `lib/src/avoid_hardcoded_strings_rule.dart` and `lib/src/fixes.dart`.
- `dart analyze` on the package root reports zero issues.
- `dart test` passes all unit tests in `test/` using the `analyzer_testing` harness (rule behavior + fix behavior, per `<validation>`), including: adjacent-string positive case, interpolation negative case, and ignore-comment suppression case.
- `example/pubspec.yaml` and `example/analysis_options.yaml` use the new `plugins:` block; `dart pub get` and `dart analyze` succeed in `example/`.
- Running `dart analyze` against `example/lib/main.dart` produces the expected hardcoded-string warnings without invoking `dart run custom_lint`.
- `README.md` Installation, Ignoring Warnings, Configuration, and Troubleshooting sections reflect the new plugin model. A "Migrating from 1.x" section is present with correctly-nested `plugins:` / `diagnostics:` YAML, and `grep -n "custom_lint" README.md` returns zero matches outside the migration section.
- `CHANGELOG.md` has a `## [2.0.0] - <date>` entry (matching existing Keep a Changelog format) documenting all breaking changes (SDK floor, plugin system, ignore-prefix, removed shorthands, no more `dart run custom_lint`).
- Manual verification checklist in `<validation>` is fully ticked.
</done_when>
