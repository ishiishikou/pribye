# LiteRT-LM iOS Metal build

## Background

The production analyzer uses `gemma-4-E4B-it.litertlm` through LiteRT-LM. On iPhone 16, the released LiteRT-LM `v0.14.0` iOS binary failed to initialize the GPU backend. The previous CPU fallback then aborted inside XNNPACK with an uncaught `std::bad_alloc` while reserving the fully connected weight cache.

Google AI Edge Gallery can execute the same E4B model on the same device because its iOS build includes the Metal accelerator in the LiteRT runtime. LiteRT-LM `v0.14.0` pins LiteRT commit `622f1f3c1352f4bc2925061b8cb72e9ce52874fe`, which predates the public `litert/runtime/accelerators/gpu` Bazel package. The Metal target therefore cannot be linked from that pinned public source revision.

## Build preparation

Both manual workflows call `scripts/prepare_litert_lm.sh` before XcodeGen:

1. Clone LiteRT-LM `v0.14.0` without Git LFS smudge.
2. Download the pinned public LiteRT source revision from `LITERT_GPU_REF` and calculate its SHA-256.
3. Point LiteRT-LM's existing `http_archive(name = "litert")` at that verified local archive.
4. Add the public LiteRT Metal accelerator target to `default_static_gpu_accelerator` for iOS.
5. Build `//swift:CLiteRTLM` with Bazelisk.
6. Replace the remote iOS binary target in the cloned `Package.swift` with the locally built XCFramework.
7. Verify that the device slice is arm64 and contains `CreateMlDriftMetalDelegate`.

The workflows currently pin LiteRT commit `0a0339003ab8e01b137e88238886a7f136e26866`, which contains the public Metal accelerator source. The accelerator and LiteRT-LM runtime are compiled into the same XCFramework. Do not mix a separately downloaded `libLiteRtMetalAccelerator.dylib` with the release XCFramework because version mismatches have caused native crashes during delegate creation.

This LiteRT revision is newer than the revision officially pinned by LiteRT-LM `v0.14.0`. Build and device validation are therefore required whenever the revision changes.

## Runtime policy

Gemma 4 E4B is GPU-only in Pribye. A saved CPU preference is ignored. This is intentional because the observed XNNPACK allocation failure terminates the process before Swift can catch an error.

`EngineConfig.cacheDir` is left `nil`, matching the normal Edge Gallery configuration for an app-managed model path.

## Validation

The workflows remain `workflow_dispatch` only. Building LiteRT-LM from source increases macOS Actions usage, so run them intentionally.

Before release:

- Run the `iOS` workflow and confirm the Metal build validation succeeds.
- Run the `TestFlight Upload` workflow.
- On the affected iPhone, download the verified E4B model and analyze a print.
- Confirm device logs contain `Statically linked GPU accelerator registered.` and `Gemma inference succeeded with gpu backend.`
- Confirm no CPU initialization appears and no new crash report is generated.
