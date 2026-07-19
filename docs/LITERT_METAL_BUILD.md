# LiteRT-LM iOS Metal build

## Goal

Pribye must run `gemma-4-E4B-it.litertlm` on an iPhone 16 through the Metal GPU backend. CPU/XNNPACK fallback is disabled because the observed fallback path terminated the process with `std::bad_alloc` while allocating the fully connected weight cache; that native abort cannot be recovered by Swift `do-catch`.

Completion requires a TestFlight build to finish a real print analysis on the affected device with GPU initialization success, no CPU initialization, and no crash report. A successful CI build alone is not completion.

## Upstream findings

The public Google AI Edge Gallery repository does not contain its iOS application source, so its exact iOS dependency and link configuration cannot be reproduced from that repository. The public LiteRT-LM `v0.14.0` source pins LiteRT commit `622f1f3c1352f4bc2925061b8cb72e9ce52874fe`; that LiteRT revision predates the public `litert/runtime/accelerators/gpu` package and therefore cannot provide the public Metal accelerator target.

Using LiteRT-LM `v0.14.0` with a substantially newer LiteRT revision is not an upstream-supported commit set. The two projects changed together across that interval, including LiteRT C/C++ APIs and the accelerator registry. PR #8 therefore uses an exact pair taken from the LiteRT-LM repository rather than mixing the release tag with a later LiteRT snapshot:

- LiteRT-LM: `a24de83834ad5419ab2f493dc0f4c15b4b67d0ec`
- LiteRT: `ac4e6fca88306c637ad0f319b4a22a93c36d01f3`

The selected LiteRT-LM commit pins that exact LiteRT commit in its `WORKSPACE`. The preparation script fails if those pins diverge.

The upstream public LiteRT-LM `default_static_gpu_accelerator` target is empty. Pribye adds `@litert//litert/runtime/accelerators/gpu:ml_drift_metal_accelerator` only for iOS. This remains a custom integration and must be validated by Bazel, Xcode, and the physical device.

## Linux preflight

Both manual workflows start on `ubuntu-latest`. The Linux job performs all network acquisition and source-level checks before a macOS runner is allocated:

1. Fetch the exact LiteRT-LM commit without Git LFS model downloads.
2. Read its official LiteRT commit and archive SHA-256 from `WORKSPACE`.
3. Require the workflow's LiteRT pin to match the official pin.
4. Download the exact LiteRT source archive and verify its original SHA-256.
5. Require the pinned source to expose exactly one Metal accelerator target and one iOS Metal framework target.
6. Scan every public `BUILD` file for active references to Google's non-public `//devtools/compliance/licenses:no_external_contributions` target.
7. Require the only active reference to be `litert/runtime/accelerators/gpu/BUILD`, then remove that single build-metadata assignment.
8. Leave Copybara-commented references, including the one in `serialization_weight_cache/BUILD`, unchanged.
9. Add the iOS Metal target to LiteRT-LM's `default_static_gpu_accelerator` dependency.
10. Record the exact commits and original/patched archive hashes in metadata.
11. Package the prepared source tree and patched archive into a short-lived workflow artifact.

The removed declaration is build metadata only. Source files retain their Apache 2.0 headers and implementation content. The script intentionally rejects any new or relocated active internal-license reference instead of broadly deleting matching text.

## macOS build

The macOS job depends on the Linux preflight job and consumes its artifact; it does not clone or download the two upstream repositories again.

The build stage:

1. Verifies the artifact metadata, commit pins, and patched archive SHA-256.
2. Points LiteRT-LM's existing `http_archive(name = "litert")` at the local verified archive.
3. Builds `//swift:CLiteRTLM` with Bazelisk.
4. Replaces the remote iOS binary target in the prepared `Package.swift` with the locally built XCFramework.
5. Requires an iOS device arm64 slice.
6. Requires the linked binary to contain `CreateMlDriftMetalDelegate`.
7. Rejects a separately bundled `libLiteRtMetalAccelerator.dylib`; the accelerator must be statically linked into the same XCFramework as LiteRT-LM.

The upstream LiteRT source labels these accelerator targets experimental. Passing these checks proves that the intended code is present and linked; it does not prove that Gemma 4 E4B initializes successfully on iPhone 16.

## Workflow policy

`iOS` and `TestFlight Upload` remain `workflow_dispatch` only. Each invocation first runs the Linux preflight and allocates macOS only if preflight succeeds. The source artifact is retained for one day.

Do not merge PR #8 based only on source inspection. Run the `iOS` workflow first. Run `TestFlight Upload` only after the XCFramework build and simulator test succeed.

## Physical-device validation

On the affected iPhone 16:

- Install the TestFlight build.
- Download the verified Gemma 4 E4B model.
- Analyze a representative print through the normal application flow.
- Confirm logs report static GPU accelerator registration and successful GPU inference.
- Confirm no CPU/XNNPACK initialization occurs.
- Confirm no new crash report is generated.

Only that result closes the crash issue.
