import 'dart:async';

const bool hasBackgroundThread = false;

Future<T> runInBackground<T>(FutureOr<T> Function() work) async {
  await breathe();
  return await work();
}

/// Yields so the browser can paint a frame before the next chunk of work.
Future<void> breathe() => Future<void>.delayed(const Duration(milliseconds: 4));
