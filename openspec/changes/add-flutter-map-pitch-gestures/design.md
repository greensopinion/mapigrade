## Context

`docs/map-pitch-concept.md` section 8 (change 3) and decisions 13 and 19 record the decisions this design implements; the requirements are in `specs/flutter-map-pitch/spec.md`. File references are to the fork's branch `map-pitch` at `04c3e14` (change 1).

Relevant current state in `lib/src/gestures/map_interactive_viewer.dart`:

- A `Listener` counts pointers (`_pointerCounter`) on `PointerDown`, `PointerUp` and `PointerCancel` and keeps no positions. A `ScaleGestureRecognizer`, the captain of a gesture arena team with the vertical and horizontal drag recognizers, drives drag and the multi-finger gestures. `ScaleUpdateDetails` has the focal point, scale and rotation, but no per-finger positions.
- `_handleScaleStart` chooses drag mode for one pointer, otherwise multi-finger mode. `_handleScaleMultiFingerUpdate` either applies zoom, move and rotate together (`enableMultiFingerGestureRace` false, the default), or first runs the race in `_determineMultiFingerGestureWinner` and then applies the winner's `MultiFingerGesture` set.
- Zoom and move are computed from values at the start of the gesture (`details.scale`, `_focalStartLocal`). Rotation is applied incrementally, from `currentRotation - _lastRotation`.
- `ScaleGestureRecognizer._reconfigure` ends the gesture (`onEnd`) and starts a new one (`onStart`) whenever a pointer is added or removed, so each scale gesture has a fixed number of pointers.
- A macOS trackpad sends `PointerPanZoom` events, not `PointerDown`, and they carry no per-finger positions.
- Cursor/keyboard rotation (Ctrl-drag) is handled in `_onPointerDown` (`rotateStarted`), `_onPointerMove` (rotation to the cursor's angle about the viewport center) and `_onPointerUp` (set north on click). It emits no rotate end event. While the trigger key is held, the drag, pinch and fling handlers return early.
- `MapControllerImpl.pitchRaw` clamps the pitch, keeps the center and emits `MapEventPitch`. There are no pitch start or pitch end events.

MapLibre GL JS's handlers (`src/ui/handler/two_fingers_touch.ts` and `mouse.ts` on its `main` branch) are the reference for the rules and rates below.

## Goals / Non-Goals

**Goals:**

- Decide whether a two-finger gesture is a pitch gesture before any zoom, rotate or move is applied, in both race modes, without changing either race mode's behavior once pitch is ruled out.
- Keep every code path that runs while pitch gestures are disabled unchanged, so that the existing gesture tests are the compatibility check.

**Non-Goals:**

- Adding pitch to the multi-finger race as a fourth competitor (decision 2).
- A pitch gesture from a trackpad, keyboard keys, or a fling of the pitch.
- Anchoring the pitch on the focal point, as iOS does.

## Decisions

### 1. Per-finger positions come from the `Listener`

The viewer keeps a map from pointer id to the position at `PointerDown` and the latest position, updated in `_onPointerMove` and removed in `_onPointerUp` and `_onPointerCancel`. `_handleScaleStart` records the start position of each tracked pointer, because the scale gesture can start after the pointers went down. Trackpad gestures add no entries, so they are never pitch candidates and behave as now.

Alternative: a custom recognizer in the gesture arena. Rejected: the scale recognizer must still win the arena for zoom, move and rotate, and two recognizers would have to share one decision.

### 2. A pitch decision precedes the race

Each multi-finger scale gesture has a pitch state, reset in `_handleScaleStart`:

```
                 not enabled, not exactly 2 pointers,
                 or finger line > 45 deg from horizontal
  [start] ------------------------------------------------> [ruled out]
     |                                                           ^
     | otherwise                                                 |
     v                                                           |
 [undecided] -- a finger moves more horizontally than vertically,|
     |          fingers move in opposite vertical directions,    |
     |          or one finger past the threshold and the other   |
     |          not moving within 100 ms ------------------------+
     |
     | both fingers moved >= threshold, each more vertically
     | than horizontally, in the same vertical direction
     v
 [pitch]
```

The rules are GL JS's `TwoFingersTouchPitchHandler`: the finger line counts as near horizontal when its vertical component is no larger than its horizontal component, a finger's movement counts as vertical when its vertical component is larger, and the single-finger window is 100 ms (`ALLOWED_SINGLE_TOUCH_TIME`). "Enabled" is `InteractiveFlag.hasPitch(flags)` and a clamped maximum pitch above 0.

- **Undecided:** `_handleScaleMultiFingerUpdate` returns before the race and before applying zoom, move or rotate. `_lastRotation` and `_lastScale` stay at their start values, so that the first update after the decision sees the whole gesture so far.
- **Ruled out:** the existing code runs unchanged. Zoom and move are computed from the gesture's start values and rotation from `_lastRotation` (still 0), so the first update applies everything held back, and the ground under the focal point is where it would have been without the hold-back. In race mode, the race runs on the same values. A gesture that is ruled out at its start never holds back.
- **Pitch:** zoom, move and rotate are not applied for the rest of the gesture. The pitch is `startPitch − 0.5 · (focal.dy − focalStart.dy)`, set through `pitchRaw`, which clamps it and keeps the center (spec: pitch pivots on the viewport center). With two pointers the focal point is the midpoint, so this is GL JS's average vertical finger movement times −0.5°. Computing from the start, as iOS does, rather than accumulating deltas, as GL JS does, makes the pitch a function of the finger position, so moving back after reaching the maximum returns to the same pitch.

`_handleScaleEnd` emits the pitch end event and returns before the fling code when the state is pitch. The recognizer's restart on a pointer change (Context) ends a pitch gesture when a third finger touches or one finger lifts; the remaining pointers start a new gesture with a new decision.

Alternative: add `MultiFingerGesture.pitch` to the race. Rejected: the race is off by default, so most applications would still apply zoom and move during a pitch drag, and the race's own thresholds (40 px for move) are larger than the pitch decision needs.

Alternative: apply zoom, move and rotate while undecided and undo them when pitch wins. Rejected: undoing a rotation about a moving focal point isn't exact, and both MapLibre platforms hold back instead.

### 3. Pitch threshold

`InteractionOptions.pitchThreshold`, in px of movement per finger, defaults to 2.0, GL JS's value. It is included in `==` and `hashCode`, and asserted non-negative like the other thresholds. The hold-back lasts until each finger has moved 2 px, which is under one frame at normal finger speeds. Its documentation states that it is independent of `enableMultiFingerGestureRace` and that pitch is decided before the race.

### 4. Ctrl-drag follows GL JS's mouse handlers

While pitch gestures are enabled and the trigger key is held, `_onPointerMove` computes, from the previous and current cursor positions and the viewport center `c`:

- pitch change: `(current.y − previous.y) · −0.5` (GL JS `pitchSpeed`), through `pitchRaw`;
- rotation change, GL JS's default `circular` movement: if `|c.y − previous.y| > 100`, the angle at `c` from `(previous.x, current.y)` to `current`, which is the turn caused by the horizontal movement alone; otherwise `(current.x − previous.x) · 0.8` (GL JS `rotateSpeed`), negated when the cursor is above `c`. The sign is converted from GL JS's bearing to `flutter_map`'s rotation so that the map turns with the cursor, and applied through `rotateRaw`, which keeps the center.

`_onPointerDown` emits rotate start and pitch start; `_onPointerUp` and `_onPointerCancel` emit rotate end and pitch end and skip set north on click. `CursorRotationBehaviour` isn't read in this mode. While pitch gestures are disabled, the existing code runs unchanged, including the missing rotate end event, which is existing upstream behavior this change doesn't alter.

Alternative: keep rotation to the cursor's angle and add pitch from vertical movement. Rejected in the concept exploration: vertical movement changes the cursor's angle, so the map would rotate while pitching.

### 5. Flag, events and controller

- `InteractiveFlag.pitch = 1 << 8`, added to `all` and to `_multiFingerFlags`, with `hasPitch`. Removing the flag during a pitch gesture ends it with `MapEventSource.interactiveFlagsChanged`, as `updateGestures` does for rotate.
- `MapEventPitchStart` and `MapEventPitchEnd`, plain `MapEvent` subclasses like `MapEventRotateStart` and `MapEventRotateEnd`. `MapControllerImpl` gains `pitchStarted` and `pitchEnded`, like `rotateStarted` and `rotateEnded`.
- Two-finger pitch events use `multiFingerGestureStart`, `onMultiFinger` and `multiFingerEnd`; Ctrl-drag events use `cursorKeyboardRotation`. No `MapEventSource` value is added (concept section 11).

### 6. Verification approach

- Widget tests in the fork with two `TestGesture` pointers, as `test/gestures/pitched_gestures_test.dart` does, for each spec scenario: recognition, ruling out, clamping, threshold, no fling, lock-out, the pinch catch-up compared with the same pinch at maximum pitch 0, and events in order.
- Widget tests for Ctrl-drag, with the Control key held through `simulateKeyDownEvent` (the fork has no Ctrl-drag widget tests yet): pitch from vertical movement, rotation far from and near the center, and events. A test with pitch gestures disabled records the existing Ctrl-drag rotation before the change.
- The existing gesture tests run unchanged at maximum pitch 0.
- The example app's Pitch page needs no change; its `maxPitch` enables the gestures. On devices: two-finger pitch on the iPhone and the Pixel, and Ctrl-drag on the Mac and in Chrome, checked by hand.

## Risks / Trade-offs

- [The 2 px threshold may misread a two-finger pan that starts vertically as a pitch] → This is MapLibre's behavior on every platform. The threshold is an option, and the device check covers whether 2 px feels right; the default can change without changing the spec.
- [Hold-back delays zoom, rotate and move by up to one frame, or up to 100 ms when one finger stays still] → Only while pitch gestures are enabled; the first update after the decision applies the whole gesture, so the ground ends up under the fingers.
- [The value of `InteractiveFlag.all` changes] → Code that combines flags with `|`, `&` and `~` is unaffected; the pitch flag has no effect while `maxPitch` is 0.
- [Ctrl-drag changes how rotation feels when an application raises `maxPitch`] → Documented on `maxPitch` and `CursorKeyboardRotationOptions`; applications that keep `maxPitch` at 0 are unchanged.
- [GL JS's handler code changes upstream] → The rates and rules are copied into this design and the fork's code; they don't depend on GL JS's later versions.

## Migration Plan

- Implement on the fork's local branch `map-pitch`, after `04c3e14`; no push without explicit approval.
- mapigrade needs no change: its path override uses the fork's working tree.
- Rollback: revert the commit on the fork's branch.
