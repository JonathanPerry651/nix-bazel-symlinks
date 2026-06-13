# nix_import.bzl

def _nix_import_impl(repository_ctx):
    hash = repository_ctx.attr.hash
    pkg_name = repository_ctx.attr.pkg_name
    
    # 1. Locate the nix_extractor binary
    extractor_path = repository_ctx.path(repository_ctx.attr._extractor)
    
    # 2. Execute extractor to fetch and unpack NAR
    result = repository_ctx.execute([
        extractor_path,
        hash,
        repository_ctx.path("."),
    ])
    
    if result.return_code != 0:
        fail("nix_extractor failed for hash %s: %s\n%s" % (hash, result.stderr, result.stdout))
        
    # 3. Read the generated metadata JSON
    metadata_bytes = repository_ctx.read("_nix_metadata.json")
    metadata = json.decode(metadata_bytes)
    
    store_path = metadata["store_path"]
    references = metadata["references"]
    symlinks = metadata["symlinks"]
    if symlinks == None:
        symlinks = []
    
    # Extract store path name (e.g. 18mrc...-hello-2.12.3)
    store_path_name = store_path.split("/")[-1]
    
    # 4. Generate the BUILD.bazel file
    build_content = []
    build_content.append("load(\"@nix_bazel_links//:nix_symlink.bzl\", \"nix_symlink\")")
    build_content.append("")
    build_content.append("exports_files(")
    build_content.append("    glob([\"**/*\"], exclude = [\"BUILD.bazel\", \"_nix_metadata.json\"]),")
    build_content.append("    visibility = [\"//visibility:public\"],")
    build_content.append(")")
    build_content.append("")
    
    # Declare the unresolved symlinks
    symlink_map = {}
    for link in symlinks:
        src = link["path"]
        target = link["target"]
        
        # Rewrite absolute Nix store paths to go through our nix_store forest
        # e.g. /nix/store/hash-name/... -> ../../+nix_extension+nix_store/store/hash-name/...
        if target.startswith("/nix/store/"):
            target = "../../+nix_extension+nix_store/store/" + target[len("/nix/store/"):]
            
        symlink_map[src] = target
        
    symlink_labels = []
    for src, target in symlink_map.items():
        build_content.append("nix_symlink(")
        build_content.append("    name = \"%s\"," % src)
        build_content.append("    target = \"%s\"," % target)
        build_content.append("    visibility = [\"//visibility:public\"],")
        build_content.append(")")
        build_content.append("")
        symlink_labels.append("\":%s\"" % src)
        
    build_content.append("filegroup(")
    build_content.append("    name = \"symlinks\",")
    build_content.append("    srcs = [%s]," % (", ".join(symlink_labels)))
    build_content.append("    visibility = [\"//visibility:public\"],")
    build_content.append(")")
    build_content.append("")
    
    # Map raw dynamic references to Bazel dependencies
    if references == None:
        references = []
    dep_labels = []
    for ref in references:
        ref_hash = ref.split("/")[-1].split("-")[0]
        if ref_hash == hash:
            continue
        # Map glibc and other dependencies to their corresponding repo rules
        dep_labels.append("\"@nix_pkg_%s//:files\"" % ref_hash)
        
    build_content.append("filegroup(")
    build_content.append("    name = \"files\",")
    build_content.append("    srcs = glob([\"**/*\"], exclude = [\"BUILD.bazel\", \"_nix_metadata.json\"]) + [\":symlinks\"],")
    build_content.append("    data = [%s]," % (", ".join(dep_labels)))
    build_content.append("    visibility = [\"//visibility:public\"],")
    build_content.append(")")
    
    repository_ctx.file("BUILD.bazel", "\n".join(build_content))
    
    # Save the store path name so the central forest repository can read it!
    repository_ctx.file("_store_name.txt", store_path_name)

nix_import = repository_rule(
    implementation = _nix_import_impl,
    attrs = {
        "hash": attr.string(mandatory = True),
        "pkg_name": attr.string(mandatory = True),
        "_extractor": attr.label(default = "//:nix_extractor"),
    },
)
