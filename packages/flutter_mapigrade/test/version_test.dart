// Both packages have the same version, and flutter_mapigrade depends on
// mapigrade with the range from that version to the next patch version (design
// D231 of the split-mapigrade-package change), or on exactly that version for a
// prerelease (design D254 of the apple-only-beta-release change).
// scripts/set_version.sh sets the three values.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:yaml/yaml.dart';

YamlMap _pubspec(String path) =>
    loadYaml(File(path).readAsStringSync()) as YamlMap;

void main() {
  test('the versions and the constraint on mapigrade agree', () {
    final pubspec = _pubspec('pubspec.yaml');
    final version = Version.parse('${pubspec['version']}');
    final VersionConstraint expectedConstraint = version.isPreRelease
        ? version
        : VersionRange(min: version, includeMin: true, max: version.nextPatch);
    final mapigradeVersion =
        '${_pubspec('../mapigrade/pubspec.yaml')['version']}';
    final constraint = '${(pubspec['dependencies'] as YamlMap)['mapigrade']}';
    final differing = [
      if (mapigradeVersion != '$version')
        'the version of mapigrade is $mapigradeVersion',
      if (VersionConstraint.parse(constraint) != expectedConstraint)
        "flutter_mapigrade's constraint on mapigrade is '$constraint', "
            "not '$expectedConstraint'",
    ];
    expect(
      differing,
      isEmpty,
      reason:
          'the version of flutter_mapigrade is $version; '
          'run scripts/set_version.sh',
    );
  });
}
