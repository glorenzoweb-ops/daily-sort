# Daily Sort

One color-sort puzzle a day, the same for everyone. Sort the balls within the move limit, hit par for three stars, and share a Wordle-style emoji card.

Built with Flutter 3.50 for web, Android and iOS.

## Run it

```bash
git clone https://github.com/glorenzoweb-ops/daily-sort.git
cd daily-sort
flutter pub get

flutter run -d chrome        # web
flutter run -d <android-id>  # Android emulator or phone (see `flutter devices`)
open ios/Runner.xcworkspace  # iOS: set your Team under Signing, then
flutter run -d <iphone-id>   # run on a simulator or iPhone
```

Run the tests (they prove the next 400 daily puzzles are solvable within their move limit):

```bash
flutter test
```

## Put the web version live (GitHub Pages, free)

1. The repository must be **public** for free GitHub Pages (Settings → General → Danger Zone → Change visibility), or you need a paid plan.
2. Settings → Pages → Build and deployment → Source: **GitHub Actions**.
3. Merge to `main` (or run the "Deploy web to GitHub Pages" workflow by hand under Actions).

The site goes live at **https://glorenzoweb-ops.github.io/daily-sort/** in about 3 minutes. Every push to `main` redeploys.

If you rename the repo or use a custom domain, update `shareUrl` in `lib/services/share.dart`. For a custom domain at the root, build with `--base-href /` instead.

## Ship to Android (Google Play)

1. Change the app id if you want (`applicationId` in `android/app/build.gradle.kts`, now `com.glorenzoweb.daily_sort`). It can't change after the first upload.
2. Create an upload keystore and signing config: https://docs.flutter.dev/deployment/android#sign-the-app
3. `flutter build appbundle` and upload `build/app/outputs/bundle/release/app-release.aab` to the Play Console.
4. New personal accounts must run a closed test with 12+ testers for 14 days before production. Start that early.

## Ship to iOS (App Store)

1. In Xcode, set the bundle id (now `com.glorenzoweb.dailySort`) and your Team.
2. `flutter build ipa`, then upload with Xcode Organizer or Transporter, and test through TestFlight.

## How it works

| Path | What it does |
| --- | --- |
| `lib/game/rng.dart` | 32-bit PRNG that gives identical numbers on the Dart VM and on the web, so everyone gets the same puzzle |
| `lib/game/daily.dart` | Turns a date into a puzzle: seeds the PRNG with the date, deals balls, and keeps re-dealing until the optimal solution length (par) is in the day's range. Move limit = par + 2 |
| `lib/game/solver.dart` | Breadth-first solver that finds the optimal solution. Every puzzle ships with a proven solution |
| `lib/game/board.dart` | Pour rules |
| `lib/game/game_controller.dart` | Game state, undo, restart, win detection, stats and streaks |
| `lib/ui/board_view.dart` | Custom-painted board: glass tubes on a wooden shelf, glossy ball buddies, pours with trails and squash, corks on finished tubes, and the win where colors stream into your painting |
| `lib/ui/sky.dart` | Background sky that follows the player's local time (morning, day, sunset, starry night) |
| `lib/ui/streak.dart` | Flame streak counter, streak sheet, freeze progress, and milestone celebrations (3, 7, 14, 30, 50, 100, 200, 365 days) |
| `lib/ui/squish.dart` | Soft press feedback for every button |
| `lib/services/puzzles.dart` | Hands out puzzles with no waiting: saves daily puzzles on the device, prepares tomorrow's after a win and the next Unwind puzzle ahead of time |
| `lib/services/background.dart` | Runs heavy work (sound synthesis, puzzle generation) off the UI thread on phones, between frames on the web |

**Streaks.** Every 5 Unwind solves earn a streak freeze (bank up to 2). When you open the game after missing days, banked freezes cover them automatically (`Stats.applyFreezes`); a freeze keeps the streak but doesn't add a day.

**Performance notes.** The board stamps pre-rendered images (glass, shelf, corks, balls, glows) instead of redrawing gradients and blurs every frame, and drops to ~24 fps when nothing is moving. The sky redraws its static parts every 2 minutes and moves clouds and stars at 20 fps. Fonts are bundled in `assets/google_fonts/` (OFL licensed), so nothing is downloaded at startup.
| `lib/services/share.dart` | Emoji share card and native share sheet (clipboard fallback on desktop web) |
| `lib/services/premium.dart` | Hook for the future Daily Sort+ subscription |

Puzzle #1 is Nov 20, 2026. The weekly rhythm (`weekdaySpecs` in `lib/game/daily.dart`):

| Day | Puzzle |
| --- | --- |
| Mon | Classic, easy |
| Tue | Tall tubes (5 balls each) |
| Wed | Picky tube (only takes one color) |
| Thu | Locked tube (opens after 3 moves) |
| Fri | Classic, medium |
| Sat | Classic, 5 colors |
| Sun | Picky tube, 5 colors |

Every pour plays a note (`lib/services/sound.dart`, synthesized, no audio files) and each solve is drawn as a painting (`lib/ui/solve_art.dart`) that players share as an image. The leaf button opens Unwind: endless 4-color puzzles with no move limit, a breathing glow (10 s cycle, about 6 breaths a minute) and optional soundscapes (rain, waves, fireplace, night), all synthesized in `lib/services/sound/`. Unwind doesn't count for stats.

Soundscapes react to play: they fade down to 40% as tubes complete, a wind chime tuned to the pour notes rings for each finished tube, and birdsong plays on the solve. "Calm music" in the sound panel adds a slow pad and a kalimba that wanders over the same pentatonic notes, so it never repeats the same way (`lib/services/sound/music.dart`).

**Don't change the generator** (`rng.dart`, `daily.dart`, `board.dart` move rules) once people are playing: every past and future puzzle would change. The test `first 60 puzzles match the pinned fingerprint` fails if you do.

## Adding Daily Sort+ later ($2.99/mo)

Payments aren't wired in. When you're ready:

1. Add RevenueCat (`purchases_flutter`) and create the product in App Store Connect and Play Console. RevenueCat also handles Stripe for web.
2. Write a `PremiumService` subclass backed by RevenueCat and swap it in `lib/main.dart` (replace `ComingSoonPremium`).
3. Gate features with `premium.isUnlocked(PremiumFeature.archive | hints | hardMode)`:
   - **Archive:** `puzzleForDay(dayForNumber(n))` already returns any past puzzle.
   - **Hints:** `solveOptimal(game.board).first` is the best next move from any position.
   - **Hard mode:** move limit = par (`defaultMoveSlack = 0`).
