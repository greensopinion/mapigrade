// The token of the Flutter engine of this isolate, which map_texture_create
// takes so that the map registers its textures with this engine (designs D153
// and D154 of the multiple-flutter-engines change).
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';

import 'map_texture_controller.dart' show MapTextureException;

/// The channel that the plugin registers with each engine.
@visibleForTesting
const engineChannel = MethodChannel('flutter_mapigrade');

int? _token;
Future<int>? _request;

/// The token of this isolate's engine. The first call asks the plugin over
/// [engineChannel]; calls while that request is pending wait for it. A failed
/// request isn't kept, so the next call asks again.
///
/// Throws [MapTextureException] if the plugin doesn't give the token, for
/// example when it isn't registered with this engine.
Future<int> engineToken() {
  final token = _token;
  if (token != null) return Future.value(token);
  return _request ??= _requestToken();
}

Future<int> _requestToken() async {
  try {
    final token = await engineChannel.invokeMethod<int>('engineToken');
    if (token == null) {
      throw const MapTextureException(
        'flutter_mapigrade returned no token for the Flutter engine',
      );
    }
    _token = token;
    return token;
  } on MapTextureException {
    rethrow;
  } on Exception catch (e) {
    throw MapTextureException(
      'failed to get the token of the Flutter engine from flutter_mapigrade: '
      '$e',
    );
  } finally {
    _request = null;
  }
}

/// For tests: forgets the token, so that the next call asks again.
@visibleForTesting
void resetEngineTokenForTesting() {
  _token = null;
  _request = null;
}
