<goal>
Allow consumers to override the lint warning message text and correction message text via their project's analysis_options.yaml, without changing the rule's detection behavior. This lets teams apply project-specific language (e.g. pointing to their own i18n docs) while keeping the same detection logic.
</goal>

<background>
Tech stack: Dart package using analysis_server_plugin ^0.3.15 and analyzer ^13.0.0.

Key files:
- @lib/main.dart — Plugin entry point; registers the rule and two fixes
- @lib/src/avoid_hardcoded_strings_rule.dart — Rule class with LintCode; currently `static const`
- @example/analysis_options.yaml — Reference config showing current plugin YAML shape

Current LintCode (lib/src/avoid_hardcoded_strings_rule.dart:10–16):
```dart
static const LintCode code = LintCode(
  'avoid_hardcoded_strings_in_widgets',
  'Hardcoded string detected in widget ⚠️ ',
  correctionMessage: 'Replace hardcoded string with a variable or localized string.',
  severity: DiagnosticSeverity.WARNING,
);
```

The `register()` method (lib/main.dart:15–22) references `AvoidHardcodedStrings.code` as a static constant for fix registration. This reference is unchanged — `static const LintCode code` is preserved; only `diagnosticCode` is overridden to carry custom messages.

No existing options parsing exists in the plugin. The analysis_server_plugin framework reads only the `diagnostics:` sub-key today.
</background>

<user_flows>
Primary flow (user configures custom messages):
1. User adds an `options:` key under their plugin config in analysis_options.yaml
2. They set `message:` and/or `correction_message:` values
3. The plugin reads these values on first analysis of a file in the project (lazy, not at startup)
4. IDE shows the custom message when a hardcoded string is detected

Alternative flow (user sets only one message):
- Only `message:` or only `correction_message:` is set
- The unset message falls back to the built-in default

Alternative flow (no options key):
- analysis_options.yaml has no `options:` key under the plugin
- Both messages use their built-in defaults — fully backwards-compatible

Error flow (invalid options values):
- Non-string value or empty string for message keys
- Plugin falls back to default message and continues normally (no crash)
</user_flows>

<requirements>
Functional:
1. Users can set a custom primary message via `options.message` in analysis_options.yaml
2. Users can set a custom correction message via `options.correction_message` in analysis_options.yaml
3. Each option is independently optional — both, either, or neither may be set
4. When an option is absent or empty, the current built-in default message is used unchanged
5. The rule name (`avoid_hardcoded_strings_in_widgets`), severity, and detection logic are unchanged
6. Both quick-fix registrations (`AddIgnoreCommentFix`, `ExtractToVariableFix`) continue to work correctly

Configuration shape (analysis_options.yaml):
```yaml
plugins:
  hardcoded_strings_lint:
    options:
      message: "Custom primary warning text"
      correction_message: "Custom correction hint text"
    diagnostics:
      avoid_hardcoded_strings_in_widgets: true
```

Error Handling:
7. Non-string or null `options.message` value → silently use default, no plugin crash
8. Empty string `options.message` value → use default (empty is not a useful message)
9. Unrecognized keys under `options:` are ignored

Edge Cases:
10. `options:` key present but empty (no sub-keys) → both messages use defaults
11. Plugin loaded in a project with no analysis_options.yaml → use defaults
</requirements>

<boundaries>
Edge cases:
- `options:` key with null value (user wrote `options:` with no indented children) → treat as absent
- Very long custom message string → no truncation; pass through as-is
- Message containing special characters or emoji → pass through unchanged (current default already contains ⚠️)

Error scenarios:
- Plugin fails to read or parse YAML → catch exception, fall back to defaults silently
- `analysis_server_plugin` API for reading options unavailable in the current version → fall back to direct filesystem YAML reading (see Implementation)

