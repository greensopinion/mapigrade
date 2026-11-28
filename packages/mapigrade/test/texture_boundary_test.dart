// mapigrade must not depend on flutter_map (design D228 of the
// split-mapigrade-package change).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final _flutterMapImport = RegExp(
  r'''^\s*(import|export)\s+['"]package:flutter_map/''',
  multiLine: true,
);

void main() {
  test('no file under lib/ imports package:flutter_map', () {
    final offenders = [
      for (final file
          in Directory('lib')
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path.endsWith('.dart')))
        if (_flutterMapImport.hasMatch(file.readAsStringSync())) file.path,
    ];
    expect(offenders, isEmpty);
  });
}
