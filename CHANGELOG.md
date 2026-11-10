# Changelog

## Unreleased

Stricter about what counts as safe.

- Poetry keeps its virtual environments inside its cache folder. They are now a rule of their own,
  marked Review, and the Safe Poetry rule only covers downloads.
- Yarn's global cache (Yarn 2 and later) is marked Caution: Plug'n'Play projects run from it.
- A `build`, `target` or `Pods` folder isn't treated as build output when its top level holds a
  project of its own, sources or scripts.
- `dustpan clean app-caches` on its own no longer picks up folders that other rules own, such as
  test browsers or the pnpm cache.
- The snapshot tour that records the README animation can't move anything.

## 0.1.0 (2026-09-25)

The first release.

- A Mac app and the `dustpan` command-line tool on one shared engine.
- 71 rules for app caches, Xcode and simulators, package managers, project build folders, SDKs,
  VMs and containers, AI models, large apps, and downloads and backups. Each has a safety level
  and says what it is and what happens once it's gone.
- Nothing is deleted. Dustpan only moves things to the Trash, behind a guard that refuses the
  system, personal folders, synced folders such as iCloud Drive, credential folders and anything
  holding a Git repository.
- Anything marked Review stays hidden until you confirm. The command line asks about each item on
  its own and never moves one in bulk, even with `--yes`.
- Warns when a cache you picked belongs to an app that's still open.
- English and Turkish, and light, dark or system appearance.
