<goal>
Fix quick fix options 4 and 5 ("Ignore for whole file", "Ignore in analysis_options.yaml") so they actually suppress the lint after being applied. Add a working "Ignore for file" fix and a working "Ignore in analysis_options.yaml" fix as custom producers.

Option 3 ("Ignore for this line") is structurally broken by the framework (see background) and cannot be fixed from the plugin. It is accepted as-is. Option 1 (`AddIgnoreCommentFix`) already provides the working "Ignore for this line" path. Options 1 and 2 are unaffected.
</goal>

<background>
Plugin: `hardcoded_strings_lint` — a Dart/Flutter analysis plugin.
Rule: `AvoidHardcodedStrings`, diagnostic code `avoid_hardcoded_strings_in_widgets`.
Relevant files:
- `lib/src/avoid_hardcoded_strings_rule.dart` — rule + `LintCode` definition
- `lib/src/fixes.dart` — existing custom fix producers (`AddIgnoreCommentFix`, `ExtractToVariableFix`)
- `lib/main.dart` — plugin registration via `PluginRegistry`
- `test/fixes_test.dart` — existing fix tests

Root cause (verified against framework source):

1. **Why built-in ignore comments don't suppress the lint**: The analyzer's ignore mechanism (`analyzer/src/ignore_comments/ignore_info.dart`, `IgnoredDiagnosticName._matches`) requires that the plugin-name prefix in the comment matches the `pluginName` passed at runtime. `pluginName` is always `configuration.name` = `'hardcoded_strings_lint'` (set in `plugin_server.dart:581`). A comment without the prefix (e.g. `// ignore: avoid_hardcoded_strings_in_widgets`) has `this.pluginName = null`, which never equals `'hardcoded_strings_lint'` → the diagnostic is NOT suppressed. Only the prefixed form `// ignore: hardcoded_strings_lint/avoid_hardcoded_strings_in_widgets` works.

2. **Why the built-in fixes produce the non-prefixed form**: The built-in `_BaseIgnoreDiagnostic._code` getter (in `analysis_server_plugin/src/correction/ignore_diagnostic.dart`) loops `PluginServer.registries` to find the plugin name. When the `PluginServer(...)` old constructor is used, registries are stored under numeric string keys (`'0'`, `'1'`, …). The loop explicitly skips numeric keys: `if (int.tryParse(entry.key) != null) { continue; }`. The plugin is never found, and `_code` falls back to the un-prefixed name. The `PluginServer.new2` constructor (which uses plugin-name keys) would fix this, but plugin authors cannot control which constructor the analysis server uses.

3. **Why `analyzer.errors` doesn't suppress plugin diagnostics**: The built-in `IgnoreInAnalysisOptionsFile` writes `analyzer.errors.avoid_hardcoded_strings_in_widgets: ignore`. This has no effect on plugin-defined diagnostics. `plugin_server.dart` suppresses diagnostics only via `ignoreInfo.ignored(e, pluginName:)` (comment-based ignores). The `analysisOptions.errorProcessors` path is never consulted for plugin rules.

4. **Correct `analysis_options.yaml` suppression path**: Setting `plugins.hardcoded_strings_lint.diagnostics.avoid_hardcoded_strings_in_widgets: false` causes the analyzer to parse `ConfiguredSeverity.disable` for that diagnostic (`analyzer/src/lint/config.dart:90–93`), which excludes the rule from `registry.enabled()` in `plugin_server.dart:575`. This is the only `analysis_options.yaml` mechanism that disables the plugin rule.

Our working option 1 (`AddIgnoreCommentFix`) uses:
  `const _ignoreCommentText = '// ignore: hardcoded_strings_lint/avoid_hardcoded_strings_in_widgets';`
This is exactly the correct format.
</background>

<requirements>
**Functional:**
1. The user must have a working path to suppress the lint for the whole file. Implement `IgnoreForFileFix` to insert `// ignore_for_file: hardcoded_strings_lint/avoid_hardcoded_strings_in_widgets`.
2. The user must have a working path to suppress the lint project-wide. Implement `IgnoreInAnalysisOptionsFix` to write `diagnostics.avoid_hardcoded_strings_in_widgets: false` under the `plugins.hardcoded_strings_lint` section of `analysis_options.yaml`.
3. Option 3 ("Ignore for this line") — built-in, framework bug, out of scope. Option 1 already satisfies the "Ignore for this line" need.

**Error Handling:**
4. `IgnoreInAnalysisOptionsFix`: if `analysis_options.yaml` cannot be located (no project root, or `context.package?.root.path` returns null), return early — no change.
5. `IgnoreInAnalysisOptionsFix`: if the rule is already set to `false` (or `disable`) in the diagnostics section, the producer must be a no-op.
6. `IgnoreForFileFix`: if the file already contains `// ignore_for_file: hardcoded_strings_lint/avoid_hardcoded_strings_in_widgets` (as a standalone entry or appended to an existing `ignore_for_file` line), the producer must be a no-op.
7. `IgnoreInAnalysisOptionsFix`: if `analysis_options.yaml` contains invalid YAML that `YamlEditor` cannot parse, catch the `YamlException` and return early.

**Out of scope:**
- Changing behavior of working options 1 and 2.
- Modifying `_ignoreCommentText` constant (option 1 continues unchanged).
- Fixing or removing the broken built-in options 3–5.
</requirements>

