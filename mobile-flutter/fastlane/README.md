fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## Android

### android build_aab

```sh
[bundle exec] fastlane android build_aab
```

Build signed release App Bundle (flutter build appbundle --release)

### android closed_beta

```sh
[bundle exec] fastlane android closed_beta
```

Upload existing AAB to Play closed testing track with Thai release notes

### android release_closed

```sh
[bundle exec] fastlane android release_closed
```

Build AAB then upload to Play closed testing

### android verify_play_api

```sh
[bundle exec] fastlane android verify_play_api
```

Verify Google Play API credentials and closed testing track access

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
