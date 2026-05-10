import 'package:analysis_server_plugin/edit/dart/correction_producer.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer_plugin/protocol/protocol_common.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_core.dart';
import 'package:analyzer_testing/analysis_rule/analysis_rule.dart';
import 'package:hardcoded_strings_lint/src/avoid_hardcoded_strings_rule.dart';
import 'package:hardcoded_strings_lint/src/fixes.dart';
import 'package:test/test.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(AddIgnoreCommentFixTest);
    defineReflectiveTests(ExtractToVariableFixTest);
    defineReflectiveTests(GenerateVariableNameTest);
    defineReflectiveTests(IgnoreForFileFixTest);
    defineReflectiveTests(IgnoreInAnalysisOptionsFixTest);
  });
}

abstract class _FixTestBase extends AnalysisRuleTest {
  @override
  bool get addFlutterPackageDep => true;

  @override
  void setUp() {
    rule = AvoidHardcodedStrings();
    super.setUp();
  }

  /// Resolves [content] and applies the producer registered for the first
  /// `avoid_hardcoded_strings_in_widgets` diagnostic in the file.
  Future<String> applyFix(
    String content,
    ResolvedCorrectionProducer Function({
      required CorrectionProducerContext context,
    })
    factory,
  ) async {
    await assertDiagnostics(content, anything as dynamic);
    fail('applyFix should be called via _applyFixForFirst');
  }

  Future<String> applyFirstFix(
    String content,
    ResolvedCorrectionProducer Function({
      required CorrectionProducerContext context,
    })
    factory,
  ) async {
    final libraryResult =
        await result.session.getResolvedLibrary(result.path)
            as ResolvedLibraryResult;
    final diagnostic = result.diagnostics.firstWhere(
      (d) =>
          d.diagnosticCode.lowerCaseName.endsWith('/${rule.name}') ||
          d.diagnosticCode.lowerCaseName.endsWith(rule.name),
    );

    final context = CorrectionProducerContext.createResolved(
      libraryResult: libraryResult,
      unitResult: result,
      diagnostic: diagnostic,
      selectionOffset: diagnostic.offset,
      selectionLength: diagnostic.length,
    );

    final producer = factory(context: context);
    final builder = ChangeBuilder(session: result.session);
    await producer.compute(builder);

    final edits = builder.sourceChange.edits.expand((e) => e.edits).toList();
    return SourceEdit.applySequence(content, edits);
  }

  Future<void> writeAndResolve(String content) async {
    newFile('/home/test/lib/test.dart', content);
    result = await resolveFile('/home/test/lib/test.dart');
  }
}

@reflectiveTest
class AddIgnoreCommentFixTest extends _FixTestBase {
  Future<void> test_inserts_ignore_comment_above_line() async {
    const source = '''
import 'package:flutter/widgets.dart';

Widget build() => Text('Hello world');
''';
    await writeAndResolve(source);
    final after = await applyFirstFix(source, AddIgnoreCommentFix.new);
    expect(after, '''
import 'package:flutter/widgets.dart';

// ignore: hardcoded_strings_lint/avoid_hardcoded_strings_in_widgets
Widget build() => Text('Hello world');
''');
  }

  Future<void> test_preserves_indentation() async {
    const source = '''
import 'package:flutter/widgets.dart';

class Demo {
  Widget build() {
    return Column(
      children: [
        Text('Hello world'),
      ],
    );
  }
}
''';
    await writeAndResolve(source);
    final after = await applyFirstFix(source, AddIgnoreCommentFix.new);
    expect(
      after,
      contains(
        '        // ignore: hardcoded_strings_lint/avoid_hardcoded_strings_in_widgets\n'
        "        Text('Hello world'),",
      ),
    );
  }
}

@reflectiveTest
class ExtractToVariableFixTest extends _FixTestBase {
  Future<void> test_extracts_inside_method_block_body() async {
    const source = '''
import 'package:flutter/widgets.dart';

class Demo {
  Widget build() {
    return Text('Hello world');
  }
}
''';
    await writeAndResolve(source);
    final after = await applyFirstFix(source, ExtractToVariableFix.new);
    expect(after, contains("const helloWorldText = 'Hello world';"));
    expect(after, contains('return Text(helloWorldText);'));
  }

  Future<void> test_extracts_at_class_scope_when_outside_method() async {
    const source = '''
import 'package:flutter/widgets.dart';

class Demo {
  final Widget header = Text('Hello world');
}
''';
    await writeAndResolve(source);
    final after = await applyFirstFix(source, ExtractToVariableFix.new);
    expect(after, contains("static const helloWorldText = 'Hello world';"));
    expect(after, contains('final Widget header = Text(helloWorldText);'));
  }

