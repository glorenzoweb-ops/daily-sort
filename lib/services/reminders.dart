/// A reminder two days before a free trial turns into a paid plan. Surprise
/// charges after a trial are the top reason for 1-star reviews of puzzle
/// apps, so the app warns first. Local notification only: nothing is sent
/// to a server. On the web it does nothing.
library;

export 'reminders_native.dart' if (dart.library.js_interop) 'reminders_web.dart';
