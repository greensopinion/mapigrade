// The tests play the native side: they complete queries with the status and
// message of a MAP_TEXTURE_EVENT_QUERY_RESULT event.
import 'dart:async';

import 'package:flutter_mapigrade/src/texture/map_texture_controller.dart';
import 'package:flutter_mapigrade/src/texture/pending_queries.dart';
import 'package:flutter_test/flutter_test.dart';

const _line =
    '[{"feature":{"type":"Feature","id":1,"properties":{"class":"primary"},'
    '"geometry":{"type":"LineString","coordinates":[[0,-20],[0,20]]}},'
    '"source":"lines","sourceLayer":null,"state":{"selected":true}}]';

void main() {
  test('a result is decoded into one entry per feature', () async {
    final queries = PendingQueries();
    final (id, result) = queries.add();
    queries.complete(id, 0, _line);
    final entries = await result;
    expect(entries, hasLength(1));
    expect((entries.single['feature']! as Map)['id'], 1);
    expect(entries.single['source'], 'lines');
    expect(entries.single['sourceLayer'], isNull);
    expect(entries.single['state'], {'selected': true});
  });

  test('a failed query completes with a MapTextureException', () async {
    final queries = PendingQueries();
    final (id, result) = queries.add();
    queries.complete(id, 3, 'invalid filter');
    await expectLater(
      result,
      throwsA(
        isA<MapTextureException>().having(
          (e) => e.message,
          'message',
          'invalid filter',
        ),
      ),
    );
  });

  test('a slow decode of a large result holds back a later small result', () async {
    final decodeStarted = Completer<void>();
    final release = Completer<void>();
    final queries = PendingQueries(
      isolateThreshold: 100,
      decodeLarge: (json) async {
        decodeStarted.complete();
        await release.future;
        return decodeQueryResult(json);
      },
    );
    final large =
        '[${List.filled(20, _line.substring(1, _line.length - 1)).join(',')}]';
    final (firstId, first) = queries.add();
    final (secondId, second) = queries.add();
    final order = <String>[];
    unawaited(first.then((_) => order.add('first')));
    unawaited(second.then((_) => order.add('second')));

    queries.complete(firstId, 0, large);
    queries.complete(secondId, 0, '[]');
    await decodeStarted.future;
    await pumpEventQueue();
    expect(order, isEmpty);

    release.complete();
    await Future.wait([first, second]);
    expect(order, ['first', 'second']);
    expect(await first, hasLength(20));
  });

  test('a large result is decoded in another isolate by default', () async {
    final queries = PendingQueries(isolateThreshold: 10);
    final (id, result) = queries.add();
    queries.complete(id, 0, _line);
    expect(await result, hasLength(1));
  });

  test('failAll completes the queries without a result', () async {
    final queries = PendingQueries();
    final (doneId, done) = queries.add();
    final (_, pending) = queries.add();
    final failed = expectLater(pending, throwsStateError);
    queries.complete(doneId, 0, '[]');
    queries.failAll(StateError('the map was disposed'));
    expect(await done, isEmpty);
    await failed;
  });

  test('a result for an unknown request is ignored', () {
    final queries = PendingQueries();
    expect(() => queries.complete(42, 0, '[]'), returnsNormally);
  });
}
