import 'dart:async';
import 'dart:collection';

/// Serial queue that guarantees write operations within a domain
/// execute one at a time, preventing lost updates and stale snapshots.
///
/// Usage:
/// ```dart
/// final queue = DomainOperationQueue();
/// final result = await queue.run(() => db.updateTask(...));
/// ```
class DomainOperationQueue {
  final _queue = Queue<_QueueEntry<dynamic>>();
  bool _isProcessing = false;

  /// Enqueue an async operation and wait for its result.
  ///
  /// Operations are executed in FIFO order. If the queue is idle,
  /// the operation starts immediately. Otherwise it waits until
  /// all preceding operations complete.
  Future<T> run<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    _queue.add(_QueueEntry<T>(operation, completer));
    _processNext();
    return completer.future;
  }

  /// Number of pending operations (including the one currently executing).
  int get length => _queue.length + (_isProcessing ? 1 : 0);

  /// Whether the queue is currently executing an operation.
  bool get isProcessing => _isProcessing;

  Future<void> _processNext() async {
    if (_isProcessing || _queue.isEmpty) return;
    _isProcessing = true;

    while (_queue.isNotEmpty) {
      final entry = _queue.removeFirst();
      await entry.execute();
    }

    _isProcessing = false;
  }
}

class _QueueEntry<T> {
  _QueueEntry(this._operation, this._completer);

  final Future<T> Function() _operation;
  final Completer<T> _completer;

  Future<void> execute() async {
    try {
      final result = await _operation();
      _completer.complete(result);
    } catch (e, st) {
      _completer.completeError(e, st);
    }
  }
}
