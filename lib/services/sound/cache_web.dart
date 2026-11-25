import 'dart:typed_data';

/// Returns [make]'s result. Browsers keep nothing between visits here.
Future<Float32List> cachedSamples(String key, Future<Float32List> Function() make) => make();
