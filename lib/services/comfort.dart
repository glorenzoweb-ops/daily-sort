import 'feedback.dart';
import 'sound.dart';
import 'sound/ambience.dart';
import 'storage.dart';

/// Applies the saved sound and vibration settings. Runs at start, and again
/// after a backup is restored.
void applySoundAndHaptics(Storage storage) {
  Haptics.enabled = storage.hapticsOn;
  // Before the volume sliders there was only an on/off switch.
  Sounds.setEffectsLevel(storage.soundOn ? storage.volume('effects') : 0);
  Sounds.ambienceLevel = storage.volume('ambience');
  Sounds.musicLevel = storage.volume('music');
  Sounds.ambience = Ambience.values.asNameMap()[storage.ambience] ?? Ambience.off;
  Sounds.music = storage.musicOn;
}
