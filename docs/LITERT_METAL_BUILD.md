# LiteRT-LM iOS Metal build

## Background

The production analyzer uses `gemma-4-E4B-it.litertlm` through LiteRT-LM. On iPhone 16, the released LiteRT-LM `v0.14.0` iOS binary failed to initialize the GPU backend. The previous CPU fallback then aborted inside XNNPACK with an uncaught `std::bad_alloc` while reserving the fully connected weight cache.

Google AI Edge Gallery can execute the same E4B model on the same device because its iOS build includes the Metal accelerator in the LiteRT runtime. The public LiteRT-LM `v0.14.0` source target `default_static_gpu_accelerator` has no open-source dependency selected by default, so the release XCFramework does not provide the equivalent static Metal path.

## Build preparation

Both manual workflows call `scripts/prepare_litert_lm.sh` before XcodeGen:

1. Clone LiteRT-LM `v0.14.0` without Git LFS smudge.
2. Add the matching LiteRT Metal accelerator target to `default_static_gpu_accelerator` for iOS.
3. Build `//swift:CLiteRTLM` with Bazelisk.
4. Replace the remote iOS binary target in the cloned `Package.swift` with the locally built XCFramework.
5. Verify that the device slice is arm64 and contains `CreateMlDriftMetalDelegate`.

The Metal accelerator and LiteRT-LM runtime are built from the same dependency graph. Do not mix a separately downloaded `libLiteRtMetalAccelerator.dylib` with the release XCFramework because version mismatches have caused native crashes during delegate creation.

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
