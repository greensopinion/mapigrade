# Map pitch: upstream PR plan

This plan covers opening one PR in [fleaflet/flutter_map](https://github.com/fleaflet/flutter_map) for each commit on the fork's branch `map-pitch` (`~/git/flutter_map`), stacked in commit order. All seven PRs were opened on 2026-10-25 (see [Branches](#branches)). Every step that pushes, opens or edits something on GitHub needs explicit approval first.

## State before the PRs were opened (2026-10-25)

- `map-pitch` has five commits on top of `upstream/master` (`34457c1`), and `upstream/master` hasn't moved since.
- `map-pitch` isn't pushed to the fork (`origin`, greensopinion/flutter_map).
- The working tree has uncommitted changes in `tile_cover.dart`, `tile_cover_calculator.dart` and `tile_layer.dart` (+101/−42): `_TileSet.expand` caches its expansions, and the separating axis test moves into a `_Ground` class that precomputes the polygon's projections. They are in none of the five commits.
- greensopinion has only `pull` permission on fleaflet/flutter_map, so it can't push branches there.

## Decisions needed before pushing

1. **How to stack.** Decided on 2026-10-25: JaffaKetchup created `pitch-support` (at `master`) as the target for the pitch work, changed #2281's base to it, and gave greensopinion write access to fleaflet/flutter_map.
   - Every PR has its head branch in fleaflet/flutter_map. PR 1 targets `pitch-support`, and every later PR targets the previous PR's branch, so each PR shows only its own commit.
   - The PRs form a GitHub native stack, #2284, created with `gh stack link --remote upstream --base pitch-support <PRs, bottom to top>`. Add each new PR with `gh stack link --remote upstream 2284 <PR>`. Native stacks can't include a PR from a fork, so #2281 (PR 1 from `greensopinion:pitch-1-camera`) was closed and replaced by #2283.
   - When a PR is merged into `pitch-support`, change the next PR's base to `pitch-support`. If the merge was a squash merge, rebase the next PR onto `pitch-support` too, then delete the merged PR's fleaflet branch.
2. **Uncommitted tile cover changes.** Decided: the user committed them as `76d0633` (compute the tile cover once per camera), and added `03cfd00` (remove TileRangeCalculator). Each is its own PR, 6 and 7, stacked on PR 5.
3. **Example app platform files.** `04c3e14` changes `example/ios` (`AppFrameworkInfo.plist`, `project.pbxproj`, `Runner.xcscheme`, `AppDelegate.swift`, `Info.plist`) and `example/macos/Flutter/GeneratedPluginRegistrant.swift`; `66b72e5` changes `example/macos` (`Podfile`, `Podfile.lock`, `project.pbxproj`, `Runner.xcscheme`, `AppDelegate.swift`). These are migrations that the Flutter tool made, and pitch doesn't need them. Decided: keep both commits as they are.
4. **PR titles.** Decided: follow the project's convention. CONTRIBUTING.md asks for Conventional Commits PR titles, and recent fleaflet PRs use them, so the titles below add a type prefix to the commit subject line.
5. **AI disclosure.** Decided: CONTRIBUTING.md asks contributors to make it clear that they used AI, so every description below ends with a disclosure paragraph. The commit messages stay as they are.
6. **Discussion issue first.** CONTRIBUTING.md asks for a discussion in the issue tracker before a PR that adds a major change. Pitch is a major change. Settled: the user discussed the pitch PRs with JaffaKetchup on Discord, and no issue was opened.
7. **`e33cd10` as an independent PR.** The aborted-load fix doesn't depend on pitch. It could be a separate PR on `master`, which maintainers can merge without reviewing pitch. This plan keeps it in the stack, as requested.

## Branches

Each branch is in fleaflet/flutter_map. Every commit after `219a744` is the `map-pitch` commit rebased onto the fix, with the same patch.

| PR | Branch | Commit |
|----|--------|--------|
| 1 | `pitch-1-camera` | `04c3e14`, then `219a744` (compile on Flutter 3.27), pushed to fleaflet; opened as [#2283](https://github.com/fleaflet/flutter_map/pull/2283) into `pitch-support` on 2026-10-25, replacing [#2281](https://github.com/fleaflet/flutter_map/pull/2281) |
| 2 | `pitch-2-gestures` | `bc99c73` (`66b72e5` rebased onto `219a744`), pushed to fleaflet; opened as [#2282](https://github.com/fleaflet/flutter_map/pull/2282) into `pitch-1-camera` on 2026-10-25 |
| 3 | `pitch-3-fit-and-constraints` | `52ce1e4` (`a581ef2` rebased onto `bc99c73`), pushed to fleaflet; opened as [#2285](https://github.com/fleaflet/flutter_map/pull/2285) into `pitch-2-gestures` on 2026-10-25, added to stack #2284 |
| 4 | `pitch-4-aborted-tile-loads` | `84b22ed` (`e33cd10` rebased onto `52ce1e4`), pushed to fleaflet; opened as [#2286](https://github.com/fleaflet/flutter_map/pull/2286) into `pitch-3-fit-and-constraints` on 2026-10-25, added to stack #2284 |
| 5 | `pitch-5-tile-level-of-detail` | `fe8e4f4` (`979748d` rebased onto `84b22ed`); opened as [#2287](https://github.com/fleaflet/flutter_map/pull/2287) into `pitch-4-aborted-tile-loads` on 2026-10-25, added to stack #2284 |
| 6 | `pitch-6-tile-cover-once` | `72068fe` (`76d0633` rebased onto `fe8e4f4`); opened as [#2288](https://github.com/fleaflet/flutter_map/pull/2288) into `pitch-5-tile-level-of-detail` on 2026-10-25, added to stack #2284. Title `perf: compute the tile cover once per camera` |
| 7 | `pitch-7-remove-tile-range-calculator` | `79a686f` (`03cfd00` rebased onto `72068fe`); opened as [#2289](https://github.com/fleaflet/flutter_map/pull/2289) into `pitch-6-tile-cover-once` on 2026-10-25, added to stack #2284. Title `refactor: remove TileRangeCalculator, which the tile cover replaced`; the commit has no body, so the description is the dependency note and the AI disclosure |

## PRs

The title is the commit subject line with a Conventional Commits prefix (decision 4). The description is the commit body. PRs 2 to 5 add a dependency note, and every PR ends with the AI disclosure (decision 5). No PR has an attribution line.

### PR 1

**Title:** `feat: add camera pitch`

**Description:**

```
MapOptions.maxPitch (default 0) allows pitch up to 60°. Ground layers
draw in perspective; markers and labels face the viewer. Adds
MapController.pitch and BillboardLayerTransformer.

I wrote this with Claude Code (Claude Opus 5.5). I directed the design,
reviewed the code, and tested it on a Mac, an iPhone 13, an iPhone 15 Pro
Max, a Pixel 4a (5G), and in Chrome.
```

### PR 2

**Title:** `feat: add pitch gestures`

**Description:**

```
A map whose maxPitch is above 0 can now be pitched by the user: with a
two-finger vertical drag on a touch screen, and with Ctrl-drag on a
desktop, which then rotates with horizontal movement and pitches with
vertical movement, as in MapLibre GL JS. While pitch gestures are
enabled, a two-finger gesture doesn't zoom, rotate or move the map until
the map has decided whether it is a pitch gesture, so that a pitch drag
doesn't also move the map. Maps that keep maxPitch at 0 behave as before.

Depends on #2283.

I wrote this with Claude Code (Claude Opus 5.5). I directed the design,
reviewed the code, and tested it on a Mac, an iPhone 13, an iPhone 15 Pro
Max, a Pixel 4a (5G), and in Chrome.
```

### PR 3

**Title:** `feat: fit and constrain the camera on a pitched map`

**Description:** The commit body refers to `04c3e14`; the description refers to PR 1 instead, because the commit hash isn't meaningful to reviewers and changes if decision 3 removes files.

```
Camera fits now account for pitch. The contain constraints, which
#<PR 1> broke on pitched maps, ignore pitch again, as in MapLibre GL JS,
so they no longer refuse pitch changes. At pitch 0, fits and constraints
behave as before.

Depends on #2282.

I wrote this with Claude Code (Claude Opus 5.5). I directed the design,
reviewed the code, and tested it on a Mac, an iPhone 13, an iPhone 15 Pro
Max, a Pixel 4a (5G), and in Chrome.
```

### PR 4

**Title:** `fix: remove aborted tile loads from the image cache when they are aborted`

**Description:**

```
An aborted load completes with a transparent image, and it was removed
from Flutter's image cache only after the abort error arrived. A tile
with the same URL created in between shared the load and showed the
transparent image until the tile was pruned.

Depends on #2285.

I wrote this with Claude Code (Claude Opus 5.5). I directed the design,
reviewed the code, and tested it on a Mac, an iPhone 13, an iPhone 15 Pro
Max, a Pixel 4a (5G), and in Chrome.
```

If decision 7 makes this PR independent, it has base `master`, contains only its own commit, and has no dependency note.

### PR 5

**Title:** `perf: load tiles at a zoom chosen from their size on screen`

**Description:**

```
On a pitched map, the tile layer loaded every tile in the bounding box
of the visible ground, all at one zoom. It now loads only the tiles that
cover the visible ground, and far tiles at a coarser zoom, so that they
are drawn at most √2 times their native size. No tile is finer than the
tile zoom of an unpitched map. The pan and keep buffers surround the
visible ground at each tile's zoom, tiles are drawn coarsest first, and
new tiles load in order of their distance on screen from the viewport
center.

At 60° on a Pixel 4a this makes 36% to 58% fewer tile requests, with as
much less decoded image memory, and the visible tiles load sooner. An
unrotated, unpitched map loads the same tiles as before.

Depends on #2286.

I wrote this with Claude Code (Claude Opus 5.5). I directed the design,
reviewed the code, and tested it on a Mac, an iPhone 13, an iPhone 15 Pro
Max, a Pixel 4a (5G), and in Chrome.
```

## Steps

PRs 1 and 2 are open. For each of PRs 3 to 5, in order:

1. Rebase the PR's commit onto the previous PR's branch, and run upstream CI's checks in a separate worktree: `dart format --output=none --set-exit-if-changed .`, `dart analyze --fatal-infos --fatal-warnings`, `flutter test` and `pana --exit-code-threshold 0 .` on current Flutter, and `flutter test` on Flutter 3.27.0, the oldest version that flutter_map supports. For PR 5, apply decision 2 first.
2. With approval, push the commit to fleaflet as the PR's branch and open the PR into the previous PR's branch: `gh pr create -R fleaflet/flutter_map --base <previous branch> --head <branch>`, with the title and description above and the previous PR's number in the dependency note. Then add it to stack #2284 with `gh stack link --remote upstream 2284 <PR>`.
