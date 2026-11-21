/// Reading and tidying the page address on the web, where a friend's result
/// arrives as `?r=...`. Phones have no address bar, so these do nothing there.
library;

export 'link_native.dart' if (dart.library.js_interop) 'link_web.dart';