Limits:
- No validation of message content (content policy is the user's responsibility)
- No live reload of options after IDE startup; an IDE restart is required if messages change (standard plugin behavior)
</boundaries>

<implementation>
Files to modify:

1. `lib/src/avoid_hardcoded_strings_rule.dart`
   - Keep `static const LintCode code` unchanged — it continues to be used for fix registration and is correct as-is
   - Add two nullable instance fields: `String? _customMessage` and `String? _customCorrectionMessage`, both initialized to `null`
   - Add a `bool _optionsRead = false` guard field
   - Override `diagnosticCode` to return a lazily-resolved `LintCode` using the resolved message values:
     ```dart
     @override
     DiagnosticCode get diagnosticCode => LintCode(
       'avoid_hardcoded_strings_in_widgets',
       _customMessage ?? 'Hardcoded string detected in widget ⚠️ ',
       correctionMessage: _customCorrectionMessage ?? 'Replace hardcoded string with a variable or localized string.',
       severity: DiagnosticSeverity.WARNING,
     );
     ```
   - In `registerNodeProcessors()`, read options on first call using the `RuleContext` parameter before creating the visitor:
     ```dart
     if (!_optionsRead) {
       _readOptions(context);
       _optionsRead = true;
     }
     ```
   - Add private `_readOptions(RuleContext context)` method that sets `_customMessage` and `_customCorrectionMessage` (see options reading approach below)

2. `lib/main.dart`
   - No changes needed for fix registration — `AvoidHardcodedStrings.code` remains a valid static reference because the rule name is unchanged
   - No constructor changes — options are read lazily inside the rule itself

3. `README.md`
   - Add `options:` config block example under the configuration/usage section showing both `message:` and `correction_message:` keys with a copy-paste snippet

4. `pubspec.yaml`
   - If filesystem YAML parsing is used (fallback C below): add `package:yaml` as an explicit dependency

---

Options reading approach — implement `_readOptions(RuleContext context)` using the first viable path:

**Step 0 — YAML key validation (do this first before any implementation):** Run the example project with an `options:` key present alongside `diagnostics:` in `analysis_options.yaml`. If `analysis_server_plugin` rejects or warns about the unknown key, switch to a separate config file (`.hardcoded_strings_lint.yaml` at the project root) and adjust the YAML traversal path accordingly.

**A. `RuleContext` options API (preferred):** Inspect `RuleContext` (from `analyzer/analysis_rule/rule_context.dart`) for any method or getter that exposes the analysis options map or the plugin config block. If available, traverse:
```
context.analysisOptions → 'plugins' → 'hardcoded_strings_lint' → 'options' → 'message'
context.analysisOptions → 'plugins' → 'hardcoded_strings_lint' → 'options' → 'correction_message'
```

**B. `AnalysisRule` built-in options hook:** Check `analyzer ^13.0.0`'s `AnalysisRule` or `AbstractAnalysisRule` for an `LintOptionsVisitor`, `withOptions()`, or similar lifecycle method introduced for configurable rules. Use it if present.

**C. Fallback — filesystem YAML reading:** Use `RuleContext` to obtain the analyzed file's path, walk up the directory tree to find `analysis_options.yaml`, parse it with `package:yaml`, and extract the options map. Cache result in `_customMessage` / `_customCorrectionMessage` to avoid re-parsing on every node visit.

**Do not attempt**: Reading options in `Plugin.register()`, `Plugin.start()`, or `Plugin.shutDown()` — these methods have no access to `AnalysisContext` or analysis options.

YAML traversal path (for A and C):
```
root → 'plugins' → 'hardcoded_strings_lint' → 'options' → 'message'
root → 'plugins' → 'hardcoded_strings_lint' → 'options' → 'correction_message'
```

Patterns to follow:
- Minimize changes — only touch what's needed for options plumbing
- Do not change test structure; add new test cases using the existing `AnalysisRuleTest` pattern
- Add `package:yaml` as an explicit dependency in `pubspec.yaml` if filesystem reading is used

What to avoid:
- Do not change the rule name string `'avoid_hardcoded_strings_in_widgets'` — it's used in ignore comments
- Do not crash the plugin if options reading fails for any reason
- Do not read options more than once per analysis context (use the `_optionsRead` guard)
</implementation>

<validation>
Manual testing:
1. Set both custom messages in example/analysis_options.yaml → restart IDE → verify custom text appears in the warning and fix hint
2. Remove `options:` key entirely → verify original default messages appear
3. Set only `message:` → verify custom primary message with default correction message
4. Set only `correction_message:` → verify default primary message with custom correction message
5. Set `message: ""` (empty string) → verify default primary message is used

Automated tests — add to `test/avoid_hardcoded_strings_rule_test.dart`:

Note: `lint(offset, length)` in this project matches by code name only — message text is NOT asserted by default. Use `messageContainsAll:` and `correctionContains:` named parameters on `lint()` to assert message text, or inspect `result.diagnostics.first.message` directly if those parameters are unavailable in `analyzer_testing ^0.2.6`.

- No custom options → diagnostic fires; assert `diagnostic.message` contains `'Hardcoded string detected in widget'`
- `_customMessage = 'Custom warning'` set on rule instance → fire diagnostic; assert `diagnostic.message` contains `'Custom warning'` (e.g. `lint(offset, length, messageContainsAll: ['Custom warning'])`)
- `_customCorrectionMessage = 'Custom correction'` set → assert `diagnostic.correctionMessage` contains `'Custom correction'` (e.g. `correctionContains: 'Custom correction'`)
- Both `_customMessage` and `_customCorrectionMessage` set → assert both fields contain their custom texts
- `_customMessage = ''` (empty string) → assert `diagnostic.message` contains the original default text, not empty string

Fix tests (`test/fixes_test.dart`):
- Existing tests must pass unchanged — the refactor must not alter fix behavior

No strict TDD mandate: this is plumbing/config work. Use the existing `assertDiagnostics` / `assertNoDiagnostics` pattern that tests in this repo already follow.
</validation>

<done_when>
- Setting `options.message` and/or `options.correction_message` in analysis_options.yaml changes the text shown in the IDE warning
- Omitting the `options:` block produces behavior identical to v2.0.0
- All existing tests pass
- New tests covering custom-message scenarios pass
- README documents the new `options:` block with a copy-paste example
</done_when>