<implementation>
Files to modify:
- `lib/src/fixes.dart` — add `IgnoreForFileFix` and `IgnoreInAnalysisOptionsFix` classes.
- `lib/main.dart` — register the two new producers with `registry.registerFixForRule`.

Files to modify (tests):
- `test/fixes_test.dart` — add `IgnoreForFileFixTest` and `IgnoreInAnalysisOptionsFixTest` test classes.

Constants:
```dart
const _ignoreForFileCommentText =
    '// ignore_for_file: hardcoded_strings_lint/avoid_hardcoded_strings_in_widgets';
```

**`IgnoreForFileFix` — insertion algorithm:**
Mirror the logic of `IgnoreDiagnosticInFile` in `analysis_server_plugin/src/correction/ignore_diagnostic.dart`:
1. Scan the file's leading lines from the top.
2. If an existing `// ignore_for_file:` comment is found: append ` hardcoded_strings_lint/avoid_hardcoded_strings_in_widgets,` immediately after the `:`.
3. Track the last blank line in the header comment block; if found, insert the new comment after it with a leading blank line.
4. Otherwise insert the new comment before the first line of code with a trailing blank line.
Use `builder.addDartFileEdit(file, ...)` — not `dart:io`.

**`IgnoreInAnalysisOptionsFix` — YAML manipulation:**
Use `builder.addYamlFileEdit(analysisOptionsFile.path, ...)` with `YamlEditor` (already a transitive dependency in `pubspec.lock`). Do NOT use `dart:io` writes — those bypass the IDE's change-preview mechanism.

Target path in `analysis_options.yaml`:
```yaml
plugins:
  hardcoded_strings_lint:
    diagnostics:
      avoid_hardcoded_strings_in_widgets: false
```

Locate `analysis_options.yaml` via `(analysisOptions as AnalysisOptionsImpl).file` — the same pattern used in the built-in `IgnoreInAnalysisOptionsFile` producer. If the file is null, return early (requirement 4).

Build the nested path with `YamlEditor.update()`:
- If `plugins` key is absent → insert the full nested map.
- If `plugins.hardcoded_strings_lint` is absent → insert from there.
- If `diagnostics` key is absent → insert `{avoid_hardcoded_strings_in_widgets: false}`.
- Otherwise → set the leaf value `['plugins', 'hardcoded_strings_lint', 'diagnostics', 'avoid_hardcoded_strings_in_widgets']` to `false`.
</implementation>

<validation>
Manual verification:
1. Open a Flutter file with a hardcoded string warning.
2. Apply the new "Ignore for whole file" fix — all warnings in the file must disappear.
3. Apply the new "Ignore in analysis_options.yaml" fix — all warnings project-wide must disappear (after analysis restarts). Confirm `analysis_options.yaml` now contains `diagnostics.avoid_hardcoded_strings_in_widgets: false` under the plugin section.

Automated tests (add to `test/fixes_test.dart`):

TDD order:
1. RED: write `IgnoreForFileFixTest.test_inserts_ignore_for_file_comment` → fails (no such producer).
2. GREEN: implement `IgnoreForFileFix`.
3. RED: write `IgnoreForFileFixTest.test_idempotent_when_comment_already_present` → fails.
4. GREEN: add idempotency guard.
5. REFACTOR: if `_ignoreCommentText` and `_ignoreForFileCommentText` share a prefix string, extract it.
6. RED: write `IgnoreInAnalysisOptionsFixTest.test_writes_disable_entry_when_absent` → fails.
7. GREEN: implement `IgnoreInAnalysisOptionsFix`.
8. RED: write `IgnoreInAnalysisOptionsFixTest.test_no_op_when_already_disabled` → fails.
9. GREEN: add idempotency guard.
10. RED: write `IgnoreInAnalysisOptionsFixTest.test_no_op_when_no_analysis_options_file` → fails.
11. GREEN: add null-file guard.

Test cases for `IgnoreForFileFix`:
- Applying the fix inserts `// ignore_for_file: hardcoded_strings_lint/avoid_hardcoded_strings_in_widgets` and subsequent analysis produces no warnings for that file.
- Idempotent: applying fix to a file that already has the exact comment produces no edit.
- Appends to existing `// ignore_for_file:` line if one is present.

Test cases for `IgnoreInAnalysisOptionsFix`:
- Applying the fix to a project whose `analysis_options.yaml` has no `diagnostics` entry under the plugin adds `avoid_hardcoded_strings_in_widgets: false` correctly.
- Applying the fix when the rule is already `false` is a no-op.
- Returns early (no crash, no edit) when `analysis_options.yaml` is not found.
- Handles malformed YAML gracefully (no crash).
</validation>

<done_when>
- `IgnoreForFileFix` is registered and, when applied, inserts the correct `// ignore_for_file:` comment; no lint warning remains in the file.
- `IgnoreInAnalysisOptionsFix` is registered and, when applied, writes `diagnostics.avoid_hardcoded_strings_in_widgets: false` under the plugin's `analysis_options.yaml` section; all warnings disappear after analysis restarts.
- All new tests pass (both new fix classes, including idempotency and error-path cases).
- Existing tests (`AddIgnoreCommentFixTest`, `ExtractToVariableFixTest`, `GenerateVariableNameTest`) pass unchanged.
- No new warnings from `package:lints`.
</done_when>
