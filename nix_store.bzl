# nix_store.bzl

def _nix_store_impl(repository_ctx):
    packages = repository_ctx.attr.packages
    
    build_content = []
    build_content.append("load(\"@nix_bazel_links//:nix_symlink.bzl\", \"nix_symlinks\")")
    build_content.append("")
    
    # Declare the unresolved symlinks for the central forest
    # store/<store_name> -> ../../+nix_extension+nix_pkg_<hash>
    symlinks = {}
    for hash, store_name in packages.items():
        symlinks["store/" + store_name] = "../../+nix_extension+nix_pkg_" + hash
        
    build_content.append("nix_symlinks(")
    build_content.append("    name = \"symlinks\",")
    build_content.append("    symlinks = {")
    for src, target in symlinks.items():
        build_content.append("        \"%s\": \"%s\"," % (src, target))
    build_content.append("    },")
    build_content.append(")")
    build_content.append("")
    
    # Declare an individual filegroup for each symlink target
    for hash, store_name in packages.items():
        build_content.append("filegroup(")
        build_content.append("    name = \"%s\"," % hash)
        build_content.append("    srcs = [\":symlinks\", \"_dummy.txt\"],")
        build_content.append("    data = [\"@nix_pkg_%s//:files\"]," % hash)
        build_content.append("    visibility = [\"//visibility:public\"],")
        build_content.append(")")
        build_content.append("")
        
    repository_ctx.file("BUILD.bazel", "\n".join(build_content))
    repository_ctx.file("_dummy.txt", "dummy")

nix_store = repository_rule(
    implementation = _nix_store_impl,
    attrs = {
        "packages": attr.string_dict(mandatory = True),
    },
)
