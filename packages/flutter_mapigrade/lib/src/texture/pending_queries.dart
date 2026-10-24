import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'map_texture_controller.dart';

/// One feature of a query result: `feature` (a GeoJSON Feature), `source`,
/// `sourceLayer` and `state`, as the native side encodes them.
typedef QueryResultEntry = Map<String, Object?>;

/// Decodes the JSON array of a query result.
List<QueryResultEntry> decodeQueryResult(String json) => [
  for (final entry in jsonDecode(json) as List<Object?>)
    entry as QueryResultEntry,
];

/// The queries of one map that wait for their results, which the native side
/// reports in the order of the queries.
///
/// A result of [isolateThreshold] or more UTF-16 code units is decoded with
/// [decodeLarge], by default in another isolate. Because such a decode can
/// finish after the decode of a later, smaller result, each query completes
/// only after the queries before it.
class PendingQueries {
  /// Pending queries whose large results [decodeLarge] decodes.
  PendingQueries({
    this.isolateThreshold = 64 * 1024,
    Future<List<QueryResultEntry>> Function(String json)? decodeLarge,
  }) : _decodeLarge = decodeLarge ?? _decodeInIsolate;

  /// The length from which a result is decoded with [decodeLarge].
  final int isolateThreshold;
  final Future<List<QueryResultEntry>> Function(String json) _decodeLarge;

  int _nextId = 0;
  final _pending = <int, Completer<List<QueryResultEntry>>>{};
  Future<void> _previous = Future.value();

  /// Starts a query and returns its request id and its result.
  (int, Future<List<QueryResultEntry>>) add() {
    final id = ++_nextId;
    final completer = Completer<List<QueryResultEntry>>();
    _pending[id] = completer;
    return (id, completer.future);
  }

  /// Completes the query [id] with a native [status] of 0 and the result
  /// [message], or with a [MapTextureException] for another status.
  void complete(int id, int status, String message) {
    final completer = _pending.remove(id);
    if (completer == null) return;
    final Future<List<QueryResultEntry>> result;
    if (status != 0) {
      result = Future.error(MapTextureException(message));
    } else if (message.length < isolateThreshold) {
      result = Future.sync(() => decodeQueryResult(message));
    } else {
      result = _decodeLarge(message);
    }
    final settled = result.then<_Outcome>(
      _Outcome.new,
      onError: (Object error, StackTrace stack) => _Outcome.error(error, stack),
    );
    _previous = _previous
        .then((_) => settled)
        .then((outcome) => outcome.completeTo(completer));
  }

  /// Completes every query that has no result yet with [error].
  void failAll(Object error) {
    final pending = [..._pending.values];
    _pending.clear();
    for (final completer in pending) {
      completer.completeError(error);
    }
  }

  static Future<List<QueryResultEntry>> _decodeInIsolate(String json) =>
      Isolate.run(() => decodeQueryResult(json));
}

class _Outcome {
  _Outcome(List<QueryResultEntry> this.value) : error = null, stack = null;
  _Outcome.error(Object this.error, StackTrace this.stack) : value = null;

  final List<QueryResultEntry>? value;
  final Object? error;
  final StackTrace? stack;

  void completeTo(Completer<List<QueryResultEntry>> completer) {
    if (error case final error?) {
      completer.completeError(error, stack);
    } else {
      completer.complete(value);
    }
  }
}
