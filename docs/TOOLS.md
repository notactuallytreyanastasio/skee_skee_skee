# Tools

`swift build -c release`, then `.build/release/skee`. Everything below runs
headless on macOS against the same core and renderer as the app.

## Physics

```
skee shot 0.62 0                 # one ball, described
skee shot 0.84 -0.5 --trace      # with the recorded path
skee map --ante 8 --boss crosswind
skee windows --boss slickLane    # widest power window per hole
```

`map` glyphs: `.` gutter, `1`-`5` the 10 to 50 rings, `L`/`R` the pockets.

## Playing a run by hand

```
skee play run.json new 2026
skee play run.json throw 0.62 0 --hand regular   # power aim [start] [fold]
skee play run.json buy 2 50                      # offer 2, targeted at the 50
skee play run.json buy 1
skee play run.json reroll | sell 0 | arm 0 | leave | show
```

The save is `{seed, actions}` and is replayed on every command. `--hand
<perfect|expert|regular|novice>` wobbles the throw like a player of that skill
would. Without it, keyboard throws are exact, which no thumb can be, so playing
without it says little about fun. The wobble is seeded, and the wobbled launch
is what gets saved.

## Bots and balance

```
skee bot 1005 --skill expert     # narrate one bot run
skee balance --runs 100          # expert, regular, novice
make balance
```

Bots aim at the centre of each hole's widest window and add Gaussian noise
(`Skill`). They pick the hole with the best measured hit rate times value,
counting payline improvement. They buy charms in a fixed preference order,
stamp sevens and clovers onto the 40, gild the 50, and fire specialty balls on
the third ball. They are a yardstick, not an opponent.

`balance` prints: win rate, the ante each run reached, the top causes of death
(by boss), the hole mix, rattles per ball, pair and triple rates, jackpots and
fever frames per run, the share of close rounds (within 15% of target), and
score/target at p10/p50/p90 per ante.

## Pictures

```
skee scene --out out/cabinet.png                    # the 3D cabinet alone
skee frame --save run.json --t 0.8 --out out/f.png  # 3D + HUD, mid-throw
skee frame --save run.json --settle --select 2      # prize counter, stamp selected
skee frame --shop [--title] --size outer           # prize shop (or title) with a sample shelf
skee frame --coach 3 --size outer                  # lesson card for step 3 (0...11)
skee frame --tip boss                              # a first-time card, by name (see Tip)
skee frame --arrival 1                             # Sal's line at the door (0...4)
skee frame --host --first [--signed]               # the first haggle, or its deal
skee frame --guide [--topic 11]                    # the Guide, or one topic
skee frame --line 0.6                              # waiting ball on a release line, with its guide
skee frame --room penthouse --pulled               # a room's cabinet, machine already pulled at max bet
skee frame --host                                  # the host's table mid-haggle (canned, no network)
skee frame --title                                 # title with the room picker and a host invitation
skee frame --title
skee scenefilm --save run.json --from 0.5 --frames 8 --dt 0.12   # contact sheet
```

The framing, the exposure, the lane UV flip and the tray count were all found
by looking at these.

## The trailer

```
skee moments --runs 300            # scan bot runs for jackpots, combos, big frames, by seed and action
skee film --out out/trailer --fps 60             # 16:9 and 9:16 mp4s, about three minutes
skee film --out /tmp/t --only 2,3                # just those shots, to check an edit
```

Every frame is a real reducer step from a real bot run, through the real
`Presentation`, cabinet and HUD, at the inner display's size. Sound is the
game's `Synth` on the game's cues. Two things are made for the film: the thumb
trail, and the music bed. The edit is the list at the bottom of
`Sources/skee/FilmCommand.swift`; the host lines there are a transcript of a
live `skee haggle`, not writing. Needs `ffmpeg` on the path. Changing the
physics or the rules moves the seeds: rerun `moments` and check the edit.

## The simulator

```
cd App && xcodegen generate
xcodebuild -project SkeeSkeeSkee.xcodeproj -scheme SkeeSkeeSkee \
  -destination 'platform=iOS Simulator,name=iPhone Duo' -derivedDataPath ../.build/xcode build
xcrun simctl install <udid> ../.build/xcode/Build/Products/Debug-iphonesimulator/SkeeSkeeSkee.app
xcrun simctl launch <udid> com.bobbygrayson.skeeskeeskee -seed 9 -ante 5 -autoplay "0.62,0;0.6,0.1"
xcrun simctl io <udid> screenshot --display=LCD shot.png
```

Launch arguments: `-seed`, `-fresh`, `-ante` (to see a later era), `-fold`,
`-autoplay "power,aim[,start];..."`, `-skipTitle`.

The simulator boots the Duo folded. `--display=LCD` captures the outer display;
the inner one (`LCD-1`) stays black until the device is unfolded, and there is
no `simctl` command to unfold it.

## The host, live

```
scripts/secrets.sh                                 # copy the DeepSeek key from ../marginalia/.env (gitignored)
skee haggle --room neonLounge                      # talk to the host on stdin; "deal" accepts
skee haggle --room highRoller --say "MORE|more!!"  # scripted; prints what the model asked for and what the rules allowed
skee balance --room neonLounge                     # bots in a room
skee windows --room penthouse                      # hole windows on a room's board
```

Each haggle turn prints the reply time, the model's mood, the offer it asked
for, and the offer the rules allowed. A model that overreaches shows up as
the two differing.

## Building for the App Store

Three build configurations, and the difference matters:

| Configuration | How it reaches DeepSeek | Use |
|---|---|---|
| Debug | directly, with the key | Xcode |
| Device | directly, with the key | your own phone, optimized |
| Release | through the relay, no key in the app | the App Store |

Every configuration asks permission before the first line is sent, and falls back to the scripted host if the player says no, the phone is offline or the relay's limit is hit.

Release never includes `Secrets.xcconfig`, because anything in Info.plist can be read out of a downloaded app. `relay/` is the server half; its README has the setup. `scripts/archive.sh` builds the archive, fails if the key is in the bundle or the relay isn't set, and exports the .ipa. `--upload` sends it to App Store Connect, which is not a submission.

`skee icon` redraws the app icon. Launch arguments `-seed 7 -skipTitle -panel host|guide|shop` open a screen in the simulator for screenshots. The listing, age rating answers and review notes are in `docs/appstore/LISTING.md`.
