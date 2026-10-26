// Unit tests of MapTextureController and the engine token request that don't
// need the native library.
import 'package:flutter/services.dart';
import 'package:flutter_mapigrade/src/texture/engine_token.dart';
import 'package:flutter_mapigrade/src/texture/map_texture_controller.dart';
import 'package:flutter_mapigrade/src/texture/native_library.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  /// Answers [engineChannel] with [answer] and returns the calls it receives.
  List<MethodCall> mockChannel(Future<Object?> Function() answer) {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(engineChannel, (call) {
      calls.add(call);
      return answer();
    });
    return calls;
  }

  tearDown(() {
    nativeLibraryAvailableOverride = null;
    resetEngineTokenForTesting();
    messenger.setMockMethodCallHandler(engineChannel, null);
  });

  test('create throws MapTextureException without the native library, '
      'before asking for the engine token', () async {
    nativeLibraryAvailableOverride = false;
    final calls = mockChannel(() async => 1);
    await expectLater(
      MapTextureController.create(pixelRatio: 1, maxPitch: 85),
      throwsA(
        isA<MapTextureException>().having(
          (e) => e.message,
          'message',
          'the native library of flutter_mapigrade is not available in this '
              'process',
        ),
      ),
    );
    expect(calls, isEmpty);
  });

  test('the engine token is requested once per isolate', () async {
    final calls = mockChannel(() async => 7);
    // Both start before the request completes.
    final tokens = await Future.wait([engineToken(), engineToken()]);
    expect(tokens, [7, 7]);
    expect(await engineToken(), 7);
    expect(calls.map((c) => c.method), ['engineToken']);
  });

  test('a channel failure becomes a MapTextureException, and the next '
      'request asks again', () async {
    var fail = true;
    final calls = mockChannel(() async {
      if (fail) throw PlatformException(code: 'error', message: 'no engine');
      return 3;
    });
    await expectLater(
      engineToken(),
      throwsA(
        isA<MapTextureException>().having(
          (e) => e.message,
          'message',
          contains('no engine'),
        ),
      ),
    );
    fail = false;
    expect(await engineToken(), 3);
    expect(calls, hasLength(2));
  });

  test('a missing plugin becomes a MapTextureException', () async {
    await expectLater(engineToken(), throwsA(isA<MapTextureException>()));
  });

  test('setMaximumCacheSize rejects a negative size', () {
    expect(
      () => MapTextureController.setMaximumCacheSize(-1),
      throwsArgumentError,
    );
  });
}
