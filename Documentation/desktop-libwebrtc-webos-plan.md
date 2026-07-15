# Desktop `libwebrtc` on GetStream/webrtc, and webOS groundwork

**Status as of this writing:** groundwork complete across three repos, all local commits on
branch `feat/lg-webos`, **nothing pushed to any remote yet**. No real build has been run end
to end. This document is the handoff for the remaining testing/validation work, which needs a
real Linux (and eventually Windows) machine with the actual toolchain — this environment could
only do static/syntax-level verification.

## Why this work exists

`stream_webrtc_flutter`'s desktop platforms (Windows, Linux, eLinux) don't use the native
ObjC/Java WebRTC SDK — they compile the shared `common/cpp/*.cc` against a **`libwebrtc` C++
wrapper** (its own `include/` API + a `libwebrtc.so`/`.dll`), currently downloaded from
**`webrtc-sdk/libwebrtc`** releases (see the old `third_party/libwebrtc_version.ini`). The goal
of this work is to build that same desktop wrapper **first-party from `GetStream/webrtc`**
(the fork that already produces the Apple xcframework and Android AAR), and lay the toolchain
groundwork for a future **webOS** target (LG's Flutter embedder, via
[lg-flutter-webos](https://github.com/lg-flutter-webos)).

**webOS's own Flutter *plugin* integration (a `webos/` platform directory in this repo,
`example/webos`, `.ipk` packaging) is explicitly out of scope here and deferred to a separate
plan.** This phase only gets the webOS-flavored native `libwebrtc.so` buildable in CI.

## Repos involved (all on branch `feat/lg-webos`, all local-only so far)

| Repo | Role | Local path used in this work |
|---|---|---|
| `GetStream/webrtc` | WebRTC source fork — hosts the `libwebrtc` wrapper compatibility patches, the mb build configs, and CI build/publish jobs | `~/Documents/github/webrtc` |
| `GetStream/stream-webrtc-release-pipeline` | Fastlane build pipeline — hosts the new `desktop` build lane | `~/Documents/github/stream-webrtc-release-pipeline` |
| `GetStream/webrtc-flutter` (this repo) | The Flutter plugin — consumes the built `libwebrtc` artifacts | `~/Documents/github/webrtc-flutter` |

**Before doing anything, verify all three are checked out on `feat/lg-webos`** — that convention
was used throughout this work and matters if these clones are shared with others.

---

## What's done

### 1. `GetStream/webrtc` — desktop wrapper compatibility (commit `f268371008`)

The `libwebrtc` C++ wrapper's own source (`include/`, `src/`) is **not** vendored into
`GetStream/webrtc` — see the pre-existing `.gitignore` rule for `/libwebrtc` (added independently
by a Stream engineer in Nov 2024). It's fetched fresh from `webrtc-sdk/libwebrtc` at build time
(see fastlane lane below). What **does** need to live in `GetStream/webrtc` permanently is
whatever changes core WebRTC itself needs so that wrapper source compiles.

Three of `webrtc-sdk/libwebrtc`'s four wrapper-compatibility patches (originally written against
`webrtc-sdk/webrtc@m144_release`) were forward-ported onto `GetStream/webrtc`'s `145.10.0` tag
(the fork's current stable release — matches the mobile SDKs' existing `145.9.0`/`145.10.0`
binaries, so all platforms now align on m145):

- **`custom_audio_source_m144` → forward-ported.** Adds an optional, pluggable
  `AudioTransportFactory` to `CreatePeerConnectionFactory` (defaults to `nullptr`, falling back to
  the existing `AudioTransportImpl` — **behaviorally a no-op for iOS/Android/macOS**, which never
  pass this new parameter). This is genuinely required, not optional: the wrapper's own
  `RTCPeerConnectionFactoryImpl` unconditionally constructs a `CustomAudioTransportFactory`, and
  even the plugin's *ordinary* microphone capture path (`CreateAudioSource` in
  `common/cpp/src/flutter_media_stream.cc`) is wired through it. One file
  (`audio/audio_state.cc`) needed hand-porting because this fork already has its own
  `AudioState::OnMuteStreamChanged()` method sitting between the two functions the upstream patch
  touches — same semantic change, applied around that existing customization.
- **`fix_desktop_capture_compile` → applied cleanly** (Linux/Wayland desktop-capture compile fix;
  never compiled into iOS/Android builds at all).
