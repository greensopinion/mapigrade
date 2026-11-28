// flutter_mapigrade has no plugin section, so its pubspec declares the
// platforms of mapigrade's plugin for pub.dev (split-mapigrade-package change).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

YamlMap _pubspec(String path) =>
    loadYaml(File(path).readAsStringSync()) as YamlMap;

void main() {
  test('the declared platforms are the platforms of mapigrade\'s plugin', () {
    final declared = (_pubspec('pubspec.yaml')['platforms'] as YamlMap).keys;
    final plugin =
        ((_pubspec('../mapigrade/pubspec.yaml')['flutter'] as YamlMap)['plugin']
                as YamlMap)['platforms']
            as YamlMap;
    expect(declared.toSet(), plugin.keys.toSet());
  });
}
