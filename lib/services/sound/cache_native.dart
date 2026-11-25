import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// Bump when any synth changes, so phones rebuild the sounds.
const _version = 1;

Directory? _dir;

Future<Directory?> _folder() async {
  if (_dir != null) return _dir;
  try {
    final base = await getApplicationSupportDirectory();
    final d = Directory('${base.path}/sounds_v$_version');
    if (!d.existsSync()) d.createSync(recursive: true);
    return _dir = d;
  } catch (_) {
    return null;
  }
}

/// The samples saved under [key], or [make]'s result (saved for next time).
Future<Float32List> cachedSamples(String key, Future<Float32List> Function() make) async {
  final d = await _folder();
  final f = d == null ? null : File('${d.path}/$key.f32');
  try {
    if (f != null && f.existsSync()) {
      final bytes = await f.readAsBytes();
      if (bytes.lengthInBytes % 4 == 0 && bytes.isNotEmpty) {
        return Float32List.sublistView(Uint8List.fromList(bytes));
      }
    }
  } catch (_) {}
  final samples = await make();
  if (f != null) {
    try {
      await f.writeAsBytes(samples.buffer.asUint8List(samples.offsetInBytes, samples.lengthInBytes), flush: true);
    } catch (_) {}
  }
  return samples;
}
