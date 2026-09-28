// Run before packaging: the runtime, generator and Rust crate are one ABI unit.
import 'dart:convert';
import 'dart:io';

void main() {
  const expected = '2.11.1';
  final config =
      jsonDecode(File('.dart_tool/package_config.json').readAsStringSync())
          as Map<String, dynamic>;
  final packages = config['packages'] as List<dynamic>;
  final frb = packages.cast<Map<String, dynamic>>().singleWhere(
    (p) => p['name'] == 'flutter_rust_bridge',
  );
  final rootUri = File(
    '.dart_tool/package_config.json',
  ).absolute.uri.resolve(frb['rootUri'] as String);
  final root = Directory.fromUri(rootUri).uri;
  final checks = <String, bool>{
    'Dart runtime': RegExp(
      r'^version: 2\.11\.1\s*$',
      multiLine: true,
    ).hasMatch(File.fromUri(root.resolve('pubspec.yaml')).readAsStringSync()),
    'Cargo pin': File(
      'rust/Cargo.toml',
    ).readAsStringSync().contains('flutter_rust_bridge = "=$expected"'),
    'Dart codegen': File(
      'lib/gen/frb_generated.dart',
    ).readAsStringSync().contains("get codegenVersion => '$expected'"),
    'Rust codegen': File('rust/src/frb_generated.rs')
        .readAsStringSync()
        .contains('FLUTTER_RUST_BRIDGE_CODEGEN_VERSION: &str = "$expected"'),
  };
  for (final entry in checks.entries) {
    stdout.writeln('${entry.key}: ${entry.value ? expected : "MISMATCH"}');
  }
  if (checks.containsValue(false)) exitCode = 1;
}
