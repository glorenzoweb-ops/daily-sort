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
| `lib/ui/picture.dart` | Picture of the day: 8 coloring-book scenes drawn in code. Each ball color paints one part, which fills in when you complete that color's tube. The title is revealed on solve |
| `lib/ui/social.dart`, `lib/services/friends.dart` | Friends board. Results travel in the share link (`?r=2-13-1-5-Ana`), so there's no server: opening a friend's link puts them on your board for that day |
| `lib/ui/archive.dart` | Past puzzles (with their pictures) and the Daily Sort+ paywall |
| `lib/services/puzzles.dart` | Hands out puzzles with no waiting: saves daily puzzles on the device, prepares tomorrow's after a win and the next Unwind puzzle ahead of time |
| `lib/services/background.dart` | Runs heavy work (sound synthesis, puzzle generation) off the UI thread on phones, between frames on the web |

**Streaks.** Every 5 Unwind solves earn a streak freeze (bank up to 2). When you open the game after missing days, banked freezes cover them automatically (`Stats.applyFreezes`); a freeze keeps the streak but doesn't add a day.

**Picture of the day.** `sceneForNumber(n)` picks the day's scene, the same for everyone and never the same two days running. Add scenes at the end of `scenes` in `lib/ui/picture.dart`: each is 5 paths on a 200 x 100 canvas, one per ball color (red, yellow, green, blue, purple). On 4-color days the purple part starts colored. The share image now shows the picture with the solve painting under it.

**Friends.** Sharing asks once for a first name and adds a link to your result. When a friend opens it, they see a toast ("Ana solved today's puzzle in 12 moves. Your turn!"), a chip above the board, and a ranked board (fewest moves, then fewest tries). Results are kept on the device for 30 days. A live board without shared links would need a small backend (for example Supabase); the link format stays the same.

**Archive and Daily Sort+.** Today's puzzle is always free. The last 3 days of the archive are free (`freeArchiveDays`), and puzzles you already played stay open. Older days open the paywall (yearly $19.99 with a 7-day trial, or $2.99 a month). Until payments are wired in, the button explains that Plus opens with the store release and counts the tap (`premiumInterest` in storage) so you can see demand. Build with `--dart-define=PREMIUM=true` to test everything unlocked. Archive solves never touch the streak or stats.

**Hints.** The bulb under the board finds the first move of a shortest solution from where you are (`GameController.findHint`): a gold arrow over the tube to tap and a ring on the one to pour into. If the board can't be sorted in the moves left, it says how many moves to undo, then points the way on. One free hint per daily puzzle (`freeHintsPerDay`); Unwind and Daily Sort+ are unlimited. Used hints show as 💡 on the shared result.

**Look.** Settings (the sliders icon) has Auto / Light / Dark and colorblind mode (`lib/ui/appearance.dart`). Dark mode turns the sky into a deep night and the menus dark; the colors live in `Palette`, which every widget reads. Colorblind mode swaps in Okabe-Ito based colors and draws a shape on every ball (`Palette.shapes`).

**History.** The statistics sheet shows the last few weeks as a calendar (`lib/ui/history.dart`): solved days glow gold by stars, tap a day for moves, par, tries and hints. Par is saved with each solve.

**Reactions.** On the friends board, tap 😊 on a friend's row to send 👏 🔥 😮 or 😂. Like results, a reaction travels in a link (`?x=2-1-Ana`, with your own result as `&r=` when you've solved), so it needs no server. The friend gets a toast and sees it under their row.

**Performance notes.** On the web, Flutter redraws the whole screen on every frame, so the game keeps frames few and cheap:
- `web/index.html` caps rendering at 2 pixels per CSS pixel. 3x phone screens look the same and each frame costs less than half as much.
- Background motion (sky, ball buddies breathing and blinking) runs on one shared 20 fps clock (`lib/ui/ambient_clock.dart`), driven by a timer rather than a ticker. The board only runs at full frame rate while something moves and then goes back to sleep.
- The board stamps pre-rendered images (glass, shelf, corks, balls, glows). The images a completed tube and the win need are prepared one per idle frame in advance. Making them at the moment itself means a read back from the graphics card, which hitches.
- The picture of the day is recorded once and turned into an image a moment after it changes. The sky's static part is redrawn every 10 minutes.
- `lib/ui/warmup.dart` draws one of each effect into a tiny hidden image at startup, so the graphics card has compiled them before the first tube completes.
- Avoid `Opacity` and `ShaderMask` on things that stay on screen: each costs an extra offscreen pass on every frame.
- Fonts are bundled in `assets/google_fonts/` (OFL licensed), so nothing is downloaded at startup.
| `lib/services/share.dart` | Emoji share card and native share sheet (clipboard fallback on desktop web) |
| `lib/services/premium.dart` | Daily Sort+ plans, archive gating, and the hook for real payments |

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

**Comfort and access.** Settings has volume sliders (pours, soundscape, music), a vibration switch, Reduce motion (no confetti, shake, bounce or breathing balls, and a still sky; it follows the phone's setting until the player picks, `lib/ui/motion.dart`) and "Share results as words" (no emoji squares; on by default while a screen reader runs). Every tube is a screen-reader button that reads its balls bottom to top, and each tap is announced.

**Backup code.** Settings → New phone? → Save code copies (or shares) one line, `DS1-…`, holding everything the device saved except the puzzle cache. Restore on the other device replaces its progress and restarts the game screen (`lib/services/backup.dart`). No account, no server.

**Travel grace.** The streak keeps the phone's time zone from the last solve. If exactly one day is missed and the time zone changed, the streak is kept without spending a freeze, and flying west back to an older puzzle number never resets it (`Stats.applyTravelGrace`, `Stats.addDailySolve`).

**Don't change the generator** (`rng.dart`, `daily.dart`, `board.dart` move rules) once people are playing: every past and future puzzle would change. The test `first 60 puzzles match the pinned fingerprint` fails if you do.

## Adding Daily Sort+ later ($2.99/mo)

Payments aren't wired in. When you're ready:

1. Add RevenueCat (`purchases_flutter`) and create the product in App Store Connect and Play Console. RevenueCat also handles Stripe for web.
2. Write a `PremiumService` subclass backed by RevenueCat and swap it in `lib/main.dart` (replace `ComingSoonPremium`).
3. The archive is already gated (`archiveLocked` in `lib/services/premium.dart`) and the paywall calls `premium.purchase(plan)`. Set `canPurchase` to true in your RevenueCat service. Still to gate:
   - **Hints:** `solveOptimal(game.board).first` is the best next move from any position.
   - **Hard mode:** move limit = par (`defaultMoveSlack = 0`).
