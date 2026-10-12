// Driver for running the integration tests with `flutter drive`, which works
// on a wirelessly connected iPhone where `flutter test` can't start the app:
//
//   flutter drive -d <device> --driver=test_driver/integration_test.dart \
//     --target=integration_test/map_texture_test.dart
import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver();
