## 1. Constraints

- [x] 1.1 In `ContainCamera` and `ContainCameraLatitude`, replace `camera.size` with `MapCamera.calculateRotatedSize(camera.rotation, camera.nonRotatedSize)`; verify tests for the spec scenarios Pitch change inside the bounds and Constrained center independent of pitch, and that the existing constraint tests pass unchanged

## 2. Fits

- [x] 2.1 Add the pitched fit of a list of points (design decision 1) and use it in `FitBounds` and `FitCoordinates` when the pitch isn't 0; verify tests for the spec scenarios Fit bounds (pitch 60, rotation 30) and Fit coordinates with padding (pitch 45), including that the result is tight, and with a maximum zoom and `forceIntegerZoomLevel` that every point stays inside the padded viewport
- [x] 2.2 Add the pitched `FitInsideBounds` (design decision 2); verify a test for the spec scenario Fit inside bounds (pitch 60, rotation 30), including that one ground corner is within 1 projected px of the bounds
- [x] 2.3 Verify that the existing fit tests, including `zero_size_camera_fit_test.dart`, pass unchanged at pitch 0, and add a test of a pitched fit to a single coordinate that centers it without changing the zoom

## 3. Documentation and integration

- [x] 3.1 Update the `MapOptions.maxPitch` documentation and document the pitched behavior on `CameraConstraint.contain` and `containLatitude` (design decision 4); verify `dart doc` reports no new warnings
- [x] 3.2 Run `flutter analyze` and `flutter test` on the fork's branch; verify both pass with no existing test changed
