import 'dart:io';

// Keep the upstream submodule revision and carry the Linux CLI fixes as a patch
// tracked by this repository. A fresh clone must build the same native library.
Future<void> prepareMaxima(Uri cliRoot) async {
  final directory = Directory.fromUri(cliRoot.resolve('ThirdParty/Maxima/'));
  if (!directory.existsSync()) {
    throw StateError(
      'Initialize CLI/ThirdParty/Maxima and restore the CLI patches first.',
    );
  }
  for (final name in ['maxima-linux-compat', 'maxima-proton-x86_64']) {
    final patch = File.fromUri(cliRoot.resolve('patches/$name.patch'));
    // Normalize only patch targets: Windows submodules may use CRLF.
    for (final match in RegExp(
      r'^\+\+\+ b/(.+)$',
      multiLine: true,
    ).allMatches(patch.readAsStringSync().replaceAll('\r\n', '\n'))) {
      final file = File.fromUri(directory.uri.resolve(match[1]!));
      if (!file.existsSync()) continue;
      final contents = file.readAsStringSync();
      if (contents.contains('\r\n')) {
        file.writeAsStringSync(contents.replaceAll('\r\n', '\n'));
      }
    }
    Future<ProcessResult> git(List<String> args) => Process.run(
      'git',
      ['apply', ...args, patch.path],
      workingDirectory: directory.path,
      // Source archives must not inherit an unrelated repository above them.
      environment: {'GIT_CEILING_DIRECTORIES': directory.parent.path},
    );
    if ((await git(['--reverse', '--check'])).exitCode == 0) continue;
    final check = await git(['--check']);
    if (check.exitCode != 0) {
      throw StateError('$name conflicts with local changes:\n${check.stderr}');
    }
    final apply = await git([]);
    if (apply.exitCode != 0) {
      throw StateError('Failed to apply $name:\n${apply.stderr}');
    }
  }
}

Future<void> main() async {
  await prepareMaxima(Platform.script.resolve('../'));
  stdout.writeln('Maxima Linux compatibility patch verified.');
}
