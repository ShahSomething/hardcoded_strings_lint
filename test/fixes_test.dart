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
