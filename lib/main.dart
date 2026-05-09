import 'package:analysis_server_plugin/plugin.dart';
import 'package:analysis_server_plugin/registry.dart';
import 'package:hardcoded_strings_lint/src/avoid_hardcoded_strings_rule.dart';

final plugin = HardcodedStringsPlugin();

class HardcodedStringsPlugin extends Plugin {
  @override
  String get name => 'hardcoded_strings_lint';

  @override
  void register(PluginRegistry registry) {
    registry.registerWarningRule(AvoidHardcodedStrings());
  }
}
