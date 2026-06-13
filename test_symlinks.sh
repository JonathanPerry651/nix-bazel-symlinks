#!/bin/bash
set -e

echo "=== System Information ==="
uname -a
echo "Architecture: $(uname -m)"

echo "=== Installing Prerequisites ==="
apt-get update -y
apt-get install -y curl g++ git python3

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

echo "=== Running Bazel Build ==="
# We run the build with strict sandboxing enabled!
bazel build //:main --verbose_failures --spawn_strategy=sandboxed

echo "=== Verifying Built Artifacts ==="
ls -la bazel-bin/

echo "=== Running Built Executable ==="
# We change directory to bazel-bin so that the RPATH "." resolves to the directory containing the shared library!
cd bazel-bin
./main
echo "=== Test Completed Successfully! ==="
