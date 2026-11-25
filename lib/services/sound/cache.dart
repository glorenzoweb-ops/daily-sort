/// Keeps synthesized sounds on disk, so only the very first launch spends
/// time building them. The web builds them each time (it has no files).
library;

export 'cache_native.dart' if (dart.library.js_interop) 'cache_web.dart';
