# Glance CPU Compatibility

An independent source repository based on [Jonathan Zhou’s Glance](https://github.com/jonnyoo/glance), with Intel CPU compatibility changes developed on a Lenovo Hackintosh. Original source attribution and the MIT license are retained. Base revision: `b97f521397ec1197ba17768ba797cae1e628848d` (Glance 1.2).

## Changes

- CPU-only Core ML and Vision requests, with an explicit software image context for face detection.
- Owned BGRA camera frames, opaque pixel handling, bounded crop/scale operations, and a Core Graphics preview instead of the accelerated video preview layer.
- Separate, serialized face-detection requests and an earlier detector fallback when the primary detector finds no face.
- Higher-detail working frames at up to ten frames per second.
- Enrollment defers embedding inference until a capture qualifies, with feedback for missing pose, alignment, image quality, and processing errors. The original nine poses, eighteen samples, quality gates, hold times, and liveness/matching thresholds are retained.
- A separate local Data Protection Keychain identity, with user-presence protection retained; no vendor Keychain group is claimed.
- Restored application icon and disabled upstream automatic updates for compatibility builds.

## Build

Requires Intel macOS 15+ and Xcode 26+. The build was checked with Xcode 26.5. Clone this repository, then run:

```sh
python3 tools/build_cpu_compatibility.py
```

The result is `build/Glance.app`, locally ad-hoc signed with compatibility metadata and the compiled bundled ArcFace model. The script does not install the app, alter system security, change EFI, or grant privacy permissions. It refuses to overwrite an existing output; pass `--output /path/to/Glance.app` to select another location.

The local identity in `tools/CPUCompatibility.entitlements` is `org.codex.local.GlanceCPU`. Entitlement acceptance was tested only on the development laptop’s existing boot/security configuration. Standard macOS distribution requires an appropriate signing identity and authorized entitlements; this repository does not provide a provisioning profile or notarized release. Do not change system security merely to run this build.

Quit the existing Glance before installing a replacement. macOS may require Camera and Accessibility approval again when its signature changes. Enter your password only in Glance or the macOS authentication dialog. The local Keychain group does not automatically migrate the upstream app’s protected credentials; existing encrypted data is not deleted or silently rekeyed.

## Validation and status

- Intel Release build and strict recursive code-signature verification passed.
- AddressSanitizer tests covered copied camera-buffer ownership, zero-alpha BGRA pixels, scale/crop orientation, invalid inputs, and concurrent crop/resize operations.
- A public sample face passed detection, measured pose, landmarks, quality, and the camera pixel-conversion path.
- Deferred enrollment inference matched the full recognition path (cosine similarity above 0.9999; 512 finite values and five-point alignment).
- Synthetic Keychain tests reproduced missing-entitlement status `-34018`, then confirmed protected storage succeeds with the local identity while an unauthenticated read remains denied (`-25308`). Only the test’s own temporary items were created and deleted.

Live face detection and head-position feedback were observed. Complete enrollment, actual credential saving after the final entitlement repair, and reliable wake-to-unlock behavior still need user validation. This is experimental hardware compatibility work, not a claim of universal Hackintosh support.

Glance uses a normal webcam, not Apple Face ID hardware. Upstream’s security limitations and threat model still apply. See [the original project documentation](UPSTREAM_README.md) for the application design and model conversion notes in [tools/README.md](tools/README.md).

The camera renderer test uses synthetic pixels and requires no camera permission:

```sh
mkdir -p build
xcrun swiftc -sanitize=address glance/CPUFrameRenderer.swift tools/cpu_renderer_selftest.swift -o build/cpu-renderer-selftest
build/cpu-renderer-selftest
```

## License and credits

Compatibility contributions: [OLGTX303](https://github.com/OLGTX303).

[MIT](LICENSE), original copyright Jonathan Zhou. The original model and upstream third-party acknowledgements are preserved. This repository contains source and build tooling; no user camera images, enrolled face templates, passwords, Keychain exports, machine-specific logs, EFI images, or permission-bypass helpers are included.
