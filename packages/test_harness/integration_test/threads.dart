import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_mapigrade/src/testing.dart';
import 'package:flutter_test/flutter_test.dart';

/// The process's thread count and, on Android, its thread names.
class Threads {
  Threads() : count = processThreadCount(), names = _threadNames();

  final int count;
  final List<String> names;
}

/// Expects that no thread was leaked between [before] and [after] by repeated
/// cycles. A thread leaked by each of 50 cycles adds 50 threads. The Dart VM
/// and the OS start and stop threads of their own pools as needed, so the count
/// may grow by a few: DartWorker and binder threads don't count, and two other
/// threads are allowed. Thread names are read on Android only.
void expectNoLeakedThreads(Threads before, Threads after) {
  var poolThreadsAdded = 0;
  if (after.count > before.count) {
    final added = _subtract(after.names, before.names);
    poolThreadsAdded = added
        .where((name) => name == 'DartWorker' || name.startsWith('binder:'))
        .length;
    debugPrint(
      'threads added: $added; '
      'removed: ${_subtract(before.names, after.names)}',
    );
  }
  expect(after.count - poolThreadsAdded, lessThanOrEqualTo(before.count + 2));
}

/// The names of the process's threads, from /proc/self/task/*/comm, on Android
/// only; empty elsewhere.
List<String> _threadNames() {
  if (!Platform.isAndroid) return const [];
  final names = <String>[];
  for (final task in Directory('/proc/self/task').listSync()) {
    try {
      names.add(File('${task.path}/comm').readAsStringSync().trim());
    } on FileSystemException {
      // The thread exited while the directory was listed.
    }
  }
  return names..sort();
}

/// The elements of [a] that [b] doesn't have, counting repeated names.
List<String> _subtract(List<String> a, List<String> b) {
  final rest = [...b];
  return [
    for (final name in a)
      if (!rest.remove(name)) name,
  ];
}
