import 'package:analysis_server_plugin/edit/dart/correction_producer.dart';
import 'package:analysis_server_plugin/edit/dart/dart_fix_kind_priority.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/file_system/file_system.dart';
import 'package:analyzer/source/source_range.dart';
import 'package:analyzer/src/dart/analysis/analysis_options.dart'; // ignore: implementation_imports
import 'package:analyzer_plugin/utilities/change_builder/change_builder_core.dart';
import 'package:analyzer_plugin/utilities/fixes/fixes.dart';
import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

const _ignoreCommentText =
    '// ignore: hardcoded_strings_lint/avoid_hardcoded_strings_in_widgets';

const _ignoreForFileCommentText =
    '// ignore_for_file: hardcoded_strings_lint/avoid_hardcoded_strings_in_widgets';

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

class IgnoreForFileFix extends ResolvedCorrectionProducer {
  IgnoreForFileFix({required super.context});

  static const FixKind _kind = FixKind(
    'dart.fix.ignoreForFileHardcodedString',
    DartFixKindPriority.ignore - 1,
    'Ignore for whole file',
  );

  @override
  CorrectionApplicability get applicability =>
      CorrectionApplicability.singleLocation;

  @override
  FixKind get fixKind => _kind;

  @override
  Future<void> compute(ChangeBuilder builder) async {
    final source = unitResult.content;
    if (source.contains(_ignoreForFileCommentText)) return;

    await builder.addDartFileEdit(file, (builder) {
      final lineCount = unitResult.lineInfo.lineCount;

      if (lineCount == 1) {
        builder.addSimpleInsertion(0, '$_ignoreForFileCommentText\n\n');
        return;
      }

      int? lastBlankLineOffset;
      late int lineStart;

      for (var lineNumber = 0; lineNumber < lineCount - 1; lineNumber++) {
        lineStart = unitResult.lineInfo.getOffsetOfLine(lineNumber);
        final nextLineStart = unitResult.lineInfo.getOffsetOfLine(
          lineNumber + 1,
        );
        final line = source.substring(lineStart, nextLineStart);
        final trimmedLine = line.trim();

        if (trimmedLine.startsWith('// ignore_for_file:')) {
          final insertOffset = lineStart + line.indexOf(':') + 1;
          builder.addSimpleInsertion(
            insertOffset,
            ' hardcoded_strings_lint/avoid_hardcoded_strings_in_widgets,',
          );
          return;
        }

        if (trimmedLine.isEmpty) {
          lastBlankLineOffset = lineStart;
          continue;
        }

        if (trimmedLine.startsWith('#!') || trimmedLine.startsWith('//')) {
          continue;
        }

        break;
      }

      if (lastBlankLineOffset != null) {
        builder.addSimpleInsertion(
          lastBlankLineOffset,
          '\n$_ignoreForFileCommentText\n',
        );
      } else {
        builder.addSimpleInsertion(lineStart, '$_ignoreForFileCommentText\n\n');
      }
    });
  }
}

class IgnoreInAnalysisOptionsFix extends ResolvedCorrectionProducer {
  IgnoreInAnalysisOptionsFix({required super.context});

  static const FixKind _kind = FixKind(
    'dart.fix.ignoreInAnalysisOptionsHardcodedString',
    DartFixKindPriority.ignore - 2,
    'Ignore in `analysis_options.yaml`',
  );

  @override
  CorrectionApplicability get applicability =>
      CorrectionApplicability.singleLocation;

  @override
  FixKind get fixKind => _kind;

  @override
  Future<void> compute(ChangeBuilder builder) async {
    final analysisOptionsFile = (analysisOptions as AnalysisOptionsImpl).file;
    if (analysisOptionsFile == null) return;

    String content;
    try {
      content = analysisOptionsFile.readAsStringSync();
    } on FileSystemException {
      return;
    }

    await builder.addYamlFileEdit(analysisOptionsFile.path, (builder) {
      YamlEditor editor;
      try {
        editor = YamlEditor(content);
      } on YamlException {
        return;
      }

      final options = editor.parseAt([]);

      if (options is YamlMap) {
        final plugins = options['plugins'];
        if (plugins is YamlMap) {
          final pluginSection = plugins['hardcoded_strings_lint'];
          if (pluginSection is YamlMap) {
            final diagnostics = pluginSection['diagnostics'];
            if (diagnostics is YamlMap) {
              final value = diagnostics['avoid_hardcoded_strings_in_widgets'];
              if (value == false || value == 'disable') return;
            }
          }
        }
      }

      List<String> path;
      Object value;

      if (options is! YamlMap) {
        path = [];
        value = {
          'plugins': {
            'hardcoded_strings_lint': {
              'diagnostics': {'avoid_hardcoded_strings_in_widgets': false},
            },
          },
        };
      } else {
        final pluginsMap = options['plugins'];
        if (pluginsMap is! YamlMap) {
          path = ['plugins'];
          value = {
            'hardcoded_strings_lint': {
              'diagnostics': {'avoid_hardcoded_strings_in_widgets': false},
            },
          };
        } else {
          final pluginSection = pluginsMap['hardcoded_strings_lint'];
          if (pluginSection is! YamlMap) {
            path = ['plugins', 'hardcoded_strings_lint'];
            value = {
              'diagnostics': {'avoid_hardcoded_strings_in_widgets': false},
            };
          } else {
            final diagnostics = pluginSection['diagnostics'];
            if (diagnostics is! YamlMap) {
              path = ['plugins', 'hardcoded_strings_lint', 'diagnostics'];
              value = {'avoid_hardcoded_strings_in_widgets': false};
            } else {
              path = [
                'plugins',
                'hardcoded_strings_lint',
                'diagnostics',
                'avoid_hardcoded_strings_in_widgets',
              ];
              value = false;
            }
          }
        }
      }

      try {
        editor.update(path, value);
      } on AssertionError {
        return;
      }

      for (final edit in editor.edits) {
        if (edit.length == 0) {
          builder.addSimpleInsertion(edit.offset, edit.replacement);
        } else {
          builder.addSimpleReplacement(
            SourceRange(edit.offset, edit.length),
            edit.replacement,
          );
        }
      }
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
