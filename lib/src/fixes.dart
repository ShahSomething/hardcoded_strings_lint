import 'package:analysis_server_plugin/edit/dart/correction_producer.dart';
import 'package:analysis_server_plugin/edit/dart/dart_fix_kind_priority.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/source/source_range.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_core.dart';
import 'package:analyzer_plugin/utilities/fixes/fixes.dart';

const _ignoreCommentText =
    '// ignore: hardcoded_strings_lint/avoid_hardcoded_strings_in_widgets';

class AddIgnoreCommentFix extends ResolvedCorrectionProducer {
  AddIgnoreCommentFix({required super.context});

  static const FixKind _kind = FixKind(
    'dart.fix.addIgnoreHardcodedString',
    DartFixKindPriority.standard,
    "Add '// ignore' comment",
  );

  @override
  CorrectionApplicability get applicability =>
      CorrectionApplicability.singleLocation;

  @override
  FixKind get fixKind => _kind;

  @override
  Future<void> compute(ChangeBuilder builder) async {
    final stringNode = node;
    if (stringNode is! StringLiteral) return;
    if (stringNode.stringValue == null) return;

    final compilationUnit = stringNode.thisOrAncestorOfType<CompilationUnit>();
    if (compilationUnit == null) return;

    final lineInfo = compilationUnit.lineInfo;
    final location = lineInfo.getLocation(stringNode.offset);
    final lineStart = lineInfo.getOffsetOfLine(location.lineNumber - 1);

    final source = unitResult.content;
    final currentLineStart = source.substring(lineStart, stringNode.offset);
    final indentMatch = RegExp(r'^(\s*)').firstMatch(currentLineStart);
    final indent = indentMatch?.group(1) ?? '';

    await builder.addDartFileEdit(file, (builder) {
      builder.addSimpleInsertion(lineStart, '$indent$_ignoreCommentText\n');
    });
  }
}

class ExtractToVariableFix extends ResolvedCorrectionProducer {
  ExtractToVariableFix({required super.context});

  static const FixKind _kind = FixKind(
    'dart.fix.extractHardcodedStringToVariable',
    DartFixKindPriority.standard - 1,
    'Extract to variable',
  );

  @override
  CorrectionApplicability get applicability =>
      CorrectionApplicability.singleLocation;

  @override
  FixKind get fixKind => _kind;

  @override
  Future<void> compute(ChangeBuilder builder) async {
    final stringNode = node;
    if (stringNode is! StringLiteral) return;
    final stringValue = stringNode.stringValue;
    if (stringValue == null || stringValue.isEmpty) return;

    AstNode? parent = stringNode.parent;
    while (parent != null &&
        parent is! MethodDeclaration &&
        parent is! ClassDeclaration) {
      parent = parent.parent;
    }

    final variableName = _generateVariableName(stringValue);
    final literalSource = stringNode.toSource();
    final literalRange = SourceRange(stringNode.offset, stringNode.length);

    if (parent is MethodDeclaration) {
      final body = parent.body;
      if (body is! BlockFunctionBody) return;
      final insertOffset = body.block.leftBracket.offset + 1;

      await builder.addDartFileEdit(file, (builder) {
        builder.addSimpleInsertion(
          insertOffset,
          '\n    const $variableName = $literalSource;\n',
        );
        builder.addSimpleReplacement(literalRange, variableName);
      });
    } else if (parent is ClassDeclaration) {
      final body = parent.body;
      if (body is! BlockClassBody) return;
      final insertOffset = body.leftBracket.offset + 1;

      await builder.addDartFileEdit(file, (builder) {
        builder.addSimpleInsertion(
          insertOffset,
          '\n  static const $variableName = $literalSource;\n',
        );
        builder.addSimpleReplacement(literalRange, variableName);
      });
    }
    // Else: no enclosing method or class — no-op.
  }

  // Visible for testing.
  static String testGenerateVariableName(String value) =>
      _generateVariableName(value);

  static String _generateVariableName(String value) {
    final words = value
        .replaceAll(RegExp(r'[^\w\s]'), '')
        .trim()
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .take(3)
        .toList();

    if (words.isEmpty) return 'textValue';

    final camelCase =
        words.first +
        words
            .skip(1)
            .map((word) => word[0].toUpperCase() + word.substring(1))
            .join();

    return '${camelCase}Text';
  }
}
