/// Runs heavy work (sound synthesis, puzzle generation) without freezing the
/// screen: on phones in a separate isolate, on the web after the current
/// frame has painted (browsers give Flutter a single thread).
library;

export 'background_native.dart' if (dart.library.js_interop) 'background_web.dart';
