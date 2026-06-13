# nix_unification.bzl

def _nix_unification_impl(repository_ctx):
    lock_path = repository_ctx.path(repository_ctx.attr.lock_file)
    lock_content = repository_ctx.read(lock_path)
    lock_data = json.decode(lock_content)
    
    build_content = []
    build_content.append("load(\"@nix_bazel_links//:nix_binary.bzl\", \"nix_binary\")")
    build_content.append("")
    
    NIX_BINARY_TEMPLATE = """nix_binary(
    name = "{name}",
    binary = "@nix_pkg_{package_hash}//:{binary_path}",
    linker = "@nix_pkg_{linker_package_hash}//:{linker_path}",
    lib_files = [
{lib_files_list}    ],
    additional_libs = [
{additional_libs_list}    ],
    visibility = ["//visibility:public"],
)

alias(
    name = "{name}_raw",
    actual = "@nix_pkg_{package_hash}//:{binary_path}",
    visibility = ["//visibility:public"],
)
"""

    LINKER_ALIAS_TEMPLATE = """alias(
    name = "glibc_linker",
    actual = "@nix_pkg_{linker_package_hash}//:{linker_path}",
    visibility = ["//visibility:public"],
)
"""

    # 1. Generate nix_binary targets
    for name, entrypoint in lock_data["entrypoints"].items():
        lib_files_lines = []
        for lib in (entrypoint.get("lib_files") or []):
            lib_files_lines.append('        "@nix_pkg_{package_hash}//:{file_path}",'.format(
                package_hash = lib["package_hash"],
                file_path = lib["file_path"],
            ))
        lib_files_list = "\n".join(lib_files_lines)
        if lib_files_list:
            lib_files_list += "\n"

        additional_libs_lines = []
        for lib in (entrypoint.get("additional_libs") or []):
            additional_libs_lines.append('        "@nix_store//:{store_name}",'.format(store_name = lib))
        additional_libs_list = "\n".join(additional_libs_lines)
        if additional_libs_list:
            additional_libs_list += "\n"

        build_content.append(NIX_BINARY_TEMPLATE.format(
            name = name,
            package_hash = entrypoint["package_hash"],
            binary_path = entrypoint["binary_path"],
            linker_package_hash = entrypoint["linker_package_hash"],
            linker_path = entrypoint["linker_path"],
            lib_files_list = lib_files_list,
            additional_libs_list = additional_libs_list,
        ))

    # 2. Expose raw linker alias just in case (using first resolved linker)
    for name, entrypoint in lock_data["entrypoints"].items():
        build_content.append(LINKER_ALIAS_TEMPLATE.format(
            linker_package_hash = entrypoint["linker_package_hash"],
            linker_path = entrypoint["linker_path"],
        ))
        break
        
    repository_ctx.file("BUILD.bazel", "\n".join(build_content))

nix_unification = repository_rule(
    implementation = _nix_unification_impl,
    attrs = {
        "lock_file": attr.label(mandatory = True),
    },
)
