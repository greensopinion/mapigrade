// Design D9: code under lib/src/texture/ must not depend on flutter_map; only
// lib/src/layer/ may import it.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final _flutterMapImport = RegExp(
  r'''^\s*(import|export)\s+['"]package:flutter_map/''',
  multiLine: true,
);

void main() {
  test('lib/src/texture does not import package:flutter_map', () {
    final offenders = [
      for (final file
          in Directory('lib/src/texture')
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path.endsWith('.dart')))
        if (_flutterMapImport.hasMatch(file.readAsStringSync())) file.path,
    ];
    expect(
      offenders,
      isEmpty,
      reason: 'only lib/src/layer/ may import package:flutter_map',
    );
  });
}
