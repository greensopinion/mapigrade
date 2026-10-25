## 1. Baseline

- [ ] 1.1 On the fork's branch `map-pitch` at `04c3e14`, add widget tests of Ctrl-drag rotation (offset behaviour, set north behaviour, set north on click) and of a two-finger vertical drag that pinch-moves the map, all at maximum pitch 0; verify they pass before any other change, and `flutter test` passes on the branch

## 2. Flag, options and events

- [ ] 2.1 Add `InteractiveFlag.pitch` to `all` and to the multi-finger flags, with `hasPitch`; verify a test of the flag value, `all` and `hasMultiFinger`, and that the compile-only exhaustive `switch` test from change 1 passes unchanged
- [ ] 2.2 Add `InteractionOptions.pitchThreshold` (default 2.0, non-negative assert, equality and hash code); verify tests of the default and equality
- [ ] 2.3 Add `MapEventPitchStart`, `MapEventPitchEnd`, and `pitchStarted` and `pitchEnded` in `MapControllerImpl`; verify a test that each emits its event with the given source

## 3. Two-finger pitch gesture

- [ ] 3.1 Track per-pointer start and current positions in the viewer's `Listener`, and record each pointer's position at scale start; verify that the baseline tests from 1.1 and the existing gesture tests pass unchanged
- [ ] 3.2 Add the pitch decision (design decision 2) with hold-back while undecided and lock-out once recognized, and set the pitch from the focal point's vertical movement; verify widget tests for the spec scenarios Pitch up, Pitch limited to the maximum, Pitch down to 0, Fingers one above the other, Three fingers and Pitch threshold
- [ ] 3.3 Verify widget tests for the scenarios Pinch while pitch is enabled (zoom and focal coordinate match the same pinch at maximum pitch 0, with race off and on), Spread after a recognized pitch gesture, and Gesture ends before a decision
- [ ] 3.4 Emit pitch start, pitch and pitch end events and skip the fling after a pitch gesture, and end a pitch gesture when the pitch flag is removed; verify widget tests for Two-finger pitch events, No fling after a pitch gesture, and the flag removal

## 4. Ctrl-drag pitch

- [ ] 4.1 Implement Ctrl-drag pitch and rotation while pitch gestures are enabled (design decision 4), with rotate and pitch start and end events; verify widget tests for the scenarios Ctrl-drag up, Ctrl-drag sideways below the center, Ctrl-drag near the center, Set north on click while pitch is enabled and Ctrl-drag pitch events, and that the baseline Ctrl-drag tests from 1.1 pass unchanged

## 5. Documentation and integration

- [ ] 5.1 Document `InteractiveFlag.pitch`, `pitchThreshold`, the pitch decision before the race in `enableMultiFingerGestureRace`, Ctrl-drag pitch on `CursorKeyboardRotationOptions` and `maxPitch`, and the new events; verify `dart doc` reports no new warnings
- [ ] 5.2 Run `flutter analyze` and `flutter test` on the branch; verify both pass with no existing test changed, and that the pitch-0 geometry assertions and local golden images from change 1 pass
- [ ] 5.3 Ask the user to check by hand, on the example app's Pitch page: two-finger pitch, pinch, rotate and two-finger pan on the iPhone and the Pixel, and Ctrl-drag on the Mac and in Chrome; record the result and any change to the threshold default in design.md
