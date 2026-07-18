# LiteRT-LM Metal handoff

The production Gemma 4 E4B path requires the statically linked iOS Metal accelerator built by `scripts/prepare_litert_lm.sh`. See `docs/LITERT_METAL_BUILD.md` for the build and device-validation procedure.

Do not restore E4B CPU fallback without first proving that XNNPACK initialization cannot reproduce the uncaught `std::bad_alloc` observed in `Pribye-2026-07-18-230656.ips`.
