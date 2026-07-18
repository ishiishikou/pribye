#!/usr/bin/env bash
set -euo pipefail

: "${LITERT_LM_VERSION:?LITERT_LM_VERSION is required}"
: "${LITERT_LM_MAC_CHECKSUM:?LITERT_LM_MAC_CHECKSUM is required}"
: "${LITERT_GPU_REF:?LITERT_GPU_REF is required}"

PACKAGE_DIR="Vendor/LiteRT-LM"
LITERT_ARCHIVE="$PWD/Vendor/LiteRT-$LITERT_GPU_REF.tar.gz"
PREBUILT_DIR="$PACKAGE_DIR/Prebuilt"
XCFRAMEWORK_PATH="$PREBUILT_DIR/CLiteRTLM.xcframework"

rm -rf "$PACKAGE_DIR" "$LITERT_ARCHIVE"
mkdir -p Vendor
GIT_LFS_SKIP_SMUDGE=1 git clone \
  --depth 1 \
  --branch "$LITERT_LM_VERSION" \
  --single-branch \
  https://github.com/google-ai-edge/LiteRT-LM.git \
  "$PACKAGE_DIR"

curl --fail --location --retry 3 \
  "https://github.com/google-ai-edge/LiteRT/archive/$LITERT_GPU_REF.tar.gz" \
  --output "$LITERT_ARCHIVE"

LITERT_GPU_SHA256=$(shasum -a 256 "$LITERT_ARCHIVE" | awk '{print $1}')
export LITERT_ARCHIVE LITERT_GPU_SHA256

python3 - <<'PY'
import os
import re
import tarfile
from pathlib import Path

package_dir = Path("Vendor/LiteRT-LM")
litert_ref = os.environ["LITERT_GPU_REF"]
litert_sha256 = os.environ["LITERT_GPU_SHA256"]
litert_archive = Path(os.environ["LITERT_ARCHIVE"]).resolve()

with tarfile.open(litert_archive, "r:gz") as archive:
    build_path = f"LiteRT-{litert_ref}/litert/runtime/accelerators/gpu/BUILD"
    member = archive.extractfile(build_path)
    if member is None:
        raise SystemExit(
            "The selected LiteRT revision does not contain the public GPU accelerator package"
        )
    gpu_build_contents = member.read().decode("utf-8")
    if gpu_build_contents.count('name = "ml_drift_metal_accelerator"') != 1:
        raise SystemExit(
            "The selected LiteRT revision does not expose exactly one Metal accelerator target"
        )

workspace = package_dir / "WORKSPACE"
workspace_contents = workspace.read_text(encoding="utf-8")
workspace_contents, ref_count = re.subn(
    r'LITERT_REF = "[0-9a-f]+"',
    f'LITERT_REF = "{litert_ref}"',
    workspace_contents,
    count=1,
)
workspace_contents, sha_count = re.subn(
    r'LITERT_SHA256 = "[0-9a-f]+"',
    f'LITERT_SHA256 = "{litert_sha256}"',
    workspace_contents,
    count=1,
)
old_url = 'url = "https://github.com/google-ai-edge/LiteRT/archive/" + LITERT_REF + ".tar.gz",'
new_url = f'url = "{litert_archive.as_uri()}",'
url_count = workspace_contents.count(old_url)
workspace_contents = workspace_contents.replace(old_url, new_url)
if (ref_count, sha_count, url_count) != (1, 1, 1):
    raise SystemExit(
        "Expected LiteRT-LM WORKSPACE LiteRT archive configuration was not found exactly once"
    )
workspace.write_text(workspace_contents, encoding="utf-8")

build_file = package_dir / "runtime/executor/BUILD"
build_contents = build_file.read_text(encoding="utf-8")

old_gpu_target = '''cc_library(
    name = "default_static_gpu_accelerator",
    deps = select({
        # If CAPI is linked dynamically, need to link the accelerator dynamically as well.
        "@litert//litert:litert_runtime_link_mode_dynamic": [],
        "//conditions:default": [
        ],
    }) + select({
        "//conditions:default": [],
    }),
)'''
new_gpu_target = '''cc_library(
    name = "default_static_gpu_accelerator",
    deps = select({
        # If CAPI is linked dynamically, need to link the accelerator dynamically as well.
        "@litert//litert:litert_runtime_link_mode_dynamic": [],
        "//conditions:default": [
        ],
    }) + select({
        "@platforms//os:ios": [
            "@litert//litert/runtime/accelerators/gpu:ml_drift_metal_accelerator",
        ],
        "//conditions:default": [],
    }),
)'''

