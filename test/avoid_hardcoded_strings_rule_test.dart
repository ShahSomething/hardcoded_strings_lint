import 'package:analyzer_testing/analysis_rule/analysis_rule.dart';
import 'package:hardcoded_strings_lint/src/avoid_hardcoded_strings_rule.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(AvoidHardcodedStringsTest);
  });
}

@reflectiveTest
class AvoidHardcodedStringsTest extends AnalysisRuleTest {
  @override
  bool get addFlutterPackageDep => true;

  @override
  void setUp() {
    rule = AvoidHardcodedStrings();
    super.setUp();
  }

  Future<void> test_hardcoded_string_in_text_reports() async {
    await assertDiagnostics(
      r'''
import 'package:flutter/widgets.dart';

Widget build() => Text('Hello world');
''',
      [lint(63, 13)],
    );
  }

  Future<void> test_short_string_in_text_does_not_report() async {
    await assertNoDiagnostics(r'''
import 'package:flutter/widgets.dart';

Widget build() => Text('a');
''');
  }

  Future<void> test_empty_string_in_text_does_not_report() async {
    await assertNoDiagnostics(r'''
import 'package:flutter/widgets.dart';

Widget build() => Text('');
''');
  }
}
