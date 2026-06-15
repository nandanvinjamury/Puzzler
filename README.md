# ♞ Puzzler

A chess alarm clock for Android: the alarm keeps ringing until you solve a chess puzzle. Built with Flutter, it pulls the Lichess daily puzzle plus a bundled set of tactics, and it plugs into [Sleep as Android](https://play.google.com/store/apps/details?id=com.urbandroid.sleep) as a dismiss CAPTCHA so the puzzle is what actually turns off your morning alarm.

## 💡 Why I Built This

I wanted two things at once: to wake up without hitting snooze, and to keep my tactics sharp without remembering to open a chess app. A puzzle you have to solve before the alarm stops does both. You can't dismiss it half-asleep, and you get a few minutes of calculation in before your feet hit the floor.

Most "math problem" alarm dismissals are trivial. A chess puzzle forces real attention, and the difficulty is self-calibrating because Lichess publishes a fresh tactic every day.

## ⚡ How the Sleep as Android Integration Works

Sleep as Android lets third-party apps act as a "dismiss CAPTCHA": the alarm fires, your app launches, and the alarm only stops when your app reports the puzzle solved. There is an official support library for this, but it depends on the legacy `android.support.*` packages, so I reverse-engineered the wire contract and reimplemented the minimal version natively in Kotlin.

The contract is not obvious. When Sleep launches the app, it hands over pre-built callback `Intent` objects as `Parcelable` extras, keyed by event name (`"solved"`, `"unsolved"`, `"alive"`). To report an event you pull the matching intent out of the launch bundle and fire it yourself, switching between `sendBroadcast` and `startActivity` depending on whether the captcha is operational or just being previewed in Sleep's settings picker. The app also sends an `"alive"` heartbeat every five seconds so Sleep doesn't time the captcha out while the sleeper is still calculating.

One problem took the longest to solve: Sleep wouldn't list the app as a captcha at all. The cause turned out to be Android 11+ package visibility, not the intent filter. I pulled Sleep's APK and confirmed it has no `QUERY_ALL_PACKAGES` permission and no `<queries>` entry for the captcha `OPEN` action, so it literally cannot see a sideloaded third-party captcha. The fix is to install with the `--force-queryable` flag, which makes the app visible to every installed app and gets it listed. The native contract lives in [`MainActivity.kt`](android/app/src/main/kotlin/com/puzzler/puzzler/MainActivity.kt) and [`CaptchaActivity.kt`](android/app/src/main/kotlin/com/puzzler/puzzler/CaptchaActivity.kt) (sharing logic in [`CaptchaHostActivity.kt`](android/app/src/main/kotlin/com/puzzler/puzzler/CaptchaHostActivity.kt)), bridged to Dart over a `MethodChannel` in [`captcha.dart`](lib/captcha.dart).

### Selecting It in Sleep as Android

Install both apps on the same phone, then open Sleep at least once after installing Puzzler so it re-scans for captcha apps. To assign it: open the **Alarms** tab, tap an alarm, tap **CAPTCHA**, and choose **"Chess puzzle"** from the list. It lists as "Chess puzzle", not "Puzzler", which is the most common reason people think it's missing. If it still doesn't appear, force-stop Sleep and reopen it to clear its cached captcha list, confirm Sleep is up to date (package-visibility discovery needs a recent build), and make sure both apps are in the same profile.

## 🧠 The Offline Analysis Engine

After you solve, the analysis board shows "best line" arrows so you can test alternatives: a blue arrow for the best move for the side to move, an orange arrow for the opponent's best reply, and a chip showing live `depth N · eval/M#`. These come from a chess engine I wrote in pure Dart ([`engine.dart`](lib/engine.dart)): negamax with alpha-beta pruning, quiescence search, killer-move and history ordering, check extensions, triangular-PV extraction, and a tapered piece-square evaluation. It runs in a background isolate with streaming iterative deepening, so the arrows sharpen the longer you look at a position (roughly a 10-second budget, capped at depth 64, stopping early on a forced mate).

I chose pure Dart over the `stockfish` FFI package for two concrete reasons. The target device is a Pixel 7 running Android with 16 KB memory pages, which the base Stockfish wrapper isn't built for, and modern Stockfish needs an NNUE network that some wrappers download at runtime, which breaks the offline requirement. The whole point is that the puzzle works at 6 a.m. with no network. The engine is weaker than Stockfish, but it reliably surfaces the key move in a tactical position, which is all the analysis board needs.

## 🛠️ Tech Stack

| Layer | Choice | Reason |
| --- | --- | --- |
| App framework | Flutter / Dart | Single codebase, native Android build for the alarm integration |
| Board UI | [`chessground`](https://pub.dev/packages/chessground) 10 | The board widget Lichess uses; drag, arrows, custom shapes |
| Chess logic | [`dartchess`](https://pub.dev/packages/dartchess) 0.13 | Move generation, SAN/UCI/FEN parsing, legality checks |
| Puzzle source | Lichess public API | Free daily puzzle, no auth required for the daily endpoint |
| Analysis | Custom pure-Dart engine | Fully offline, no NDK build, safe on 16 KB memory pages |
| Persistence | `shared_preferences` | Streaks, XP, and the pre-fetched puzzle cache |
| Alarm integration | Native Kotlin + `MethodChannel` | Sleep as Android captcha contract |

No backend, no database server. Everything runs on the device.

## 🧩 How the Puzzles Work

The daily puzzle comes from `GET https://lichess.org/api/puzzle/daily`, which returns a game PGN and a UCI solution. Reaching the puzzle position means replaying the entire PGN, since `initialPly` is one less than the PGN's ply count and the last move is the highlighted setup move. The orientation of the board is whichever side is to move after that replay.

Solve-gating compares moves by resulting position, not by raw notation. A user move counts as correct when `pos.play(userMove).fen == pos.play(expectedMove).fen`. Comparing by FEN instead of by UCI string avoids false rejections on castling (king-takes-rook versus king-to-file notation) and on promotions.

For variety beyond the once-a-day puzzle, the app ships about 60 bundled tactics and keeps a pre-fetched cache ([`puzzle_source.dart`](lib/puzzle_source.dart)) so an alarm never has to make a live API call against a rate-limited endpoint. The cache hands out a random puzzle each time, so the morning session isn't the same order every day.

## 🚀 Running It

This is a personal Android build. You will need Flutter 3.44+ (Dart 3.12+), JDK 17, and an Android device.

```bash
flutter pub get

# A Lichess API token is optional; the daily puzzle needs no auth.
# Scope: puzzle:read
flutter run -d <device-id> --dart-define=LICHESS_TOKEN=<token>
```

To install so that Sleep as Android can see it as a captcha, build a release APK and install with the force-queryable flag:

```bash
flutter build apk --release --dart-define=LICHESS_TOKEN=<token>
adb install -r --force-queryable build/app/outputs/flutter-apk/app-release.apk
```

A plain `flutter install` or `adb install` re-hides the app from Sleep, so the `--force-queryable` install is required for the captcha integration.

Build environment notes:

- Flutter must use JDK 17 for Gradle, not the Android Studio JBR: `flutter config --jdk-dir "<path-to-jdk-17>"`. Java 21 fails with "Unsupported class file major version 65".
- On the Pixel 7, Google Play Protect blocks ADB installs with `INSTALL_FAILED_VERIFICATION_FAILURE` until it is disabled on the phone.

## 📂 Project Structure

```
lib/
  main.dart                  App entry, captcha launch routing, daily-puzzle replay
  lichess.dart               Lichess API client (daily puzzle, next, token handling)
  puzzle_source.dart         On-device puzzle cache + bundled fallback set
  puzzle_board.dart          Interactive board, solve-gating, engine arrows
  engine.dart                Pure-Dart chess engine (negamax + iterative deepening)
  captcha.dart               Dart side of the Sleep as Android MethodChannel bridge
  progress.dart              Streaks, XP, and leveling
  theme.dart                 chess.com-inspired dark palette
  widgets.dart               Shared UI (streak flame, progress bars)
  screens/
    home_screen.dart         Home, with normal and captcha modes
    alarm_session_screen.dart  The alarm session: daily puzzle + 3 randoms
    puzzle_review_screen.dart  Read-only analysis of a solved puzzle

android/app/src/main/kotlin/com/puzzler/puzzler/
  MainActivity.kt            Launcher activity + captcha channel
  CaptchaActivity.kt         Dedicated captcha entry point for Sleep
  CaptchaHostActivity.kt     Shared captcha signaling logic

assets/fallback_puzzles.json  ~60 bundled tactics for offline variety
```

## ✨ Features

- Alarm dismissal gated on solving a real chess puzzle, via Sleep as Android.
- Lichess daily puzzle plus about 60 bundled tactics, all usable offline.
- Post-solve analysis board with engine "best line" arrows, computed on-device.
- Streaks, XP, and a leveling system to reward consistent solving.
- Pre-fetched, randomized puzzle cache so the alarm never waits on the network.
- A custom pure-Dart engine with no native build dependencies.

## 🗺️ Possible Extensions

- Per-difficulty puzzle selection mapped to Sleep's 1–5 difficulty slider.
- A stronger engine via `lichess-org/dart-stockfish`, once 16 KB pages and offline NNUE are verified.
- Themed puzzle packs (endgames, mating nets) for targeted practice.

## License

MIT. See [LICENSE](LICENSE).
