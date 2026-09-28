import 'dart:convert';
import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:native_toolchain_rs/native_toolchain_rs.dart';

import '../tool/prepare_maxima.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    await prepareMaxima(input.packageRoot);
    output.dependencies.add(
      input.packageRoot.resolve('patches/maxima-linux-compat.patch'),
    );
    output.dependencies.add(
      input.packageRoot.resolve('patches/maxima-proton-x86_64.patch'),
    );
    // Dart filters the hook's inherited environment. The Windows cross-build
    // script supplies an explicit, temporary configuration instead.
    final environmentFile = File.fromUri(
      input.packageRoot.resolve('.dart_tool/kyber-build-environment.json'),
    );
    final environment = <String, String>{};
    if (environmentFile.existsSync()) {
      environment.addAll(
        (jsonDecode(environmentFile.readAsStringSync()) as Map)
            .cast<String, String>(),
      );
      output.dependencies.add(environmentFile.uri);
    }
    final prebuiltLibrary = environment.remove('KYBER_PREBUILT_RUST_LIB');
    if (prebuiltLibrary != null) {
      final library = File(prebuiltLibrary);
      if (!library.existsSync()) {
        throw StateError('Prebuilt Rust library is missing: $prebuiltLibrary');
      }
      output.dependencies.add(library.uri);
      output.assets.code.add(
        CodeAsset(
          package: input.packageName,
          name: 'lib/gen/frb_generated.dart',
          linkMode: DynamicLoadingBundled(),
          file: library.uri,
        ),
      );
      return;
    }
    await RustBuilder(
      assetName: 'lib/gen/frb_generated.dart',
      extraCargoEnvironmentVariables: environment,
    ).run(input: input, output: output);
  });
}
