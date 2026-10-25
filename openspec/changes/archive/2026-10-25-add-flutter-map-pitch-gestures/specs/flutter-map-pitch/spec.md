## MODIFIED Requirements

### Requirement: Unchanged behavior at pitch 0

At pitch 0, the camera's projections, visible bounds and the positions at which layers draw SHALL be the same as without pitch support. While the maximum pitch is 0, gesture behavior SHALL be the same as without pitch support.

#### Scenario: Existing tests

- **WHEN** the pitch is 0
- **THEN** the fork's existing tests pass without changes

#### Scenario: Gestures at the default maximum pitch

- **WHEN** the maximum pitch is 0 and the user drags vertically with two fingers, pinches, twists two fingers, or drags with Ctrl held
- **THEN** the map moves, zooms and rotates as in the release the fork starts from, and the pitch stays 0

## ADDED Requirements

### Requirement: Pitch gestures enabled

The interactive flags SHALL include a flag for pitch gestures, and the flag SHALL be part of the set of all interactive flags. The two-finger pitch gesture and Ctrl-drag pitch SHALL be enabled only while the pitch flag is set and the maximum pitch is above 0. While they are not enabled, two-finger gestures and Ctrl-drag SHALL behave as in the release the fork starts from.

#### Scenario: Pitch flag removed

- **WHEN** the maximum pitch is 60, the interactive flags are all flags except the pitch flag, and the user drags two fingers upward side by side
- **THEN** the map moves with the fingers and the pitch doesn't change

#### Scenario: All flags at the default maximum pitch

- **WHEN** the interactive flags are all flags, the maximum pitch is 0, and the user drags two fingers upward side by side
- **THEN** the map moves with the fingers and the pitch stays 0

### Requirement: Two-finger pitch gesture

While pitch gestures are enabled, the map SHALL recognize a pitch gesture when exactly two fingers touch the map, the line between them is within 45° of horizontal when the gesture starts, and both fingers move vertically in the same direction, each more vertically than horizontally, by at least the pitch threshold. The map SHALL rule the pitch gesture out when the line between the fingers is more than 45° from horizontal when the gesture starts, when a finger moves more horizontally than vertically, when the fingers move vertically in opposite directions, or when one finger moves by the pitch threshold and the other finger doesn't move within 100 ms. Once recognized, the pitch SHALL be the pitch at the start of the gesture minus 0.5° for each px that the midpoint between the fingers has moved down since the start, limited to the range from 0 to the maximum pitch. The pitch gesture SHALL keep the center coordinate at the center of the viewport and SHALL NOT change the zoom or the rotation. When the user lifts the fingers after a pitch gesture, the map SHALL NOT fling. The application SHALL be able to set the pitch threshold in px in the interaction options.

#### Scenario: Pitch up

- **WHEN** the pitch is 10, the maximum pitch is 60, and the user places two fingers side by side and moves both 40 px up
- **THEN** the pitch is 30, the zoom and rotation are unchanged, and the center coordinate is at the center of the viewport

#### Scenario: Pitch limited to the maximum

- **WHEN** the pitch is 40, the maximum pitch is 45, and the user moves two fingers side by side 100 px up
- **THEN** the pitch is 45

#### Scenario: Pitch down to 0

- **WHEN** the pitch is 20 and the user moves two fingers side by side 100 px down
- **THEN** the pitch is 0

#### Scenario: Fingers one above the other

- **WHEN** the user places two fingers so that the line between them is 60° from horizontal and moves both 40 px up
- **THEN** the pitch doesn't change and the map moves with the fingers

#### Scenario: Three fingers

- **WHEN** the user moves three fingers side by side 40 px up
- **THEN** the pitch doesn't change

#### Scenario: Pitch threshold

- **WHEN** the pitch threshold is 20 and the user moves two fingers side by side 10 px up and lifts them
- **THEN** the pitch, center, zoom and rotation don't change

#### Scenario: No fling after a pitch gesture

- **WHEN** the user pitches the map with two fingers and lifts them while they still move
- **THEN** the center doesn't change after the fingers are lifted

### Requirement: Other two-finger gestures while pitch is enabled

