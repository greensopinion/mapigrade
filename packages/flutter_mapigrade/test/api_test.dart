// The API test of the package-api spec (design D70 of the public-api change):
// what the main library exports, the naming rule for exported names, and the
// class modifiers of exported classes. Adding API requires editing
// `expectedNames`.
@Timeout(Duration(minutes: 3))
library;

import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context.dart';
import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

const mainLibrary = 'package:flutter_mapigrade/flutter_mapigrade.dart';

const expectedNames = {
  'MapigradeLayer',
  'LayerAlignment',
  'LayerException',
  'LayerLoadException',
  'LayerRenderException',
  'LayerCreateException',
  'HttpHeaderRule',
  'LayerMetrics',
  'LayerMetricsSnapshot',
};

/// Names that `flutter_map` uses for its own types. Exported names don't
/// start with them, except the name of the layer.
const reservedPrefixes = [
  'Map',
  'Camera',
  'Tile',
  'Marker',
  'Polyline',
  'Polygon',
];
const prefixExceptions = {'MapigradeLayer'};

/// Libraries whose exported names the main library doesn't export.
const otherLibraries = [
  'package:flutter_map/flutter_map.dart',
  'package:latlong2/latlong.dart',
  'package:flutter/widgets.dart',
  'package:flutter/material.dart',
];

/// Abstract final, so that applications can't extend it and a new subclass is
/// a compatible change (design D68); every other exported class is final.
const abstractFinalClasses = {'LayerException'};

/// The Dart SDK of the Flutter SDK that runs the test. The analyzer's default
/// is the SDK of the running executable, which under `flutter test` is
/// `flutter_tester`, not a Dart SDK.
String dartSdkPath() {
  if (Platform.environment['FLUTTER_ROOT'] case final root?) {
    return p.join(root, 'bin', 'cache', 'dart-sdk');
  }
  for (
    var dir = p.dirname(Platform.resolvedExecutable);
    dir != p.dirname(dir);
    dir = p.dirname(dir)
  ) {
    if (p.basename(dir) == 'cache' &&
        Directory(p.join(dir, 'dart-sdk')).existsSync()) {
      return p.join(dir, 'dart-sdk');
    }
  }
  throw StateError('no Dart SDK found above ${Platform.resolvedExecutable}');
}

void main() {
  final packageRoot = p.normalize(Directory.current.absolute.path);
  late AnalysisContext context;
  late LibraryElement library;

  setUpAll(() async {
    context = AnalysisContextCollection(
      includedPaths: [packageRoot],
      sdkPath: dartSdkPath(),
    ).contextFor(packageRoot);
    final result = await context.currentSession.getLibraryByUri(mainLibrary);
    library = (result as LibraryElementResult).element;
  });

  Map<String, Element> exportsOf(LibraryElement library) => {
    for (final MapEntry(:key, :value)
        in library.exportNamespace.definedNames2.entries)
      // A setter is listed as `name=`.
      key.endsWith('=') ? key.substring(0, key.length - 1) : key: value,
  };

  test('the main library exports exactly the names of the spec', () {
    final names = exportsOf(library).keys.toSet();
    expect(
      names.difference(expectedNames),
      isEmpty,
      reason:
          'exported but not in the spec (add to expectedNames only with '
          'a decision to add API)',
    );
    expect(
      expectedNames.difference(names),
      isEmpty,
      reason: 'in the spec but not exported',
    );
  });

  test('every export directive of the main library has a show list', () {
    final path = p.join(packageRoot, 'lib', 'flutter_mapigrade.dart');
    final unit =
        (context.currentSession.getParsedUnit(path) as ParsedUnitResult).unit;
    final withoutShow = [
      for (final directive in unit.directives.whereType<ExportDirective>())
        if (!directive.combinators.any((c) => c is ShowCombinator))
          directive.uri.stringValue,
    ];
    expect(
      withoutShow,
      isEmpty,
      reason: 'each export directive must list the names it exports',
    );
  });

  test('exported names follow the naming rule', () async {
    final violations = <String>[];
    for (final name in exportsOf(library).keys) {
      for (final prefix in reservedPrefixes) {
        if (name.startsWith(prefix) && !prefixExceptions.contains(name)) {
          violations.add(
            '$name starts with $prefix, which flutter_map uses for its own '
            'types',
          );
        }
      }
    }
    for (final uri in otherLibraries) {
      final result = await context.currentSession.getLibraryByUri(uri);
      final other = exportsOf((result as LibraryElementResult).element);
      for (final name in exportsOf(library).keys) {
        if (other.containsKey(name)) {
          violations.add('$name is also exported by $uri');
        }
      }
    }
    expect(violations, isEmpty);
  });

  test('exported classes are closed to applications', () {
    final violations = <String>[];
    for (final MapEntry(key: name, :value) in exportsOf(library).entries) {
      if (value is! ClassElement) {
        violations.add('$name is not a class');
        continue;
      }
      final abstractFinal = abstractFinalClasses.contains(name);
      if (!value.isFinal || value.isAbstract != abstractFinal) {
        violations.add(
          '$name must be ${abstractFinal ? 'abstract final' : 'final'}',
        );
      }
    }
    expect(violations, isEmpty);
  });

  test('lib/ has no library outside lib/src/ other than the main library', () {
    final files = [
      for (final file
          in Directory(p.join(packageRoot, 'lib'))
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path.endsWith('.dart')))
        p.relative(file.path, from: packageRoot),
    ];
    expect(files.where((f) => !p.isWithin('lib/src', f)), [
      'lib/flutter_mapigrade.dart',
    ]);
  });
}
