def _nix_symlinks_impl(ctx):
    outputs = []
    for link_name, target in ctx.attr.symlinks.items():
        # Declare the unresolved symlink artifact
        out = ctx.actions.declare_symlink(link_name)
        
        # Materialize the unresolved symlink pointing to the target path string
        ctx.actions.symlink(
            output = out,
            target_path = target,
        )
        outputs.append(out)
        
    return [DefaultInfo(files = depset(outputs))]

nix_symlinks = rule(
    implementation = _nix_symlinks_impl,
    attrs = {
        "symlinks": attr.string_dict(
            doc = "A dictionary mapping symlink paths to their target paths relative to execroot (e.g. {'lib/libfoo.so': '../../../nix_pkg_hash_bar/lib/libbar.so'})"
        ),
    },
)

def _nix_symlink_impl(ctx):
    # Declare the unresolved symlink artifact with the exact target name
    out = ctx.actions.declare_symlink(ctx.label.name)
    
    # Materialize the unresolved symlink pointing to the target path string
    ctx.actions.symlink(
        output = out,
        target_path = ctx.attr.target,
    )
    return [DefaultInfo(files = depset([out]))]

nix_symlink = rule(
    implementation = _nix_symlink_impl,
    attrs = {
        "target": attr.string(mandatory = True),
    },
)

