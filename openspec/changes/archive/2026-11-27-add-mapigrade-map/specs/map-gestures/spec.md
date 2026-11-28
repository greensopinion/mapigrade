## Purpose

Defines how `MapigradeMap` turns touch, trackpad, mouse and keyboard input into camera movement through the FFI's gesture recognizer, how it shares input with other widgets, and the tap callbacks and haptic feedback it provides.

## ADDED Requirements

### Requirement: Gestures through the gesture arena
`MapigradeMap` SHALL take part in Flutter's gesture arena for the pointers that hit it, and SHALL move the camera only with the pointers whose gesture it wins. A child of the map, such as a marker with its own gesture recognizer, SHALL win the gestures that its recognizers accept. When the map is inside a scrollable, a one-pointer drag SHALL go to whichever recognizer passes its slop first, and a gesture with two pointers on the map SHALL go to the map. When the map wins a pointer, the camera SHALL follow the pointer from where it went down, including the movement before the map won.

#### Scenario: Tap on a marker
- **WHEN** a marker with a `GestureDetector` that has `onTap` is drawn over the map, and the user taps the marker
- **THEN** the marker's `onTap` is called, and the map's `onTap` isn't

#### Scenario: Map in a vertical list
- **WHEN** the map is inside a vertical `ListView` and the user drags vertically with one finger
- **THEN** either the list scrolls or the map pans, not both

#### Scenario: Pinch in a list
- **WHEN** the map is inside a vertical `ListView` and the user pinches on the map
- **THEN** the map zooms and the list doesn't scroll

#### Scenario: Ground stays under the finger
- **WHEN** the user drags the map with one finger on a flat map at rest
- **THEN** after the drag the coordinate that was under the finger when it went down is under the finger, within 1 logical pixel

### Requirement: Touch gestures
With every part of the gesture options on, touch input SHALL pan the map with one or two fingers, zoom with a pinch, turn the bearing with a twist, change the pitch with two fingers moving up or down together, zoom in by one level with a double tap, and zoom out by one level with a two-finger tap. A release while panning, zooming, turning or tilting fast enough SHALL glide on. The glide SHALL decay as the platform's scroll views do: on iOS and macOS by friction with a half-life of 346 ms, and on Android by the FFI's curve model with Android's fling defaults. A bearing within 7 degrees of north when a gesture ends SHALL snap to north.

#### Scenario: Pitch with two fingers
- **WHEN** the user moves two fingers up together on the map
- **THEN** the camera's pitch increases, up to the maximum pitch of the camera limits

#### Scenario: Fling
- **WHEN** the user flings the map
- **THEN** the map keeps panning after the finger lifts and slows down until it stops

#### Scenario: Snap to north
- **WHEN** the user twists the map to a bearing of 5 degrees and lifts the fingers
- **THEN** the bearing eases to 0

### Requirement: Gesture options
`MapigradeMap` SHALL take `MapigradeGestures`, which turns each of these on or off: pan, zoom, rotate, pitch, glides, double-tap zoom, two-finger-tap zoom, the snap to north and the keyboard. All are on by default. A part that is off SHALL NOT move the camera, and its input SHALL go to other recognizers. When the application rebuilds the widget with different options, the new options SHALL apply from the next input.

#### Scenario: Rotation off
- **WHEN** rotate is off and the user twists two fingers on the map
- **THEN** the bearing doesn't change

#### Scenario: Double-tap zoom off
- **WHEN** double-tap zoom is off and the user double-taps the map
- **THEN** the zoom doesn't change, and `onTap` is called for each tap

### Requirement: Desktop input
On macOS, a two-finger scroll on a trackpad SHALL pan the map, and a trackpad pinch SHALL zoom and turn it, gliding on when the fingers lift. A mouse wheel SHALL zoom by a third of a level per wheel detent around the pointer, and SHALL NOT also scroll an enclosing scrollable. A drag with the right mouse button, or with the left button while Ctrl is held, SHALL turn the bearing with sideways movement and change the pitch with up and down movement. A drag while Shift is held SHALL draw a rectangle that the map shows, and the map SHALL zoom to the rectangle when the button is released. A double click while Shift is held SHALL zoom out by one level. While the map has keyboard focus, the arrow keys SHALL pan by 100 logical pixels, `+` and `-` SHALL zoom by one level, and Shift with the left and right arrows SHALL turn the bearing by 15 degrees and with the up and down arrows change the pitch by 10 degrees. A click on the map SHALL give it keyboard focus.

#### Scenario: Trackpad scroll
- **WHEN** the user scrolls with two fingers on a Mac trackpad over the map
- **THEN** the map pans and the zoom doesn't change

#### Scenario: Mouse wheel
- **WHEN** the user turns a mouse wheel by three detents toward zooming in, with the pointer over a coordinate
- **THEN** the zoom increases by one level, and the coordinate stays under the pointer

#### Scenario: Box zoom
- **WHEN** the user drags a rectangle with Shift held and releases the button
- **THEN** the map shows the rectangle while dragging, and afterwards the camera shows the rectangle's area

#### Scenario: Keyboard
- **WHEN** the user clicks the map and presses the right arrow key
- **THEN** the map pans by 100 logical pixels

### Requirement: Taps
`MapigradeMap` SHALL call `onTap` for a tap, `onLongPress` for a press held still for 500 ms, and `onSecondaryTap` for a click of the right mouse button without a drag, each with a `MapigradeTap` that has the logical position relative to the widget's top-left corner and the coordinate at that position on the displayed frame's ground. The FFI's gesture recognizer SHALL decide what is a tap, so that a press that pans the map is not a tap. When double-tap zoom is on, `onTap` SHALL be called only after the time for a second tap has passed without one, and a double tap SHALL NOT call `onTap`. When double-tap zoom is off, `onTap` SHALL be called when the tap lifts.

#### Scenario: Tap gives a coordinate
- **WHEN** the camera is at rest with pitch 45 and the user taps the map
- **THEN** `onTap` receives the tap's position and the coordinate that the displayed frame draws there, within 1 logical pixel

#### Scenario: Double tap doesn't tap
- **WHEN** double-tap zoom is on and the user double-taps the map
- **THEN** the map zooms in and `onTap` isn't called

#### Scenario: Pan isn't a tap
- **WHEN** the user presses, drags the map and lifts
- **THEN** `onTap` isn't called

### Requirement: Haptic feedback
When a gesture, its glide or its snap moves the bearing to or across north, `MapigradeMap` SHALL play the platform's selection haptic feedback on iOS and Android. `MapigradeMap` SHALL take a setting that turns haptic feedback off.

#### Scenario: Snap to north
- **WHEN** the user twists the map across north on an iPhone
- **THEN** the phone plays the selection feedback once
