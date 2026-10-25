## Why

A pitched `flutter_map` map can be pitched only from code: change 1 (`add-flutter-map-pitch-camera`) added the pitched camera and kept every existing gesture correct when pitched, but added no way for the user to change the pitch. Users of MapLibre's maps expect to pitch with a two-finger vertical drag on a touch screen and with Ctrl-drag on a desktop. This is change 3 in `docs/map-pitch-concept.md`.

## What Changes

This change is implemented in our `flutter_map` fork (greensopinion/flutter_map), on the branch `map-pitch`. It changes nothing in mapigrade.

- A new interactive flag for pitch, part of the set of all flags. It has no effect while the maximum pitch is 0.
- A two-finger vertical drag changes the pitch, by MapLibre's rule: the line between the fingers is within 45° of horizontal, and both fingers move vertically in the same direction. Moving up increases the pitch, by 0.5° per px, and the pitch pivots on the viewport center.
- While pitch is enabled, a two-finger gesture holds back zoom, rotate and move until the pitch gesture is recognized or ruled out. A recognized pitch gesture locks them out for the rest of the gesture.
- A new interaction option for the pitch gesture's threshold, alongside the existing rotation, pinch-zoom and pinch-move thresholds.
- While pitch is enabled, Ctrl-drag rotates the map with horizontal movement and pitches it with vertical movement, as MapLibre GL JS does. The cursor rotation behaviour option and set-north-on-click have no effect in this mode.
- Pitch gesture events: new pitch start and pitch end events, and the existing pitch event, with the existing multi-finger and Ctrl-drag event sources. No event source value is added.
- With the maximum pitch at its default of 0, gesture behavior is unchanged.
- Not in this change: keyboard pitch keys, a trackpad pitch gesture (Flutter receives no finger positions from a trackpad), and the limit on ground movement near the horizon (change 6).

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `flutter-map-pitch`: adds the pitch interaction flag, the two-finger pitch gesture and its effect on other two-finger gestures, Ctrl-drag pitch, and pitch gesture events. The requirement for unchanged behavior at pitch 0 changes so that gestures are unchanged while the maximum pitch is 0, because a map at pitch 0 with a higher maximum pitch now has a pitch gesture.

## Impact

- The fork: `InteractiveFlag`, `InteractionOptions`, the map interactive viewer's pointer tracking, two-finger gesture handling and Ctrl-drag handling, `MapControllerImpl`, map events, the example app's Pitch page, and documentation.
- Public API additions in the fork, all keeping existing behavior while the maximum pitch is 0: `InteractiveFlag.pitch`, a pitch threshold in `InteractionOptions`, and pitch start and end events. The value of `InteractiveFlag.all` gains the new flag.
- mapigrade: no change. mapigrade resolves `flutter_map` to the fork through a path override, so the demo's pitched showcases get the gestures without a change.
