# Nix-Bazel Symlink Integration: Production-Grade Multi-GLIBC Isolation

A proof-of-concept demonstrating how to integrate Nix packages directly into a strict, sandboxed **Bazel 9.x (Bzlmod)** workspace. 

This approach runs with **zero host dependencies** (no local Nix installation or Nix daemon needed), is **100% RBE (Remote Build Execution) compatible**, and successfully supports **multi-GLIBC coexistence** in the same build graph without cross-contamination.

---

## The Approach

The core idea is to treat Nix store paths as Bazel external repositories, resolve absolute `/nix/store` symlinks to relative Bzlmod sibling traversals, and run binaries with scoped dynamic linkers.

```mermaid
graph TD
    subgraph "NixOS Cache"
        Cache[cache.nixos.org] -->|.nar.xz| Extractor[Pure Go Extractor]
    end

    subgraph "Bzlmod Repositories"
        Extractor -->|Unpack| Repos[Individual Nix Package Repos]
        Repos -->|JSON Metadata| Forest[@nix_store Symlink Forest]
    end

    subgraph "Sandboxed Execution"
        Forest -->|Relative Traversals| Bin[nix_binary target]
        Bin -->|Runs via| LD[Dynamic Linker ld-linux]
        LD -->|Resolves closure via| Libs[libs in sibling repos]
    end
```

