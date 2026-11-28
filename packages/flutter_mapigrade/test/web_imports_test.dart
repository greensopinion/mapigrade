// The import-graph check of the scenario "Application built for web" of the
// map-layer spec (design D163 of the web-build-compatibility change): no file
// of the package that the main library reaches on web imports a library that
// the web compilers reject. A directive with configurations is followed
// through its `dart.library.js_interop` URI, as dart2js and dart2wasm follow
// it. Imports into mapigrade are followed; imports into other packages aren't.
import 'dart:io';
import 'dart:convert';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

const mainLibrary = 'lib/flutter_mapigrade.dart';
const webCondition = 'dart.library.js_interop';

/// The packages whose files the check follows: this one, and mapigrade, which
/// the main library imports.
const followedPackages = ['flutter_mapigrade', 'mapigrade'];

/// Libraries that dart2js or dart2wasm reject.
const unavailableOnWeb = {
  'dart:ffi',
  'dart:io',
  'dart:isolate',
  'dart:mirrors',
  'dart:cli',
};
const unavailablePackages = ['package:ffi/'];

/// The URI that a web compiler follows for [directive].
String webUri(NamespaceDirective directive) {
  for (final configuration in directive.configurations) {
    final value = configuration.value?.stringValue ?? 'true';
    if (configuration.name.toSource() == webCondition && value == 'true') {
      return configuration.uri.stringValue!;
    }
  }
  return directive.uri.stringValue!;
}

/// The `lib/` directory of each followed package, from the workspace's
/// package configuration. `flutter_tester` doesn't support
/// `Isolate.resolvePackageUri`.
final Map<String, String> packageLibs = () {
  var dir = Directory.current.absolute;
  while (!File(p.join(dir.path, '.dart_tool', 'package_config.json'))
      .existsSync()) {
    dir = dir.parent;
  }
  final configFile = p.join(dir.path, '.dart_tool', 'package_config.json');
  final config =
      jsonDecode(File(configFile).readAsStringSync()) as Map<String, Object?>;
  return {
    for (final package
        in (config['packages']! as List).cast<Map<String, Object?>>())
      if (followedPackages.contains(package['name']))
        package['name'] as String: p.relative(
          p.join(
            p.fromUri(
              Uri.file(configFile).resolve(package['rootUri'] as String),
            ),
            package['packageUri'] as String,
          ),
        ),
  };
}();

/// The file that [uri], in [from], refers to, or null for a library outside
/// the followed packages.
String? packageFile(String uri, String from) {
  if (uri.startsWith('package:')) {
    final [package, ...path] = uri.substring('package:'.length).split('/');
    final lib = packageLibs[package];
    return lib == null ? null : p.normalize(p.join(lib, path.join('/')));
  }
  if (uri.contains(':')) return null;
  return p.normalize(p.join(p.dirname(from), uri));
}

/// Each file reached from [start] on web whose imports include a library
/// that the web compilers reject, with the chain of files from [start].
List<String> webIncompatibleImports(String start) {
  final parents = <String, String?>{start: null};
  final queue = [start];
  final violations = <String>[];
  List<String> chain(String file) =>
      [for (String? f = file; f != null; f = parents[f]) f].reversed.toList();
  while (queue.isNotEmpty) {
    final file = queue.removeAt(0);
    final unit = parseFile(
      path: p.normalize(p.absolute(file)),
      featureSet: FeatureSet.latestLanguageVersion(),
    ).unit;
    for (final directive in unit.directives.whereType<NamespaceDirective>()) {
      final uri = webUri(directive);
      if (unavailableOnWeb.contains(uri) ||
          unavailablePackages.any(uri.startsWith)) {
        violations.add('$file imports $uri (${chain(file).join(' => ')})');
        continue;
      }
      final target = packageFile(uri, file);
      if (target != null && !parents.containsKey(target)) {
        parents[target] = file;
        queue.add(target);
      }
    }
  }
  return violations;
}

void main() {
  test('the main library reaches no library that web compilers reject, '
      'in this package and in mapigrade', () {
    expect(packageLibs.keys, unorderedEquals(followedPackages));
    expect(File(mainLibrary).existsSync(), isTrue);
    expect(webIncompatibleImports(mainLibrary), isEmpty);
  });
}
