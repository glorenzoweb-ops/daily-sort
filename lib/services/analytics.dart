import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'storage.dart';

/// Anonymous counts of what players do, sent to TelemetryDeck: how many
/// finish the first puzzle, solve today's, come back tomorrow. No names, no
/// advertising id, no tracking across apps: the install gets a random id,
/// hashed on the phone before it leaves.
///
/// Off on the web and in tests (only `main()` starts it), and off when the
/// player turns it off in Settings. Build with `--dart-define=TELEMETRY_APP_ID=`
/// to turn it off for a build.
class Analytics {
  static const appID = String.fromEnvironment('TELEMETRY_APP_ID', defaultValue: 'C2C92760-43C1-42D4-8B99-8CF173B709AF');
  static final _url = Uri.parse('https://nom.telemetrydeck.com/v2/');

  static Storage? _storage;
  static String _user = '';
  static String _session = '';
  static final _queue = <Map<String, Object?>>[];
  static Timer? _timer;

  static bool get on => _storage?.analyticsOn ?? false;

  /// Starts a session. Call once, at launch, on a phone.
  static Future<void> start(Storage storage) async {
    if (kIsWeb || appID.isEmpty) return;
    _storage = storage;
    var id = storage.installId;
    if (id.isEmpty) {
      id = _random();
      await storage.setInstallId(id);
    }
    _user = sha256.convert(utf8.encode(id)).toString();
    newSession();
  }

  /// The app came back to the front after a while.
  static void newSession() {
    if (_storage == null) return;
    _session = _random();
    send('TelemetryDeck.Session.started');
  }

  /// Queues signal [type] with [params]. Sent in small batches.
  static void send(String type, [Map<String, Object?> params = const {}]) {
    if (!on || _user.isEmpty) return;
    _queue.add({
      'receivedAt': DateTime.now().toUtc().toIso8601String(),
      'appID': appID,
      'clientUser': _user,
      'sessionID': _session,
      'type': type,
      'isTestMode': kDebugMode ? 'true' : 'false',
      'payload': {
        'TelemetryDeck.Device.platform': defaultTargetPlatform.name,
        for (final e in params.entries) e.key: '${e.value}',
      },
    });
    if (_queue.length >= 10) {
      flush();
    } else {
      _timer ??= Timer(const Duration(seconds: 20), flush);
    }
  }

  /// Sends what is queued (also when the app goes to the background).
  static Future<void> flush() async {
    _timer?.cancel();
    _timer = null;
    if (_queue.isEmpty) return;
    final batch = List.of(_queue);
    _queue.clear();
    try {
      final r = await http
          .post(_url, headers: {'Content-Type': 'application/json'}, body: jsonEncode(batch))
          .timeout(const Duration(seconds: 15));
      // Retry later only when the server may take it next time.
      if (r.statusCode >= 500) _requeue(batch);
    } catch (_) {
      _requeue(batch);
    }
  }

  static void _requeue(List<Map<String, Object?>> batch) {
    // Offline: keep the newest few for the next try.
    _queue.insertAll(0, batch);
    if (_queue.length > 50) _queue.removeRange(0, _queue.length - 50);
  }

  /// The player turned analytics off: drop what was waiting.
  static void stopped() {
    _queue.clear();
    _timer?.cancel();
    _timer = null;
  }

  static String _random() {
    final r = Random.secure();
    return List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }
}
