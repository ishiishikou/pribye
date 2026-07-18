# LiteRT-LM Metal handoff note

This temporary handoff note records the non-obvious runtime decision introduced by the E4B crash fix. The canonical technical details are in `docs/LITERT_METAL_BUILD.md`.

- iOS and TestFlight workflows build LiteRT-LM `v0.14.0` from source with the matching LiteRT Metal accelerator statically linked.
- Gemma 4 E4B is GPU-only in Pribye. CPU fallback is disabled because XNNPACK can terminate the process with an uncaught `std::bad_alloc` during weight preparation.
- `EngineConfig.cacheDir` is `nil` for the normal app-managed model path.
- The workflows remain manual and now consume more macOS Actions time because Bazel builds the XCFramework.
- Required release validation: run iOS CI, upload TestFlight, confirm `Statically linked GPU accelerator registered.` on the affected iPhone, and verify successful GPU inference.
