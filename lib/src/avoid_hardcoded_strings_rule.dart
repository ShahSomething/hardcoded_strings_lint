import 'dart:io';

import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/error/error.dart';
import 'package:yaml/yaml.dart';

class AvoidHardcodedStrings extends AnalysisRule {
  static const LintCode code = LintCode(
    'avoid_hardcoded_strings_in_widgets',
    'Hardcoded string detected in widget ⚠️ ',
    correctionMessage:
        'Replace hardcoded string with a variable or localized string.',
    severity: DiagnosticSeverity.WARNING,
  );

  String? _customMessage;
  String? _customCorrectionMessage;
  bool _optionsRead = false;

  AvoidHardcodedStrings()
    : super(
        name: 'avoid_hardcoded_strings_in_widgets',
        description:
            'Avoid hardcoded strings passed directly to widget constructors.',
      );

  @override
  DiagnosticCode get diagnosticCode => LintCode(
    'avoid_hardcoded_strings_in_widgets',
    _customMessage?.isNotEmpty == true
        ? _customMessage!
        : 'Hardcoded string detected in widget ⚠️ ',
    correctionMessage: _customCorrectionMessage?.isNotEmpty == true
        ? _customCorrectionMessage!
        : 'Replace hardcoded string with a variable or localized string.',
    severity: DiagnosticSeverity.WARNING,
  );

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    if (!_optionsRead) {
      _readOptions(context);
      _optionsRead = true;
    }
    final visitor = _Visitor(this);
    registry.addSimpleStringLiteral(this, visitor);
    registry.addAdjacentStrings(this, visitor);
    registry.addStringInterpolation(this, visitor);
  }

  /// Sets custom messages directly, skipping file I/O.
  /// Call this in tests before [assertDiagnostics] to inject custom values.
  void setCustomMessagesForTest({String? message, String? correctionMessage}) {
    _customMessage = message;
    _customCorrectionMessage = correctionMessage;
    _optionsRead = true;
  }

  void _readOptions(RuleContext context) {
    try {
      final rootPath = context.package?.root.path;
      if (rootPath == null) return;
      final file = File('$rootPath/analysis_options.yaml');
      if (!file.existsSync()) return;
      final doc = loadYaml(file.readAsStringSync());
      if (doc is! YamlMap) return;
      final plugins = doc['plugins'];
      if (plugins is! YamlMap) return;
      final pluginConfig = plugins['hardcoded_strings_lint'];
      if (pluginConfig is! YamlMap) return;
      final options = pluginConfig['options'];
      if (options is! YamlMap) return;
      final message = options['message'];
      if (message is String && message.isNotEmpty) {
        _customMessage = message;
      }
      final correction = options['correction_message'];
      if (correction is String && correction.isNotEmpty) {
        _customCorrectionMessage = correction;
      }
    } catch (_) {}
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  final AvoidHardcodedStrings rule;

  _Visitor(this.rule);

  @override
  void visitSimpleStringLiteral(SimpleStringLiteral node) {
    _check(node);
  }

  @override
  void visitAdjacentStrings(AdjacentStrings node) {
    _check(node);
  }

  @override
  void visitStringInterpolation(StringInterpolation node) {
    _check(node);
  }

  void _check(StringLiteral node) {
    final value = node.stringValue;
    if (value == null) return;
    if (value.isEmpty) return;
    if (value.length <= 2) return;

    if (!_isPassedToWidget(node)) return;
    if (_isMapKey(node)) return;
    if (_isAcceptableWidgetProperty(node)) return;
    if (_isTechnicalString(value)) return;

    rule.reportAtNode(node);
  }

  bool _isMapKey(StringLiteral node) {
    final parent = node.parent;
    if (parent is IndexExpression) {
      return parent.index == node;
    }
    if (parent is MapLiteralEntry) {
      return parent.key == node;
    }
    return false;
  }

  bool _isAcceptableWidgetProperty(StringLiteral node) {
    final parent = node.parent;
    if (parent is! NamedArgument) return false;

    final propertyName = parent.name.lexeme;

    const acceptableProperties = {
      'semanticsLabel',
      'excludeSemantics',
      'restorationId',
      'heroTag',
      'key',
      'debugLabel',
      'fontFamily',
      'package',
      'name',
      'asset',
      'tooltip',
      'textDirection',
      'locale',
      'materialType',
      'clipBehavior',
      'crossAxisAlignment',
      'mainAxisAlignment',
      'textAlign',
      'textBaseline',
      'overflow',
      'softWrap',
      'textScaleFactor',
    };

    return acceptableProperties.contains(propertyName);
  }

  bool _isTechnicalString(String value) {
    final technicalPatterns = [
      RegExp(r'^\w+://'),
      RegExp(r'^[\w\-\.]+@[\w\-\.]+\.\w+'),
      RegExp(r'^#[0-9A-Fa-f]{3,8}'),
      RegExp(r'^\d+(\.\d+)?[a-zA-Z]*'),
      RegExp(r'^[A-Z][A-Z0-9]*_[A-Z0-9_]*'),
      RegExp(r'^[a-z]+_[a-z_]+'),
      RegExp(r'^/[\w/\-\.]*'),
      RegExp(r'^\w+\.\w+'),
      RegExp(r'^[\w\-]+\.[\w]+'),
      RegExp(r'^[a-zA-Z0-9]*[_\-0-9]+[a-zA-Z0-9_\-]*'),
    ];

    return technicalPatterns.any((pattern) => pattern.hasMatch(value.trim()));
  }

  bool _isPassedToWidget(StringLiteral node) {
    final argumentList = node.thisOrAncestorOfType<ArgumentList>();
    if (argumentList == null) return false;

    AstNode? walker = node.parent;
    while (walker != null && walker != argumentList) {
      if (walker is FunctionExpression || walker is FunctionBody) {
        return false;
      }
      walker = walker.parent;
    }

    final owner = argumentList.parent;
    if (owner is! InstanceCreationExpression) return false;

    final type = owner.staticType;
    if (type == null || !_isFlutterWidget(type.element)) return false;

    for (final arg in argumentList.arguments) {
      if (identical(arg, node)) return true;
      if (arg is NamedArgument && identical(arg.argumentExpression, node)) {
        return true;
      }
    }

    return false;
  }

  bool _isFlutterWidget(Element? element) {
    if (element is! InterfaceElement) return false;
    return _extendsWidget(element);
  }

  bool _extendsWidget(InterfaceElement element) {
    InterfaceElement? current = element;
    while (current != null) {
      if (_isWidgetBaseClass(current.name ?? '')) {
        return true;
      }
      final supertype = current.supertype;
      current = supertype?.element;
    }
    return false;
  }

  bool _isWidgetBaseClass(String className) {
    const widgetBaseClasses = {
      'Widget',
      'StatelessWidget',
      'StatefulWidget',
      'InheritedWidget',
      'RenderObjectWidget',
      'LeafRenderObjectWidget',
      'SingleChildRenderObjectWidget',
      'MultiChildRenderObjectWidget',
      'ProxyWidget',
      'ParentDataWidget',
      'InheritedTheme',
      'PreferredSizeWidget',
    };
    return widgetBaseClasses.contains(className);
  }
}
