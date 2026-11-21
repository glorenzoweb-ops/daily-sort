import 'dart:async';
import 'dart:isolate';

const bool hasBackgroundThread = true;

Future<T> runInBackground<T>(FutureOr<T> Function() work) => Isolate.run(work);

/// Lets frames paint between chunks of long work. On phones the work is
/// already off the UI thread, so this is free.
Future<void> breathe() async {}
