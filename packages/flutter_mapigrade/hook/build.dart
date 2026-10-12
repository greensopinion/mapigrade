// Declares where Dart finds the plugin's native functions on Android (design
// D56). The Gradle build packages libflutter_mapigrade.so, and the plugin class
// loads it with System.loadLibrary. Its symbols are not in the scope that
// @Native's process lookup searches, so the bindings' asset names the library,
// and Dart loads it by name, which returns the copy that is already loaded.
//
// On macOS and iOS the plugin is linked into the app, and @Native resolves the
// symbols from the process, so no asset is declared there.
import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;
    if (input.config.code.targetOS != OS.android) return;
    output.assets.code.add(
      CodeAsset(
        package: input.packageName,
        name: 'src/texture/bindings.dart',
        linkMode: DynamicLoadingSystem(Uri.file('libflutter_mapigrade.so')),
      ),
    );
  });
}