- **`add_libwebrtc_build_target` → deliberately dropped.** It only adds `//libwebrtc` to GN's
  `default` build group; every build invocation in this pipeline (ours and upstream's) always
  names `libwebrtc` as an explicit `ninja` target, so this patch is inert either way.
- **`fix_emplace` → not needed.** Upstream WebRTC itself already refactored
  `LossBasedBweV2::CreateConfig` away from the `absl::optional::emplace()` pattern this patch
  worked around — the bug it fixed doesn't exist at m145.

### 2. `GetStream/webrtc` — mb build configs (commits `f50612e300`, `8d20857fb3`)

Added to `tools_webrtc/mb/mb_config.pyl`:
- `release_bot_webos_arm` / `debug_bot_webos_arm` configs, using a new `webos_arm_abi` mixin:
  `arm_version=7 arm_use_neon=true arm_float_abi="softfp"` (webOS's Cortex-A9/softfp target,
  distinct from the existing hardfp `release_bot_arm`/`debug_bot_arm` Linux configs — **these two
  cannot be used interchangeably**, softfp and hardfp are ABI-incompatible).
- Linux x64/arm64 and Windows x64 reuse **existing** upstream configs
  (`release_bot_x64`/`release_bot_arm64`/`win_clang_release_bot_x64` and their debug equivalents)
  — no new config needed there.
- The webOS NDK sysroot path is deliberately **not** hardcoded here (it's machine-specific) — it's
  injected at build time via `extra_gn_args` (see fastlane lane below).

### 3. `stream-webrtc-release-pipeline` — local mb configs (commits `2ad6088`, `223c35a`)

`fastlane/scripts/generate_local_mb_config.py` now also generates `disable_remoteexec` local
variants of all the desktop configs above (`release_local_bot_x64`, `release_local_bot_arm64`,
`win_clang_release_local_bot_x64`, `release_local_bot_webos_arm`, and their `debug_local_bot_*`
equivalents). Verified by actually running the script against the real `mb_config.pyl` and
checking the generated output.

### 4. `stream-webrtc-release-pipeline` — desktop fastlane lane (commits `ebf7a32`, `25db8fe`)

New `platform :desktop` lane in `fastlane/lanes/desktop.rb`, modeled on the existing `macos.rb`
lane (direct `gn gen` + `ninja`, not the Apple/Android Python-script delegation):

- Takes `target_os` (`linux`/`win`/`webos`), `arch` (`x64`/`arm64`/`arm`), `profile`
  (`release`/`debug`), resolves the matching local mb config.
- Fetches the `libwebrtc` wrapper source fresh from a **pinned** `webrtc-sdk/libwebrtc` commit
  (`8586c07c4c0a82f645cb0867913d43593a9e9466`) into `<root>/libwebrtc` — unpatched, since (per
  above) only `GetStream/webrtc`'s own core needed patching, not the wrapper itself.
- Builds the `libwebrtc` GN target explicitly by name.
- Stages `lib/` (the `.so`/`.dll`(+`.lib`)) + `include/` + `LICENSE` into a self-contained
  artifact directory, then zips it as `libwebrtc-{target_os}-{arch}-{profile}.zip`, wrapped in a
  single top-level directory — **this exact layout and naming was chosen to match what
  `webrtc-flutter`'s existing `third_party/CMakeLists.txt` already expects on extract**, so no
  changes were needed on the consuming side.
- Also fixed a small pre-existing gap in `utilities.rb`: `merge_gn_args_content` never quoted
  string GN values (only ever exercised by booleans before) — needed for the webOS
  `target_sysroot` override passed via `extra_gn_args`.
- **Verified:** the packaging step was actually run against a fake artifact tree and the
  resulting zip's layout confirmed with `unzip -l`. The GN/ninja build itself has **not** been
  run — the fastlane/rubocop gems aren't installed in this environment (only `ruby -c` syntax
  checks were possible).

### 5. `GetStream/webrtc` — CI wiring (commit `942a9c2fba`)

- New `prepare-desktop` composite action (Linux-hosted; shared by native-Linux and webOS jobs
  since both only need generic `unix` gclient deps — only their GN args differ).
- New jobs in both `.github/workflows/manual-platform-tests.yml` and `.github/workflows/publish.yml`:
  `prepare_desktop_linux`, `prepare_desktop_windows`, `build_desktop_linux` (x64/arm64 matrix),
  `build_desktop_webos`, `build_desktop_windows` — mirroring the existing Apple/Android
  prepare→build→upload pattern.
- Desktop artifacts upload as `release-desktop-*`, which `publish.yml`'s existing job **already**
  picks up via its `release-*` artifact glob when creating a GitHub Release — only its `needs:`
  list was extended, release creation itself is untouched.
- webOS builds require an explicit `webos_sysroot` **workflow input**, validated both up front and
  again immediately before the build (fails clearly if the path doesn't exist on the runner).
  **This workflow does not provision the webOS NDK onto the runner** — that's flagged explicitly
  as unsolved (see Remaining Work).
- **Verified with `actionlint`** (a real GitHub Actions linter, installed via `brew` for this
  purpose) — clean pass on both workflow files, which also cross-validates that
  `prepare-desktop`'s declared inputs match how both workflows invoke it.
- **Caveat, flagged inline in both workflow files:** the Windows-hosted jobs are the **first
  Windows CI in this repo** — reasonably confident in the design (Git Bash via `shell: bash` is
  standard on GitHub-hosted Windows runners; depot_tools supports Windows) but genuinely
  unverified against a real runner.

### 6. `webrtc-flutter` (this repo) — manifest repoint (commit `db0857b`)

`third_party/libwebrtc_version.ini` now points at `GetStream/webrtc` releases
(`download_url = https://github.com/GetStream/webrtc/releases/download`,
`binary_version = 145.10.0`). `third_party/CMakeLists.txt`'s asset-name composition
(`libwebrtc-{os}-{arch}-release.zip`) needed **no changes** — it already matches what the new
pipeline produces.

**This manifest does not yet resolve to a working download** — `145.10.0` doesn't have desktop
assets attached yet (see Remaining Work, step 3).

### 7. `common/cpp` wrapper-API compatibility audit (no code changes — verified clean)

Rather than a manual symbol diff, all 9 `common/cpp/src/*.cc` files were compiled with
`clang++ -std=c++17 -fsyntax-only`, using: `common/cpp/include`, the **pinned** wrapper commit's
real `include/` (cloned locally for this check), and the **real** Flutter engine's
`client_wrapper`/`public` headers (found in the local FVM-installed Flutter 3.44.1 SDK, not a
stand-in). Result: **zero errors** on all 9 files; with `-Wall -Wextra` added, only pre-existing
cosmetic warnings (unused parameters, sign-compare) unrelated to the wrapper API. **No `common/cpp`
changes are needed** for the m145 rebuild.

---

## Remaining work (what a human needs to do next)

### Step 0 — Review and push

Nothing has been pushed to any remote. Before anything else:
1. Review the diffs on `feat/lg-webos` in all three repos (`git log main..feat/lg-webos` /
   `git diff main..feat/lg-webos` in `GetStream/webrtc`; equivalent in the other two).
2. Push `feat/lg-webos` to each remote and open PRs as appropriate. **Nothing in this branch
   auto-triggers CI** — both `manual-platform-tests.yml` and `publish.yml` are `workflow_dispatch`
   -only (manually triggered, no `push`/`schedule`/`pull_request` trigger), so pushing is safe on
   its own.

### Step 1 — Get the fastlane lane actually building (Linux first)

The `desktop` fastlane lane (`stream-webrtc-release-pipeline/fastlane/lanes/desktop.rb`) has only
been syntax-checked, never run. On a real Linux machine with `bundle`/`fastlane`/depot_tools:

```
cd stream-webrtc-release-pipeline
bundle install
bundle exec fastlane desktop build \
  "root:<path-to-GetStream-webrtc-checkout>/.output/src" \
  "products_root:/tmp/desktop-products" \
  target_os:linux arch:x64 profile:release
```

(This assumes a `gclient sync`/`runhooks` has already populated `.output/src` — see how
`prepare-desktop`'s composite action does it, or just run the CI job instead, see Step 2.)

Expect to iterate here — this is genuinely untested. Watch particularly for:
- Whether the pinned wrapper commit (`8586c07c4c0a82f645cb0867913d43593a9e9466`) actually builds
  cleanly against `GetStream/webrtc@145.10.0` with the audio-transport-factory patch — the
  `-fsyntax-only` check in this work only validated `common/cpp`'s usage of the wrapper's public
  headers, **not** the wrapper's own `src/*.cc` implementation, which wasn't compiled at all.
- GN/ninja errors from the `libwebrtc` target itself.

Once linux x64 builds, try `arch:arm64` too (likely needs cross-compilation setup or an arm64
runner/machine).

### Step 2 — Or, run it via the real CI (recommended once Step 1's lane is trusted)

Trigger `manual-platform-tests.yml` manually (GitHub UI "Run workflow" or
`gh workflow run manual-platform-tests.yml --repo GetStream/webrtc -f desktop_linux=true`) with
`apple=false android=false desktop_linux=true` to isolate the new jobs. This exercises
`prepare-desktop` + `build_desktop_linux` for real, including the caching and artifact-upload
steps that Step 1's local run bypasses.

Do the equivalent for `desktop_windows=true` **on a real run** — this is the first Windows job in
this repo's CI and needs to be watched closely; expect to debug depot_tools/gclient-on-Windows
specifics that weren't visible from this (macOS) environment.

### Step 3 — Publish real desktop artifacts, then re-point `webrtc-flutter`

Once builds succeed, either:
- Re-run `publish.yml` for a **new** version tag with `desktop_linux`/`desktop_windows` enabled
  (alongside `ios`/`android` if cutting a full release), or
- Figure out how to attach desktop assets to the existing `145.10.0` release without conflicting
  with `publish.yml`'s `gh release create` (which will fail if a release for that tag already
  exists) — e.g. `gh release upload 145.10.0 <zips>` directly, bypassing the workflow for this
  one-off.

Then update `webrtc-flutter/third_party/libwebrtc_version.ini`'s `binary_version` if a new tag was
cut.

### Step 4 — Verify `webrtc-flutter` end to end (Linux, then Windows)

On the Ubuntu machine:
```
cd example
flutter build linux
```
This should trigger `third_party/CMakeLists.txt`'s download of the new `libwebrtc-linux-x64-release.zip`
and link against it. Then run the example app and exercise:
- `getUserMedia` (camera + mic),
- a loopback `RTCPeerConnection` (offer/answer between two local peer connections),
- local video render in an `RTCVideoView` (exercises the shared `flutter_video_renderer.cc`
  pixel-buffer texture path).

Repeat with `flutter build windows` on a Windows machine once Step 2/3 produce a working Windows
artifact.

Also sanity-check: `flutter pub get`, existing analyzer/tests still pass. No Dart changes were
made or are expected.

### Step 5 — webOS armv7 (build-only; plugin integration is a separate future plan)

This phase's webOS scope is **only** getting `libwebrtc.so` to build for the armv7/softfp target
— not the Flutter plugin/`webos/` directory itself. To exercise `build_desktop_webos`:

1. **Obtain the webOS NDK** (`webos-ndk-11.2.0` / "starfish" SDK) and figure out how to make its
   sysroot available to a CI runner or a manual build — **this workflow does not do this for
   you**, on purpose (LG's NDK provisioning process wasn't known at the time this was written; a
   self-hosted runner with it pre-installed is one option, or download-and-cache logic added to
   `prepare-desktop`/`build_desktop_webos` once the acquisition method is known).
2. Trigger `build_desktop_webos` with `webos_sysroot` pointing at that sysroot's path on the
   runner.
3. On success, sanity-check the output `libwebrtc.so`: `readelf -A libwebrtc.so` should show
   `Tag_ABI_VFP_args: VFP registers` absent / softfp indicators (not hardfp), confirming the
   float-ABI actually took effect — this is the detail most likely to silently go wrong.
4. No on-device webOS app testing yet — that requires the deferred plugin-integration plan
   (`webos/` platform directory in this repo, mirroring `elinux/`, plus `example/webos` and
   `.ipk` packaging).

### Known risks to keep an eye on

- **Windows CI is unverified** — first-ever Windows job in `GetStream/webrtc`'s Actions history.
- **webOS NDK provisioning is an open problem**, not solved by this work.
- **Wrapper `src/*.cc` was never actually compiled**, only its public headers' usage from
  `common/cpp` was verified. The real GN/ninja build (Step 1) is the first time the wrapper's own
  implementation gets compiled against `GetStream/webrtc@145.10.0`.
- **Future WebRTC milestone bumps**: the `AudioTransportFactory` patch is now permanent
  `GetStream/webrtc` source (not a reapplied `.patch` file), living in files this fork's own
  audio-pipeline branches (stereo playout, reworked audio pipeline, etc.) also touch — check it
  survives future merges/milestone bumps.
- **`145.10.0` currently has no desktop assets** — the manifest repoint in this repo is inert
  until Step 3 happens.

---

## Quick reference — commits

| Repo | Commit | Summary |
|---|---|---|
| `GetStream/webrtc` | `f268371008` | Forward-port `AudioTransportFactory` + desktop-capture compile-fix patches to m145 |
| `GetStream/webrtc` | `f50612e300` | Add release mb configs (linux/win/webos) |
| `GetStream/webrtc` | `8d20857fb3` | Add debug mb config for webOS armv7 |
| `GetStream/webrtc` | `942a9c2fba` | Wire desktop builds into Build/Publish CI workflows |
| `stream-webrtc-release-pipeline` | `2ad6088` | Local mb configs for desktop release builds |
| `stream-webrtc-release-pipeline` | `223c35a` | Local mb configs for desktop debug builds |
| `stream-webrtc-release-pipeline` | `ebf7a32` | New `desktop` fastlane build lane |
| `stream-webrtc-release-pipeline` | `25db8fe` | Zip packaging for desktop artifacts |
| `webrtc-flutter` | `db0857b` | Repoint `third_party/libwebrtc_version.ini` to `GetStream/webrtc` |

All on branch `feat/lg-webos` in each repo.