### 1. Pure Go NAR Extractor
Instead of relying on a host-level `nix` tool, we download `.nar.xz` packages directly from `cache.nixos.org`. The custom [nix_extractor.go](file:///Users/jonathanperry/.gemini/antigravity/scratch/nix-bazel-symlinks/nix_extractor.go) streams, decompresses, and unpacks the package. It also writes virtual symlink metadata into a `_nix_metadata.json` file inside the repository.

### 2. Relative Symlink Translation
In a normal Nix store, packages use absolute paths (e.g. `/nix/store/1bdzriip...-glibc/lib/libc.so.6`). In Bazel, these paths do not exist. 
- [nix_import.bzl](file:///Users/jonathanperry/.gemini/antigravity/scratch/nix-bazel-symlinks/nix_import.bzl) parses the metadata JSON and translates absolute `/nix/store` paths into relative sibling traversals (e.g. `../../nix_pkg_1bdzriip...`).
- Because Bzlmod mangles repository names, these symlinks traverse exactly two levels up (`../../`) to resolve other Bzlmod-managed repositories.

### 3. Central `@nix_store` Symlink Forest
To emulate the `/nix/store` structure, a central repository [nix_store.bzl](file:///Users/jonathanperry/.gemini/antigravity/scratch/nix-bazel-symlinks/nix_store.bzl) aggregates virtual symlinks pointing to every dependency repository. This ensures that any standard dynamic linker looking for a sibling `/nix/store` path can find it via the runfiles of the target.

### 4. Multi-GLIBC Isolation
Different packages often require different GLIBC versions (e.g. `hello` and `patchelf` on **GLIBC 2.42**, while `ripgrep` runs on **GLIBC 2.35**).
To prevent dynamic linker mismatches or host-dependency leaks:
- The [nix_binary.bzl](file:///Users/jonathanperry/.gemini/antigravity/scratch/nix-bazel-symlinks/nix_binary.bzl) wrapper discovers the local Bazel `.runfiles` directory robustly.
- It executes the binary directly through its own, package-specific dynamic linker (`ld-linux`) using `--library-path` pointed exclusively to its specific transitive dependency closure.

### 5. API Unification (@nix)
To shield users from knowing cryptographic hashes of Nix packages, a unification repository [nix_unification.bzl](file:///Users/jonathanperry/.gemini/antigravity/scratch/nix-bazel-symlinks/nix_unification.bzl) is generated. 
- It houses all the `nix_binary` rule declarations.
- It exports clean aliases (e.g. `@nix//:hello_raw`, `@nix//:glibc_linker`) for use in custom build rules.
- This reduces the user's `MODULE.bazel` to only need to import `nix` and `nix_store`, hiding individual package hashes.

```mermaid
graph LR
    subgraph "GLIBC 2.42 Environment"
        H[//:hello] --> LD1[ld-linux glibc-2.42]
        P[//:patchelf] --> LD1
        LD1 --> GLIBC1[libc.so.6 glibc-2.42]
    end
    subgraph "GLIBC 2.35 Environment"
        R[//:ripgrep] --> LD2[ld-linux glibc-2.35]
        LD2 --> GLIBC2[libc.so.6 glibc-2.35]
        LD2 --> PCRE[libpcre2-8.so]
    end
```

---

## File Structure

- [MODULE.bazel](file:///Users/jonathanperry/.gemini/antigravity/scratch/nix-bazel-symlinks/MODULE.bazel): Registers Bzlmod dependencies and loads the Nix package extension.
- [BUILD.bazel](file:///Users/jonathanperry/.gemini/antigravity/scratch/nix-bazel-symlinks/BUILD.bazel): Declares runnable target binaries (`//:hello`, `//:patchelf`, `//:ripgrep`).
- [nix_extension.bzl](file:///Users/jonathanperry/.gemini/antigravity/scratch/nix-bazel-symlinks/nix_extension.bzl): Bzlmod module extension registering the Nix packages and the `@nix_store` forest.
- [nix_import.bzl](file:///Users/jonathanperry/.gemini/antigravity/scratch/nix-bazel-symlinks/nix_import.bzl): Repository rule to download, unpack, and map symlinks for a single package.
- [nix_store.bzl](file:///Users/jonathanperry/.gemini/antigravity/scratch/nix-bazel-symlinks/nix_store.bzl): Combines packages into a single symlink forest.
- [nix_unification.bzl](file:///Users/jonathanperry/.gemini/antigravity/scratch/nix-bazel-symlinks/nix_unification.bzl): Repository rule to expose unified, hash-free entrypoints and raw aliases.
- [nix_binary.bzl](file:///Users/jonathanperry/.gemini/antigravity/scratch/nix-bazel-symlinks/nix_binary.bzl): Wrapper script rule to safely resolve paths and launch binaries via the correct `ld-linux`.
- [nix_extractor.go](file:///Users/jonathanperry/.gemini/antigravity/scratch/nix-bazel-symlinks/nix_extractor.go): A standalone Go program that downloads NARs and outputs file structures and metadata.
- [custom_rules.bzl](file:///Users/jonathanperry/.gemini/antigravity/scratch/nix-bazel-symlinks/custom_rules.bzl): Custom Starlark rules that invoke the Nix-built binaries as part of sandboxed build actions.

---

## Custom Build Rules

To verify that the Nix binaries can be consumed as build tools by other Bazel rules, [custom_rules.bzl](file:///Users/jonathanperry/.gemini/antigravity/scratch/nix-bazel-symlinks/custom_rules.bzl) defines three custom rules:

1. **`nix_hello_gen`**: Runs the `//:hello` binary to output a hello message.
2. **`nix_ripgrep_search`**: Runs `//:ripgrep` to search a file for a regex pattern.
3. **`nix_patchelf_inspect`**: Runs `//:patchelf` with `--print-interpreter` on an ELF binary to extract its dynamic linker path.

These rules use `ctx.actions.run_shell` and execute the nix-packaged binaries inside Bazel's strict sandboxed build actions.

---

## Verification & Usage

You can test this repository inside a clean, unprivileged Linux container (e.g. using Docker or Podman) to verify that no host libraries are being leaked.

Run the test script in Ubuntu 22.04:
```bash
podman run --rm \
  -v $(pwd):/workspace \
  -w /workspace \
  ubuntu:22.04 \
  bash /workspace/test_nix.sh
```

The script will automatically install prerequisites, download Bazelisk, clean the workspace, build all targets (including the custom rules and their Nix dependencies), and execute/verify all output files.