if build_contents.count(old_gpu_target) != 1:
    raise SystemExit("Expected LiteRT-LM default_static_gpu_accelerator target was not found exactly once")
build_file.write_text(build_contents.replace(old_gpu_target, new_gpu_target), encoding="utf-8")

manifest = package_dir / "Package.swift"
manifest_contents = manifest.read_text(encoding="utf-8")
old_mac_checksum = "13e818c9d3987afa87f0716884ebf0b6b10677b480717b8b098146e6b4f45847"
new_mac_checksum = os.environ["LITERT_LM_MAC_CHECKSUM"]
if manifest_contents.count(old_mac_checksum) != 1:
    raise SystemExit("Expected LiteRT-LM macOS checksum was not found exactly once")
manifest.write_text(
    manifest_contents.replace(old_mac_checksum, new_mac_checksum),
    encoding="utf-8",
)
PY

(
  cd "$PACKAGE_DIR"
  bazelisk build //swift:CLiteRTLM
)

python3 - <<'PY'
import re
import shutil
import zipfile
from pathlib import Path

package_dir = Path("Vendor/LiteRT-LM")
bazel_swift_dir = (package_dir / "bazel-bin/swift").resolve()
prebuilt_dir = package_dir / "Prebuilt"
destination = prebuilt_dir / "CLiteRTLM.xcframework"

candidates = sorted(
    [
        path
        for path in bazel_swift_dir.rglob("*")
        if path.name in {"CLiteRTLM.xcframework", "CLiteRTLM.xcframework.zip"}
    ],
    key=lambda path: (path.name.endswith(".zip"), len(path.parts)),
)
if not candidates:
    raise SystemExit("Bazel did not produce CLiteRTLM.xcframework or CLiteRTLM.xcframework.zip")

shutil.rmtree(prebuilt_dir, ignore_errors=True)
prebuilt_dir.mkdir(parents=True)
artifact = candidates[0]

if artifact.is_dir():
    shutil.copytree(artifact, destination)
else:
    extraction_dir = prebuilt_dir / "extracted"
    with zipfile.ZipFile(artifact) as archive:
        archive.extractall(extraction_dir)
    extracted = next(extraction_dir.rglob("CLiteRTLM.xcframework"), None)
    if extracted is None:
        raise SystemExit("CLiteRTLM.xcframework was not found inside Bazel output zip")
    shutil.copytree(extracted, destination)
    shutil.rmtree(extraction_dir)

manifest = package_dir / "Package.swift"
manifest_contents = manifest.read_text(encoding="utf-8")
pattern = re.compile(
    r'''\.binaryTarget\(\s*name:\s*"CLiteRTLM",\s*url:\s*"[^"]+",\s*checksum:\s*"[^"]+"\s*\)''',
    re.MULTILINE,
)
replacement = '''.binaryTarget(
      name: "CLiteRTLM",
      path: "Prebuilt/CLiteRTLM.xcframework"
    )'''
manifest_contents, replacement_count = pattern.subn(replacement, manifest_contents)
if replacement_count != 1:
    raise SystemExit("Expected remote CLiteRTLM binary target was not replaced exactly once")
manifest.write_text(manifest_contents, encoding="utf-8")
PY

DEVICE_BINARY=$(find "$XCFRAMEWORK_PATH" -path '*ios-arm64*' -type f -name CLiteRTLM -print -quit)
if [ -z "$DEVICE_BINARY" ]; then
  echo "::error::The iOS arm64 CLiteRTLM binary was not found"
  exit 1
fi

xcrun lipo -info "$DEVICE_BINARY" | grep -q 'arm64'
if ! (nm -a "$DEVICE_BINARY" 2>/dev/null || true) | grep -q 'CreateMlDriftMetalDelegate'; then
  echo "::error::The built CLiteRTLM binary does not contain the Metal delegate"
  exit 1
fi

echo "Prepared LiteRT-LM $LITERT_LM_VERSION with LiteRT $LITERT_GPU_REF and the statically linked iOS Metal accelerator."