While pitch gestures are enabled and a two-finger gesture can still become a pitch gesture, the map SHALL NOT zoom, rotate or move for that gesture. When the pitch gesture is ruled out, the map SHALL zoom, rotate and move for the whole gesture so far, as it would have without pitch gestures, and continue as without pitch gestures. When the pitch gesture is recognized, the map SHALL NOT zoom, rotate or move for the rest of the gesture.

#### Scenario: Pinch while pitch is enabled

- **WHEN** the maximum pitch is 60 and the user pinches two fingers apart
- **THEN** after the pinch, the zoom and the coordinate under the focal point are the same as for the same pinch with the maximum pitch at 0

#### Scenario: Spread after a recognized pitch gesture

- **WHEN** the user pitches the map with two fingers and then spreads them apart without lifting them
- **THEN** the zoom, center and rotation don't change

#### Scenario: Gesture ends before a decision

- **WHEN** the user places two fingers side by side and lifts them without moving them
- **THEN** the pitch, center, zoom and rotation don't change

### Requirement: Ctrl-drag pitch

While pitch gestures are enabled, a drag with the cursor/keyboard rotation trigger key held SHALL pitch and rotate the map as MapLibre GL JS does by default. Vertical movement SHALL change the pitch by 0.5° per px, increasing it when the cursor moves up, and SHALL NOT rotate the map. Horizontal movement SHALL rotate the map about the viewport center and SHALL NOT change the pitch: when the cursor is more than 100 px above or below the viewport center, by the angle about the viewport center through which the horizontal movement turns the cursor; otherwise by 0.8° per px. Either way the map SHALL turn in the direction that the cursor moves around the viewport center. The pitch and the rotation SHALL keep the center coordinate at the center of the viewport and SHALL NOT change the zoom. The cursor rotation behaviour option and the option to set north on click SHALL have no effect while pitch gestures are enabled.

#### Scenario: Ctrl-drag up

- **WHEN** the pitch is 10, the maximum pitch is 60, and the user drags the cursor 40 px straight up with Ctrl held
- **THEN** the pitch is 30 and the rotation is unchanged

#### Scenario: Ctrl-drag sideways below the center

- **WHEN** the maximum pitch is 60 and the user drags the cursor horizontally with Ctrl held, 200 px below the viewport center
- **THEN** the map rotates by the angle that the cursor's movement subtends at the viewport center, in the direction that the cursor moves around the center, and the pitch is unchanged

#### Scenario: Ctrl-drag near the center

- **WHEN** the maximum pitch is 60 and the user drags the cursor 10 px to the right with Ctrl held, 50 px below the viewport center
- **THEN** the map rotates by 8° in the direction that the cursor moves around the center

#### Scenario: Set north on click while pitch is enabled

- **WHEN** the maximum pitch is 60, set north on click is enabled, and the user clicks without dragging with Ctrl held
- **THEN** the rotation doesn't change

### Requirement: Pitch gesture events

A pitch gesture SHALL emit a pitch start event when it starts, a pitch event for each change of the pitch, and a pitch end event when it ends. A two-finger pitch gesture starts when it is recognized and ends when the fingers are lifted, and its events SHALL have the existing event sources of multi-finger gestures: the multi-finger start source for the start event, the multi-finger update source for pitch events, and the multi-finger end source for the end event. A two-finger pitch gesture SHALL emit no move start, move, or move end events. A Ctrl-drag while pitch gestures are enabled starts when the button is pressed and ends when it is released; it SHALL emit a rotate start event and a pitch start event when it starts and a rotate end event and a pitch end event when it ends, and all of its events SHALL have the existing cursor/keyboard rotation source.

#### Scenario: Two-finger pitch events

- **WHEN** the user pitches the map with two fingers from 10 to 30 and lifts them
- **THEN** one pitch start event, one or more pitch events whose last has pitch 30, and one pitch end event are emitted, in that order, with the multi-finger sources

#### Scenario: Ctrl-drag pitch events

- **WHEN** the maximum pitch is 60 and the user presses the button with Ctrl held, drags the cursor up, and releases the button
- **THEN** a rotate start and a pitch start event, one or more pitch events, and a rotate end and a pitch end event are emitted, in that order, all with the cursor/keyboard rotation source
