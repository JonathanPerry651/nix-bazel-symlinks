#!/bin/bash
set -e

echo "=== System Information ==="
uname -a
echo "Architecture: $(uname -m)"

echo "=== Installing Prerequisites ==="
apt-get update -y
apt-get install -y curl g++ git python3 xz-utils

echo "=== Installing Bazelisk ==="
ARCH=$(uname -m)
if [ "$ARCH" = "x86_64" ]; then
    BAZELISK_ARCH="amd64"
else
    BAZELISK_ARCH="arm64"
fi

echo "Downloading Bazelisk for linux-${BAZELISK_ARCH}..."
curl -Lo /usr/local/bin/bazel "https://github.com/bazelbuild/bazelisk/releases/latest/download/bazelisk-linux-${BAZELISK_ARCH}"
chmod +x /usr/local/bin/bazel

echo "Bazel version:"
bazel --version

echo "=== Cleaning Workspace ==="
bazel clean --expunge

echo "=== Building All Nix Packages ==="
bazel build //:hello //:patchelf //:ripgrep

echo "=== Debugging Nix Metadata ==="
find $(bazel info output_base)/external/ -name _nix_metadata.json -exec echo "--- {} ---" \; -exec cat {} \;

echo "=== Running GNU Hello Nix Package ==="
bazel run //:hello

echo "=== Diagnosing External Cache Folders ==="
ls -la $(bazel info output_base)/external/

echo "=== Listing Runfiles Tree for Patchelf ==="
find bazel-bin/patchelf.runfiles/ -name "*libgcc_s.so*" -exec ls -ld {} \;
find bazel-bin/patchelf.runfiles/ -name "*nix_store*" -exec ls -ld {} \;
find bazel-bin/patchelf.runfiles/ -name "*libgcc*" -exec ls -ld {} \;

echo "=== Running Patchelf Nix Package ==="
bazel run //:patchelf -- --version

echo "=== Running Ripgrep Nix Package ==="
bazel run //:ripgrep -- --version
bazel run //:ripgrep -- "main" /workspace/main.c

echo "=== Building Custom Rule Targets ==="
bazel build //:hello_gen_out //:ripgrep_search_out //:patchelf_inspect_out

echo "=== Verifying Custom Rule Outputs ==="
echo "hello_message.txt:"
cat bazel-bin/hello_message.txt
echo "rg_matches.txt:"
cat bazel-bin/rg_matches.txt
echo "hello_interpreter.txt:"
cat bazel-bin/hello_interpreter.txt

echo "=== Verification Completed Successfully! ==="