  Future<void> test_no_op_when_outside_method_or_class() async {
    const source = '''
import 'package:flutter/widgets.dart';

final Widget header = Text('Hello world');
''';
    await writeAndResolve(source);
    final after = await applyFirstFix(source, ExtractToVariableFix.new);
    // The fix should produce no edits, so the source is unchanged.
    expect(after, source);
  }
}

@reflectiveTest
class IgnoreForFileFixTest extends _FixTestBase {
  Future<void> test_inserts_ignore_for_file_comment() async {
    const source = '''
import 'package:flutter/widgets.dart';

Widget build() => Text('Hello world');
''';
    await writeAndResolve(source);
    final after = await applyFirstFix(source, IgnoreForFileFix.new);
    expect(
      after,
      '// ignore_for_file: hardcoded_strings_lint/avoid_hardcoded_strings_in_widgets\n'
      '\n'
      "import 'package:flutter/widgets.dart';\n"
      '\n'
      "Widget build() => Text('Hello world');\n",
    );
  }

  Future<void> test_inserts_after_header_blank_line() async {
    const source = '''
// Copyright 2024 Company. All rights reserved.

import 'package:flutter/widgets.dart';

Widget build() => Text('Hello world');
''';
    await writeAndResolve(source);
    final after = await applyFirstFix(source, IgnoreForFileFix.new);
    expect(
      after,
      '// Copyright 2024 Company. All rights reserved.\n'
      '\n'
      '// ignore_for_file: hardcoded_strings_lint/avoid_hardcoded_strings_in_widgets\n'
      '\n'
      "import 'package:flutter/widgets.dart';\n"
      '\n'
      "Widget build() => Text('Hello world');\n",
    );
  }

  Future<void> test_appends_to_existing_ignore_for_file_comment() async {
    const source = '''
// ignore_for_file: some_other_lint

import 'package:flutter/widgets.dart';

Widget build() => Text('Hello world');
''';
    await writeAndResolve(source);
    final after = await applyFirstFix(source, IgnoreForFileFix.new);
    expect(
      after,
      contains(
        '// ignore_for_file: hardcoded_strings_lint/avoid_hardcoded_strings_in_widgets, some_other_lint',
      ),
    );
  }

  Future<void> test_no_op_when_comment_already_present() async {
    const source = '''
// ignore_for_file: hardcoded_strings_lint/avoid_hardcoded_strings_in_widgets

import 'package:flutter/widgets.dart';

Widget build() => Text('Hello world');
''';
    await writeAndResolve(source);
    final diagnostics = result.diagnostics
        .where(
          (d) =>
              d.diagnosticCode.lowerCaseName.endsWith('/${rule.name}') ||
              d.diagnosticCode.lowerCaseName.endsWith(rule.name),
        )
        .toList();
    if (diagnostics.isEmpty) {
      // Comment suppresses the diagnostic — idempotency confirmed.
      return;
    }
    // If diagnostic still present (e.g. test env ignores the prefix),
    // verify the producer guard produces no edits.
    final after = await applyFirstFix(source, IgnoreForFileFix.new);
    expect(after, source);
  }
}

@reflectiveTest
class IgnoreInAnalysisOptionsFixTest extends _FixTestBase {
  static const _dartSource = '''
import 'package:flutter/widgets.dart';

Widget build() => Text('Hello world');
''';

  // Base yaml that enables the lint rule.
  static const _baseYaml =
      'analyzer:\n'
      '  optional-checks:\n'
      '    propagate-linter-exceptions: true\n'
      'linter:\n'
      '  rules:\n'
      '    - avoid_hardcoded_strings_in_widgets\n';

