import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/error/error.dart';

class AvoidHardcodedStrings extends AnalysisRule {
  static const LintCode code = LintCode(
    'avoid_hardcoded_strings_in_widgets',
    'Hardcoded string detected in widget ⚠️ ',
    correctionMessage:
        'Replace hardcoded string with a variable or localized string.',
    severity: DiagnosticSeverity.WARNING,
  );

  AvoidHardcodedStrings()
    : super(
        name: 'avoid_hardcoded_strings_in_widgets',
        description:
            'Avoid hardcoded strings passed directly to widget constructors.',
      );

  @override
  DiagnosticCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    final visitor = _Visitor(this);
    registry.addSimpleStringLiteral(this, visitor);
    registry.addAdjacentStrings(this, visitor);
    registry.addStringInterpolation(this, visitor);
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

    rule.reportAtNode(node);
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
