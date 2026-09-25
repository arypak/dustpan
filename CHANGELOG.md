# Changelog

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
