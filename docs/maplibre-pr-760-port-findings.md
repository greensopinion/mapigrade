# Findings: porting mapigrade to maplibre-native-ffi PR #760

This document records what we learned by porting mapigrade to the C API of [maplibre-native-ffi PR #760](https://github.com/maplibre/maplibre-native-ffi/pull/760) ("Move execution into the native core and generate language bindings") on the branch `experiment-maplibre-pr-760-port`. The plan is the OpenSpec change `experiment-maplibre-pr-760-port` (proposal, design and tasks in `openspec/changes/experiment-maplibre-pr-760-port/`); the questions Q1 to Q7 and the decisions D166 to D172 are those of its design. The background is [discussion #877](https://github.com/maplibre/maplibre-native-ffi/discussions/877).

Each finding names the #760 commit it was made with, and states whether it comes from #760 or from the port's shortcuts (D172).

## #760 commit

| Date | Commit | Reason |
|---|---|---|
| 2026-10-21 | `3b56ef916` ("Merge origin/main into binding-codegen") | Initial pin (D166). |

## Baseline

The branch's first commit adds camera-to-frame latency to `map_texture_stats` (D171) and still uses the released FFI (0.202610.1, commit `a2f332ec`). The port is measured against that commit.

Not yet measured.

## Q1. Display slots on Apple platforms

Open.

## Q2. Latency from camera to frame

Open.

## Q3. Synchronous execution

Open.

## Q4. Glyph load failures

Open. #760's log records (`logging.h`) carry no map identity, and the core worker emits them. #760 has no glyph failure event; candidates to check are `MLN_RUNTIME_EVENT_MAP_TILE_ACTION` and a resource transform.

## Q5. Android hook before the swap

Open. On `main`, Android switches the session's surface only when the window is replaced or the map parks on a pbuffer, not per frame. In discussion #877 we wrote that Android switches the OpenGL surface per frame; that was wrong.

## Q6. Lifecycle

Open.

## Q7. Other API

Open.

## Complexity

Lines of the native code on `main` (commit `d71c9bc`), in `packages/flutter_mapigrade`:

| Area | Files | Lines on `main` | Lines on the branch |
|---|---|---|---|
| Core | `src/core/*` | 2,677 | |
| Apple target | `darwin/.../MapTextureMetal.mm` | 459 | |
| Android target | `android/src/main/cpp/map_texture_android.cpp` | 772 | |
| Native tests | `test/native/*` | 2,371 | not built (D172) |

## What broke

Nothing yet.

## Feedback for #760

None yet. Issue drafts go here for review before anything is posted.
