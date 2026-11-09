# Putting

An Apple Watch app that measures every putting stroke, and an iPhone app
that ties each stroke to how far the ball rolled.

- **Watch:** wear it on your lead wrist and putt. For each stroke it shows
  tempo (backswing time ÷ downswing time), backswing length and
  follow-through length, and taps your wrist when a stroke is recorded.
- **iPhone:** each stroke arrives from the watch. Enter how far the ball
  rolled (or leave it blank for a practice swing). The app builds your
  **stroke chart** (roll distance vs. backswing, plus a "backswing for each
  distance" table) and scores your **consistency** per session.

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
`.watchkitapp`). Run on your iPhone; the watch app installs alongside it.

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
| `Tools/` | Python mirror of the detector for quick checks |
