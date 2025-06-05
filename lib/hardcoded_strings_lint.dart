// Plugin entry point
import 'package:custom_lint_builder/custom_lint_builder.dart';
import 'package:hardcoded_strings_lint/src/hardcoded_strings_lint_base.dart';

PluginBase createPlugin() => HardcodedStringLintPlugin();

class HardcodedStringLintPlugin extends PluginBase {
  @override
  List<LintRule> getLintRules(CustomLintConfigs configs) => [
        const HardcodedStringLintRule(),
      ];
}
