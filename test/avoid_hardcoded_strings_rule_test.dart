import 'package:analyzer_testing/analysis_rule/analysis_rule.dart';
import 'package:hardcoded_strings_lint/src/avoid_hardcoded_strings_rule.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(AvoidHardcodedStringsTest);
    defineReflectiveTests(AvoidHardcodedStringsCustomMessagesTest);
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

  // --- Phase 1 baseline ---

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

  // --- Technical string skip ---

  Future<void> test_url_does_not_report() async {
    await assertNoDiagnostics(r'''
import 'package:flutter/widgets.dart';

Widget build() => Text('https://example.com');
''');
  }

  Future<void> test_email_does_not_report() async {
    await assertNoDiagnostics(r'''
import 'package:flutter/widgets.dart';

Widget build() => Text('user@example.com');
''');
  }

  Future<void> test_hex_color_does_not_report() async {
    await assertNoDiagnostics(r'''
import 'package:flutter/widgets.dart';

Widget build() => Text('#FF5722');
''');
  }

  Future<void> test_snake_case_does_not_report() async {
    await assertNoDiagnostics(r'''
import 'package:flutter/widgets.dart';

Widget build() => Text('snake_case_value');
''');
  }

  Future<void> test_constant_case_does_not_report() async {
    await assertNoDiagnostics(r'''
import 'package:flutter/widgets.dart';

Widget build() => Text('CONSTANT_VALUE');
''');
  }

  Future<void> test_dotted_notation_does_not_report() async {
    await assertNoDiagnostics(r'''
import 'package:flutter/widgets.dart';

Widget build() => Text('package.asset');
''');
  }

  // --- Acceptable widget property skip ---

  Future<void> test_semantics_label_property_does_not_report() async {
    await assertNoDiagnostics(r'''
import 'package:flutter/widgets.dart';

Widget build() => Text('hi', semanticsLabel: 'A long accessibility label');
''');
  }

  Future<void> test_restoration_id_property_does_not_report() async {
    await assertNoDiagnostics(r'''
import 'package:flutter/material.dart';

Widget build() =>
    const Scaffold(restorationId: 'A long restoration Id value');
''');
  }

  // --- Map key skip ---

  Future<void> test_index_expression_string_key_does_not_report() async {
    await assertNoDiagnostics(r'''
String? lookup(Map<String, String> map) => map['some long key'];
''');
  }

  Future<void> test_map_literal_string_key_does_not_report() async {
    await assertNoDiagnostics(r'''
Map<String, int> get values => {'some long key': 1};
''');
  }

  // --- Callback body skip (v1.0.4 regression) ---

  Future<void> test_string_inside_callback_body_does_not_report() async {
    await assertNoDiagnostics(r'''
import 'package:flutter/widgets.dart';

class _Logger {
  void info(String message) {}
}

Widget build(_Logger logger) => GestureDetector(
      onTap: () {
        logger.info('skip me inside a callback');
      },
      child: const SizedBox(),
    );
''');
  }

  // --- Non-widget invocations ---

  Future<void> test_print_call_does_not_report() async {
    await assertNoDiagnostics(r'''
void main() {
  print('hello world');
}
''');
  }

  Future<void> test_non_widget_function_call_does_not_report() async {
    await assertNoDiagnostics(r'''
void myFunction(String x) {}

void main() {
  myFunction('hello world');
}
''');
  }

  // --- Custom widget chain walk ---

  Future<void> test_custom_widget_extends_stateless_reports() async {
    await assertDiagnostics(
      r'''
import 'package:flutter/widgets.dart';

class MyBadge extends StatelessWidget {
  const MyBadge(this.label, {super.key});
  final String label;

  @override
  Widget build(BuildContext context) => Text(label);
}

Widget root() => const MyBadge('Hello world');
''',
      [lint(244, 13)],
    );
  }

  // --- Adjacent / interpolation ---

  Future<void> test_adjacent_strings_passed_to_widget_reports() async {
    // The visitor reports the AdjacentStrings node (the direct widget arg)
    // rather than each fragment, because v1's "direct argument" check only
    // matches whole `arguments` entries.
    await assertDiagnostics(
      r'''
import 'package:flutter/widgets.dart';

Widget build() => Text('foo bar' 'baz qux');
''',
      [lint(63, 19)],
    );
  }

  Future<void> test_string_interpolation_does_not_report() async {
    await assertNoDiagnostics(r'''
import 'package:flutter/widgets.dart';

Widget build(String name) => Text('Hello $name');
''');
  }
}

@reflectiveTest
class AvoidHardcodedStringsCustomMessagesTest extends AnalysisRuleTest {
  @override
  bool get addFlutterPackageDep => true;

  @override
  void setUp() {
    rule = AvoidHardcodedStrings();
    super.setUp();
  }

  static const _code = r'''
import 'package:flutter/widgets.dart';

Widget build() => Text('Hello world');
''';

  Future<void> test_default_message() async {
    await assertDiagnostics(_code, [
      lint(
        63,
        13,
        messageContainsAll: ['Hardcoded string detected in widget'],
        correctionContains: 'Replace hardcoded string',
      ),
    ]);
  }

  Future<void> test_custom_message() async {
    (rule as AvoidHardcodedStrings).setCustomMessagesForTest(
      message: 'Custom warning',
    );
    await assertDiagnostics(_code, [
      lint(63, 13, messageContainsAll: ['Custom warning']),
    ]);
  }

  Future<void> test_custom_correction_message() async {
    (rule as AvoidHardcodedStrings).setCustomMessagesForTest(
      correctionMessage: 'Custom correction',
    );
    await assertDiagnostics(_code, [
      lint(63, 13, correctionContains: 'Custom correction'),
    ]);
  }

  Future<void> test_both_custom_messages() async {
    (rule as AvoidHardcodedStrings).setCustomMessagesForTest(
      message: 'Custom warning',
      correctionMessage: 'Custom correction',
    );
    await assertDiagnostics(_code, [
      lint(
        63,
        13,
        messageContainsAll: ['Custom warning'],
        correctionContains: 'Custom correction',
      ),
    ]);
  }

  Future<void> test_empty_message_falls_back_to_default() async {
    (rule as AvoidHardcodedStrings).setCustomMessagesForTest(message: '');
    await assertDiagnostics(_code, [
      lint(63, 13, messageContainsAll: ['Hardcoded string detected in widget']),
    ]);
  }
}
