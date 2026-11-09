# Contributing to Grove

Thanks for your interest in Grove. Bug reports, ideas and pull requests are all welcome. For anything bigger than a small fix, open an issue first so we can agree on the approach before you put time in.

By taking part you agree to follow the [Code of Conduct](CODE_OF_CONDUCT.md). Report security problems privately, as described in [SECURITY.md](SECURITY.md).

## Requirements

- macOS 15 or later
- Xcode 26 or later (the packages use Swift tools 6.2)
- `git` on your `PATH`

No paid Apple Developer account is needed to build and run Grove locally.

## Building from source

```sh
git clone https://github.com/DouweBos/Grove.git
cd Grove

# GroveKit, the git engine
swift build && swift test

# The Grove app
cd app/Grove
xcodebuild -project Grove.xcodeproj -scheme Grove -derivedDataPath build \
  -destination 'platform=macOS,arch=arm64' build
open build/Build/Products/Debug/Grove.app
```

Or open `app/Grove/Grove.xcodeproj` in Xcode and run the `Grove` scheme. Xcode resolves the only remote dependency, [Sparkle](https://github.com/sparkle-project/Sparkle), on first build.

### Signing with your own Apple team

The project is set up with the maintainer's development team, which your machine can't sign for. Pick one of:

- **Xcode**: select the `Grove` target › Signing & Capabilities and choose your own team (a free Apple ID works). Do the same for `GroveTests` if you run tests from Xcode.
- **Command line, your team**: append `DEVELOPMENT_TEAM=<your team ID>` to the `xcodebuild` commands.
- **Command line, ad-hoc** (no Apple ID at all): append `CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=`.

Please don't commit a changed `DEVELOPMENT_TEAM` or bundle identifier.

Builds you make yourself still check the official update feed (houwert.dev) through Sparkle, and installing an update replaces your build with the official release. To opt out, set `SUEnableAutomaticChecks` to `false` in `app/Grove/Grove/Info.plist` locally.

## Running the tests

```sh
swift build && swift test          # GroveKit, from the repository root

cd app/Grove
xcodebuild -project Grove.xcodeproj -scheme Grove -derivedDataPath build \
  -destination 'platform=macOS,arch=arm64' test -only-testing:GroveTests
```

Both must stay green. When testing anything that writes to a repository, use a scratch repository under `/tmp`, never a real one.

Handy launch arguments for development: `-GroveOpenRepository <path>` opens a repository on launch, `-GroveAction <action>` (for example `navigateHistory`) runs an action once it's open, `-GroveAppearance dark|light` forces an appearance, and `-GroveSidebar hidden` collapses the sidebar.

## How the code is organised

See the [README](README.md#architecture) for the architecture and [`docs/CONVENTIONS.md`](docs/CONVENTIONS.md) for the patterns in detail. The short version:

- `Packages/GroveKit` is the git engine, models and headless view models. It's public API that other apps depend on, so: no SwiftUI or AppKit, all git and worktree access goes through `GitRunner`, and keep the public surface deliberate. Fix bugs found through Grove in GroveKit itself. GroveKit's `Package.swift` and the root one must keep the same targets and settings.
- `app/Grove` is the SwiftUI app. View models are `@Observable` and `@MainActor`; `RepositorySession` owns the per-repository view models, and you call `refreshAll()` after a git mutation.
- Design system: colors come from `Theme`, content sits in cards, SF Symbols only, and reusable components live in `DesignSystem/` with a `#Preview`.
- Keep files under 500 lines and views under 300.

## Commits and pull requests

- One commit per feature, fix or refactor, each with its own tests and docs, so it stands alone and can be reverted.
- Use [Conventional Commits](https://www.conventionalcommits.org/): `type(scope): subject`, with a short lowercase subject, for example `fix(history): order commits by commit date`.
- Comments explain *why*, in a line or two.
- User-facing changes add a changeset, `.changeset/<name>.md`:

  ```md
  ---
  "grove": patch
  ---

  Fix the history list jumping when a fetch finishes.
  ```

  Use `minor` for new features and `patch` for fixes. Never use `major`. A breaking change to GroveKit's API needs a `minor` bump and a note for other apps in the changeset. Changesets become the release notes.

Fill in the pull request template, and make sure both test suites pass before asking for review.

## License

By contributing, you agree that your contributions are licensed under the [MIT License](LICENSE).