  /// Sets up [yamlContent] as `analysis_options.yaml`, resolves [_dartSource],
  /// applies [IgnoreInAnalysisOptionsFix], and returns the updated yaml text.
  /// Returns the original [yamlContent] unchanged when no edits are produced.
  Future<String> _applyFix(String yamlContent) async {
    newAnalysisOptionsYamlFile(testPackageRootPath, yamlContent);
    await writeAndResolve(_dartSource);

    final yamlPath = convertPath('$testPackageRootPath/analysis_options.yaml');

    final diagnostics = result.diagnostics
        .where(
          (d) =>
              d.diagnosticCode.lowerCaseName.endsWith('/${rule.name}') ||
              d.diagnosticCode.lowerCaseName.endsWith(rule.name),
        )
        .toList();
    if (diagnostics.isEmpty) return yamlContent;

    final diagnostic = diagnostics.first;
    final libraryResult =
        await result.session.getResolvedLibrary(result.path)
            as ResolvedLibraryResult;

    final context = CorrectionProducerContext.createResolved(
      libraryResult: libraryResult,
      unitResult: result,
      diagnostic: diagnostic,
      selectionOffset: diagnostic.offset,
      selectionLength: diagnostic.length,
    );

    final producer = IgnoreInAnalysisOptionsFix(context: context);
    final changeBuilder = ChangeBuilder(session: result.session);
    await producer.compute(changeBuilder);

    final fileEdits = changeBuilder.sourceChange.edits
        .where((e) => e.file == yamlPath)
        .expand((e) => e.edits)
        .toList();

    if (fileEdits.isEmpty) return yamlContent;
    return SourceEdit.applySequence(yamlContent, fileEdits);
  }

  Future<void> test_writes_full_nested_path_when_plugins_absent() async {
    final updated = await _applyFix(_baseYaml);
    expect(updated, contains('plugins:'));
    expect(updated, contains('hardcoded_strings_lint:'));
    expect(updated, contains('diagnostics:'));
    expect(updated, contains('avoid_hardcoded_strings_in_widgets: false'));
  }

  Future<void> test_writes_disable_entry_to_existing_plugin_section() async {
    final yamlContent =
        '$_baseYaml'
        'plugins:\n'
        '  hardcoded_strings_lint:\n'
        '    some_setting: true\n';
    final updated = await _applyFix(yamlContent);
    expect(updated, contains('diagnostics:'));
    expect(updated, contains('avoid_hardcoded_strings_in_widgets: false'));
    // Existing content is preserved.
    expect(updated, contains('some_setting: true'));
  }

  Future<void> test_no_op_when_already_disabled() async {
    final yamlContent =
        '$_baseYaml'
        'plugins:\n'
        '  hardcoded_strings_lint:\n'
        '    diagnostics:\n'
        '      avoid_hardcoded_strings_in_widgets: false\n';
    final updated = await _applyFix(yamlContent);
    // No edits produced — content unchanged.
    expect(updated, equals(yamlContent));
  }

  Future<void> test_no_op_on_malformed_yaml() async {
    // Valid enough for context setup (linter rule enabled) but contains an
    // unclosed flow mapping that YamlEditor will reject.
    final yamlContent = '${_baseYaml}invalid: {\n';

    // Resolve first with the (potentially partially-parsed) yaml.
    newAnalysisOptionsYamlFile(testPackageRootPath, yamlContent);
    await writeAndResolve(_dartSource);

    // Overwrite with clearly malformed content after context creation so the
    // producer reads it via readAsStringSync() at compute time.
    resourceProvider
        .getFile(convertPath('$testPackageRootPath/analysis_options.yaml'))
        .writeAsStringSync('{malformed yaml');

    final diagnostics = result.diagnostics
        .where(
          (d) =>
              d.diagnosticCode.lowerCaseName.endsWith('/${rule.name}') ||
              d.diagnosticCode.lowerCaseName.endsWith(rule.name),
        )
        .toList();
    if (diagnostics.isEmpty) return;

    final diagnostic = diagnostics.first;
    final libraryResult =
        await result.session.getResolvedLibrary(result.path)
            as ResolvedLibraryResult;

    final context = CorrectionProducerContext.createResolved(
      libraryResult: libraryResult,
      unitResult: result,
      diagnostic: diagnostic,
      selectionOffset: diagnostic.offset,
      selectionLength: diagnostic.length,
    );

    final producer = IgnoreInAnalysisOptionsFix(context: context);
    final changeBuilder = ChangeBuilder(session: result.session);
    // Must not crash.
    await producer.compute(changeBuilder);

    // Must produce no yaml edits.
    final fileEdits = changeBuilder.sourceChange.edits
        .expand((e) => e.edits)
        .toList();
    expect(fileEdits, isEmpty);
  }
}

@reflectiveTest
class GenerateVariableNameTest {
  void test_camel_case_with_punctuation() {
    expect(
      ExtractToVariableFix.testGenerateVariableName('Hello, World!'),
      'helloWorldText',
    );
  }

  void test_falls_back_to_text_value_for_punctuation_only() {
    expect(ExtractToVariableFix.testGenerateVariableName('!!!!!'), 'textValue');
  }

  void test_takes_first_three_words() {
    expect(
      ExtractToVariableFix.testGenerateVariableName('one two three four'),
      'oneTwoThreeText',
    );
  }
}
