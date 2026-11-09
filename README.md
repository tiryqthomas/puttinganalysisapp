# Putting

An Apple Watch app that measures every putting stroke, and an iPhone app
that ties each stroke to how far the ball rolled.

- **Watch:** wear it on your lead wrist and putt. For each stroke it shows
  tempo (backswing time ÷ downswing time), backswing length and
  follow-through length, and taps your wrist when a stroke is recorded.
  Tap **Roll** to enter how far the ball rolled with the Digital Crown; it
  starts at what your stroke chart predicts for that backswing.
- **iPhone:** each stroke arrives from the watch. Enter how far the ball
  rolled here or on the watch (a roll entered on either one shows on the
  other), or leave it blank for a practice swing. The app builds your
  **stroke chart** (roll distance vs. backswing, plus a "backswing for each
  distance" table) and scores your **consistency** per session.
- **Paces:** roll distances are entered and shown only in your own paces,
  to the nearest half pace. Pace off the putt with your normal walking
  step. There's nothing to calibrate: the chart learns how far your
  stroke rolls in your paces, which is exactly what you pace off on the
  course. Backswing and follow-through stay in inches (or centimetres).
- **Green speed:** set how fast the greens are for each session, on the
  watch before you start or on the phone, as a range (very slow under 7,
  slow 7–8, medium 9–10, fast 11–12, very fast 13+) or an exact
  Stimp. The stroke chart then shows a curve per speed, and the backswing
  table can be switched to any speed so you can see how to adjust your
  stroke at a faster or slower course.
- **Start from the phone:** the Practice tab has a **Start session** card
  with the green speed. It opens the watch app, which starts measuring and
  shows Ready. You can still start on the watch.
- **Landmarks (optional):** under the roll on the watch, or under the roll
  distance on the phone, note where the putter head stopped against your
  foot (inside, inside-middle, middle, outside-middle, outside), relative
  to where the putter starts on your foot. **Chart → Landmarks** then shows
  the landmark for each roll, and it moves with green speed.
- **Review:** tapping End on the watch opens a recap on the phone with each
  score against your usual range and any new best. Progress shows your
  usual range on the chart, the latest session against your average,
  personal bests and a putt log.
- **Putting card:** on the Chart tab, your backswing for each roll at one
  green speed. **Add to Lock Screen** explains how to put it on your Lock
  Screen as a widget; it follows the speed picked on the Chart tab.

This first milestone is putt analysis only. The green-slope level and
break/speed estimates come later.

## Try it

You need a Mac with Xcode 16 or later.

**1. Run the analysis tests (no project setup needed).**

```sh
cd PuttCore
swift test
```

These run the stroke detector against simulated watch motion and check the
measurements, the stroke chart fit and the consistency scores.

**2. Generate the Xcode project.**

```sh
brew install xcodegen
xcodegen
open PuttingApp.xcodeproj
```

**3. Run on your devices.** Choose the **PuttPhone** scheme. For both the
PuttPhone and PuttWatch targets, open **Signing & Capabilities** and pick
your Apple ID's Personal Team. If a bundle ID is taken, change
`com.tiryqthomas.putting` (keep the watch app's ID as the phone's ID plus
`.watchkitapp`, and the widget's as the phone's ID plus `.widget`). The
phone and the widget share an App Group, `group.com.tiryqthomas.putting`;
if you change the bundle ID, change the group to match in **Signing &
Capabilities** and in `SharedWidget/PuttingCardData.swift`. Run on your
iPhone; the watch app installs alongside it.

No watch handy? On the iPhone's Practice tab, tap the waveform button to
add a simulated stroke. It runs through the same analysis code as a real
one.

## How a stroke is measured

A putting stroke is a pendulum, so the watch rotates mostly about one
axis. The detector (`PuttCore/Sources/PuttCore`):

1. Streams the gyroscope at 100 Hz and waits for you to hold still at
   address (0.35 s).
2. Captures from the first movement until you're still again.
3. Finds the dominant rotation axis, integrates the rotation into an arm
   angle, and reads off the takeaway, top of backswing, impact (the arm back
   through address) and finish.
4. Converts angles to putter-head travel with your pivot-to-putter-head
   length (about 1.1 m for most players; calibrate it in Settings with a
   ruler behind the ball).

Consistency scores (0–100) measure what should stay the same at every
length: tempo, total stroke time (rhythm), follow-through ÷ backswing
(proportion), and how closely each roll matched your stroke chart
(distance control).

## How green speed is handled

A Stimpmeter measures how far a ball rolls from a fixed starting speed, so
the same stroke rolls about in proportion to the Stimp: a putt that rolls
8 paces on an 8 rolls about 11 paces on an 11. The app scales every roll to a
Stimp 10 green and fits one curve to all of them, so every putt helps
estimate every speed (shown dashed). Once a speed range has 5 putts of its
own, it gets its own curve from just those putts (shown solid). Distance
control compares rolls after the same scaling, so changing greens doesn't
hurt your score. Rolls with no speed set are treated as your usual speed.

## How landmarks are handled

A landmark is a fixed spot on your foot, so it always means the same
backswing length. Each landmark you note collects the backswings that
ended there, and its typical backswing is their median. To show the
landmark for a roll, the app asks the stroke chart for the backswing that
roll needs at the chosen green speed, then picks the landmark you've used
whose typical backswing is closest. Faster greens need a shorter
backswing, so the same roll moves toward the inside of your foot. Below 5
notes at a speed, the screen says it's estimated.

## Checking the detector without Xcode

`Tools/sim_check.py` is a Python mirror of the detector. It runs 40
simulated strokes through it and prints the measurement error:

```sh
python3 Tools/sim_check.py
```

If you change a threshold in the Swift detector, change it there too.

## Layout

| Folder | What's in it |
|---|---|
| `PuttCore/` | Swift package: detection, metrics, stroke chart fit, consistency, simulator, tests |
| `PuttWatch/` | watchOS app: motion capture, workout session, live stroke screens |
| `PuttPhone/` | iOS app: distance entry, stroke chart, progress, settings |
| `Shared/` | Watch ↔ phone messages and unit formatting |
| `PuttWidget/` | Lock Screen widget: the Putting card |
| `SharedWidget/` | The Putting card data the phone writes and the widget reads |
| `Tools/` | Python mirror of the detector for quick checks |
