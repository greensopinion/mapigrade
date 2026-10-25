## 1. Dependency

- [x] 1.1 Add `dependency_overrides: flutter_map: path: ../flutter_map` to the workspace root `pubspec.yaml`; verify `flutter pub get` resolves `flutter_map` to the fork, and that `flutter analyze` and the package's existing tests pass unchanged with it

## 2. Native core and C API

- [x] 2.1 Add `pitch` to `Camera`, to `map_texture_set_camera` and to `map_texture_event`, set `MLN_CAMERA_OPTION_PITCH`, and report each frame's pitch; verify the native tests pass and a new native test that a camera set with pitch 45 is reported with pitch 45
- [x] 2.2 Add perspective to `ScreenPosition` in `projection.h` (design decision 4); verify native tests that compare it with `mln_map_projection_pixel_for_lat_lng` within 0.01 px at pitch 0, 30 and 60 with rotations 0 and 30

## 3. Dart

- [x] 3.1 Add `pitch` to `MapCamera` (including `toString`; it has no equality) and the bindings; verify that the test harness's "camera change shows up in the frame camera" test, which goes through the FFI, reports a pitch of 45 set with the camera, and that the package's tests pass
- [x] 3.2 Carry the pitch in `viewCameraOf`, `flutterMapCameraOf` and `ViewCamera`; verify unit tests that a pitched `flutter_map` camera converts and converts back unchanged
- [x] 3.3 Implement `screenPosition` and `worldPosition` with the fork's camera (design decision 3); verify `camera_projection_test.dart` with pitched cases, round trips, and the antimeridian case
- [x] 3.4 Add the pitch rate to camera prediction, limited to 0 to 60 degrees; verify `camera_prediction_test.dart` cases for a constant pitch change and for the limit

## 4. Verification on devices

- [x] 4.1 Add pitched cases to `static_alignment_test.dart` (design decision 7); verify they meet the 1 logical pixel limit on the Mac, the iPhone and the Pixel, run in parallel
- [x] 4.2 Add the pitched case to `feature_query_test.dart`; verify it passes on the Mac
- [x] 4.3 Run the alignment benchmark with children at pitch 45 during a pan at 1,000 logical px/s on the Mac; verify the alignment error is at most 1 logical pixel in each Flutter frame, and record the result in `docs/benchmarks.md`
- [x] 4.4 Run the package tests, the test harness's integration tests and `flutter analyze` across the workspace; verify all pass

## 5. Demo and documentation

- [x] 5.1 Add the 3D view showcase and its gallery entry; verify on the Mac, the iPhone and the Pixel, in parallel, that it opens at pitch 45 with 3D buildings, that the slider tilts the map and the overlays from 0 to 60, and that the route and markers stay on the map while panning, zooming and rotating
- [x] 5.2 Pitch the flyover while it follows a route (design decision 9); verify the demo's tests, including that the camera is pitched only while following and that the rider stays at its place on screen, and on the Mac that the flyover tilts into each route and back
- [x] 5.3 Update the package README and `docs/limitations.md`, which state that there is no pitch, and the concept doc's change 2 status; verify the statements match the behaviour
