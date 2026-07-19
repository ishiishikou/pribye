#!/usr/bin/env bash
set -euo pipefail

: "${LITERT_LM_REF:?LITERT_LM_REF is required}"
: "${LITERT_REF:?LITERT_REF is required}"

MODE="${LITERT_PREPARE_MODE:-build}"
VENDOR_DIR="Vendor"
PACKAGE_DIR="$VENDOR_DIR/LiteRT-LM"
LITERT_ARCHIVE="$PWD/$VENDOR_DIR/LiteRT-$LITERT_REF.tar.gz"
METADATA_PATH="$VENDOR_DIR/litert-preflight.json"
BUNDLE_PATH="$VENDOR_DIR/litert-preflight.tar.gz"
PREBUILT_DIR="$PACKAGE_DIR/Prebuilt"
XCFRAMEWORK_PATH="$PREBUILT_DIR/CLiteRTLM.xcframework"

prepare_preflight() {
  rm -rf "$PACKAGE_DIR" "$LITERT_ARCHIVE" "$METADATA_PATH" "$BUNDLE_PATH"
  mkdir -p "$VENDOR_DIR"

  git init -q "$PACKAGE_DIR"
  git -C "$PACKAGE_DIR" remote add origin https://github.com/google-ai-edge/LiteRT-LM.git
  GIT_LFS_SKIP_SMUDGE=1 git -C "$PACKAGE_DIR" fetch --depth 1 origin "$LITERT_LM_REF"
  git -C "$PACKAGE_DIR" checkout -q --detach FETCH_HEAD

  local actual_litert_lm_ref
  actual_litert_lm_ref=$(git -C "$PACKAGE_DIR" rev-parse HEAD)
  if [ "$actual_litert_lm_ref" != "$LITERT_LM_REF" ]; then
    echo "::error::Fetched LiteRT-LM commit $actual_litert_lm_ref, expected $LITERT_LM_REF"
    exit 1
  fi

  export PACKAGE_DIR LITERT_REF LITERT_ARCHIVE METADATA_PATH
  python3 - <<'PY'
import os
import re
from pathlib import Path

package_dir = Path(os.environ["PACKAGE_DIR"])
litert_ref = os.environ["LITERT_REF"]
workspace = package_dir / "WORKSPACE"
workspace_contents = workspace.read_text(encoding="utf-8")

ref_match = re.search(r'^LITERT_REF = "([0-9a-f]{40})"$', workspace_contents, re.MULTILINE)
sha_match = re.search(r'^LITERT_SHA256 = "([0-9a-f]{64})"$', workspace_contents, re.MULTILINE)
if ref_match is None or sha_match is None:
    raise SystemExit("Unable to read the LiteRT pin from the selected LiteRT-LM WORKSPACE")
if ref_match.group(1) != litert_ref:
    raise SystemExit(
        "LiteRT-LM and LiteRT are not an official pinned pair: "
        f"WORKSPACE={ref_match.group(1)}, requested={litert_ref}"
    )

Path("Vendor/litert-official-sha256.txt").write_text(sha_match.group(1) + "\n", encoding="utf-8")
PY

  curl --fail --location --retry 3 \
    "https://github.com/google-ai-edge/LiteRT/archive/$LITERT_REF.tar.gz" \
    --output "$LITERT_ARCHIVE"

  export LITERT_LM_REF
  python3 - <<'PY'
import hashlib
import io
import json
import os
import tarfile
from pathlib import Path

archive_path = Path(os.environ["LITERT_ARCHIVE"])
litert_ref = os.environ["LITERT_REF"]
litert_lm_ref = os.environ["LITERT_LM_REF"]
metadata_path = Path(os.environ["METADATA_PATH"])
expected_original_sha = Path("Vendor/litert-official-sha256.txt").read_text(encoding="utf-8").strip()

def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()

original_sha = sha256_file(archive_path)
if original_sha != expected_original_sha:
    raise SystemExit(
        "Downloaded LiteRT archive SHA-256 does not match the LiteRT-LM WORKSPACE pin: "
        f"actual={original_sha}, expected={expected_original_sha}"
    )

label = b'"//devtools/compliance/licenses:no_external_contributions"'
expected_member = f"LiteRT-{litert_ref}/litert/runtime/accelerators/gpu/BUILD"
expected_assignment = b'    default_applicable_licenses = ["//devtools/compliance/licenses:no_external_contributions"],\n'
patched_path = archive_path.with_suffix(archive_path.suffix + ".patched")
active_references = []
metal_target_count = 0
ios_framework_count = 0

with tarfile.open(archive_path, "r:gz") as source, tarfile.open(patched_path, "w:gz") as target:
    for member in source:
        if not member.isfile():
            target.addfile(member)
            continue

        extracted = source.extractfile(member)
        if extracted is None:
            raise SystemExit(f"Unable to read LiteRT archive member: {member.name}")
        data = extracted.read()

        if member.name.endswith("/BUILD"):
            for line in data.splitlines():
                if label in line and not line.lstrip().startswith(b"#"):
                    active_references.append(member.name)

        if member.name == expected_member:
            metal_target_count = data.count(b'name = "ml_drift_metal_accelerator"')
            ios_framework_count = data.count(b'name = "build_ml_drift_metal_accelerator_framework"')
            if data.count(expected_assignment) != 1:
                raise SystemExit(
                    "Pinned LiteRT GPU BUILD does not contain the expected single OSS-incompatible "
                    "default_applicable_licenses assignment"
                )
            data = data.replace(expected_assignment, b"", 1)

        member.size = len(data)
        target.addfile(member, io.BytesIO(data))

if active_references != [expected_member]:
    patched_path.unlink(missing_ok=True)
    raise SystemExit(
        "Unexpected active Google-internal license references in the pinned LiteRT archive: "
        + ", ".join(active_references)
    )
if metal_target_count != 1:
    patched_path.unlink(missing_ok=True)
    raise SystemExit("The pinned LiteRT revision does not expose exactly one Metal accelerator target")
if ios_framework_count != 1:
    patched_path.unlink(missing_ok=True)
    raise SystemExit("The pinned LiteRT revision does not expose exactly one iOS Metal framework target")

with tarfile.open(patched_path, "r:gz") as patched:
    remaining = []
    for member in patched:
        if not member.isfile() or not member.name.endswith("/BUILD"):
            continue
        extracted = patched.extractfile(member)
        if extracted is None:
            continue
        for line in extracted.read().splitlines():
            if label in line and not line.lstrip().startswith(b"#"):
                remaining.append(member.name)
if remaining:
    patched_path.unlink(missing_ok=True)
    raise SystemExit("Active Google-internal license references remain after patching: " + ", ".join(remaining))

patched_path.replace(archive_path)
patched_sha = sha256_file(archive_path)
metadata = {
    "litert_lm_ref": litert_lm_ref,
    "litert_ref": litert_ref,
    "litert_original_sha256": original_sha,
    "litert_patched_sha256": patched_sha,
    "patched_active_license_references": [expected_member],
    "metal_target": "@litert//litert/runtime/accelerators/gpu:ml_drift_metal_accelerator",
}
metadata_path.write_text(json.dumps(metadata, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY

  export PACKAGE_DIR
  python3 - <<'PY'
import os
from pathlib import Path

package_dir = Path(os.environ["PACKAGE_DIR"])
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
PY

  rm -rf "$PACKAGE_DIR/.git" "$VENDOR_DIR/litert-official-sha256.txt"
  tar -czf "$BUNDLE_PATH" -C "$VENDOR_DIR" \
    "LiteRT-LM" \
    "LiteRT-$LITERT_REF.tar.gz" \
    "litert-preflight.json"

  echo "Prepared aligned LiteRT-LM/LiteRT sources for macOS build: $BUNDLE_PATH"
}

prepare_build() {
  if [ ! -f "$BUNDLE_PATH" ]; then
    echo "::error::Linux preflight artifact is missing: $BUNDLE_PATH"
    exit 1
  fi

  rm -rf "$PACKAGE_DIR" "$LITERT_ARCHIVE" "$METADATA_PATH"
  mkdir -p "$VENDOR_DIR"
  tar -xzf "$BUNDLE_PATH" -C "$VENDOR_DIR"

  export PACKAGE_DIR LITERT_ARCHIVE METADATA_PATH LITERT_LM_REF LITERT_REF
  LITERT_PATCHED_SHA256=$(python3 - <<'PY'
import hashlib
import json
import os
from pathlib import Path

metadata_path = Path(os.environ["METADATA_PATH"])
archive_path = Path(os.environ["LITERT_ARCHIVE"])
package_dir = Path(os.environ["PACKAGE_DIR"])
metadata = json.loads(metadata_path.read_text(encoding="utf-8"))

if metadata.get("litert_lm_ref") != os.environ["LITERT_LM_REF"]:
    raise SystemExit("Preflight artifact LiteRT-LM commit does not match the workflow pin")
if metadata.get("litert_ref") != os.environ["LITERT_REF"]:
    raise SystemExit("Preflight artifact LiteRT commit does not match the workflow pin")
digest = hashlib.sha256()
with archive_path.open("rb") as source:
    for chunk in iter(lambda: source.read(1024 * 1024), b""):
        digest.update(chunk)
actual_sha = digest.hexdigest()
if actual_sha != metadata.get("litert_patched_sha256"):
    raise SystemExit("Preflight artifact LiteRT archive hash does not match its metadata")
if not (package_dir / "runtime/executor/BUILD").is_file():
    raise SystemExit("Preflight artifact does not contain the prepared LiteRT-LM source tree")
print(actual_sha)
PY
)
  export LITERT_PATCHED_SHA256

  python3 - <<'PY'
import os
import re
from pathlib import Path

package_dir = Path(os.environ["PACKAGE_DIR"])
workspace = package_dir / "WORKSPACE"
workspace_contents = workspace.read_text(encoding="utf-8")
litert_ref = os.environ["LITERT_REF"]
patched_sha = os.environ["LITERT_PATCHED_SHA256"]
litert_archive = Path(os.environ["LITERT_ARCHIVE"]).resolve()

workspace_contents, ref_count = re.subn(
    r'^LITERT_REF = "[0-9a-f]{40}"$',
    f'LITERT_REF = "{litert_ref}"',
    workspace_contents,
    count=1,
    flags=re.MULTILINE,
)
workspace_contents, sha_count = re.subn(
    r'^LITERT_SHA256 = "[0-9a-f]{64}"$',
    f'LITERT_SHA256 = "{patched_sha}"',
    workspace_contents,
    count=1,
    flags=re.MULTILINE,
)
old_url = 'url = "https://github.com/google-ai-edge/LiteRT/archive/" + LITERT_REF + ".tar.gz",'
new_url = f'url = "{litert_archive.as_uri()}",'
url_count = workspace_contents.count(old_url)
workspace_contents = workspace_contents.replace(old_url, new_url)
if (ref_count, sha_count, url_count) != (1, 1, 1):
    raise SystemExit("Expected LiteRT-LM WORKSPACE LiteRT archive configuration was not found exactly once")
workspace.write_text(workspace_contents, encoding="utf-8")
PY

  (
    cd "$PACKAGE_DIR"
    bazelisk build //swift:CLiteRTLM
  )

  export PACKAGE_DIR
  python3 - <<'PY'
import os
import re
import shutil
import zipfile
from pathlib import Path

package_dir = Path(os.environ["PACKAGE_DIR"])
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
    raise SystemExit("Expected remote CLiteRTLM iOS binary target was not replaced exactly once")
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
  if find "$XCFRAMEWORK_PATH" -type f -name 'libLiteRtMetalAccelerator.dylib' -print -quit | grep -q .; then
    echo "::error::A separate Metal accelerator dylib was bundled; the accelerator must be statically linked"
    exit 1
  fi

  echo "Built LiteRT-LM $LITERT_LM_REF with its pinned LiteRT $LITERT_REF and the statically linked iOS Metal accelerator."
}

case "$MODE" in
  preflight)
    prepare_preflight
    ;;
  build)
    prepare_build
    ;;
  *)
    echo "::error::Unsupported LITERT_PREPARE_MODE: $MODE"
    exit 1
    ;;
esac
