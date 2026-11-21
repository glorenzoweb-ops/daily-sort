import 'package:web/web.dart' as web;

/// The `r` parameter of the link that opened the app, if any.
String? incomingResultParam() {
  try {
    return Uri.base.queryParameters['r'];
  } catch (_) {
    return null;
  }
}

/// Removes `?r=...` from the address bar so a reload doesn't re-add it.
void clearIncomingParam() {
  try {
    final u = Uri.base;
    if (!u.queryParameters.containsKey('r')) return;
    final q = Map<String, String>.of(u.queryParameters)..remove('r');
    final query = q.isEmpty ? '' : '?${Uri(queryParameters: q).query}';
    final clean = '${u.path}$query${u.hasFragment ? '#${u.fragment}' : ''}';
    web.window.history.replaceState(null, '', clean);
  } catch (_) {}
}
