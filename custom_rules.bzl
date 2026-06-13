# custom_rules.bzl

def _nix_hello_gen_impl(ctx):
    out_file = ctx.actions.declare_file(ctx.attr.out)
    
    # Run the hello nix_binary tool to generate a greeting
    ctx.actions.run_shell(
        outputs = [out_file],
        inputs = [],
        tools = [ctx.executable.hello_tool],
        command = "$1 > $2",
        arguments = [ctx.executable.hello_tool.path, out_file.path],
        mnemonic = "NixHello",
        progress_message = "Generating hello message using Nix hello...",
    )
    
    return [DefaultInfo(files = depset([out_file]))]

nix_hello_gen = rule(
    implementation = _nix_hello_gen_impl,
    attrs = {
        "hello_tool": attr.label(
            default = Label("//:hello"),
            executable = True,
            cfg = "exec",
        ),
        "out": attr.string(mandatory = True),
    },
)


def _nix_ripgrep_search_impl(ctx):
    out_file = ctx.actions.declare_file(ctx.attr.out)
    
    # Run ripgrep search on the input file
    # We append || true because ripgrep returns exit code 1 if no matches are found,
    # which would otherwise fail the Bazel action.
    ctx.actions.run_shell(
        outputs = [out_file],
        inputs = [ctx.file.src],
        tools = [ctx.executable.rg_tool],
        command = "$1 \"$2\" \"$3\" > \"$4\" || true",
        arguments = [
            ctx.executable.rg_tool.path,
            ctx.attr.pattern,
            ctx.file.src.path,
            out_file.path,
        ],
        mnemonic = "NixRipgrep",
        progress_message = "Searching for pattern '%s' using Nix ripgrep..." % ctx.attr.pattern,
    )
    
    return [DefaultInfo(files = depset([out_file]))]

nix_ripgrep_search = rule(
    implementation = _nix_ripgrep_search_impl,
    attrs = {
        "rg_tool": attr.label(
            default = Label("//:ripgrep"),
            executable = True,
            cfg = "exec",
        ),
        "src": attr.label(mandatory = True, allow_single_file = True),
        "pattern": attr.string(mandatory = True),
        "out": attr.string(mandatory = True),
    },
)


def _nix_patchelf_inspect_impl(ctx):
    out_file = ctx.actions.declare_file(ctx.attr.out)
    
    # Run patchelf to print the interpreter of the given binary
    ctx.actions.run_shell(
        outputs = [out_file],
        inputs = [ctx.file.binary_to_inspect],
        tools = [ctx.executable.patchelf_tool],
        command = "$1 --print-interpreter \"$2\" > \"$3\"",
        arguments = [
            ctx.executable.patchelf_tool.path,
            ctx.file.binary_to_inspect.path,
            out_file.path,
        ],
        mnemonic = "NixPatchelfInspect",
        progress_message = "Inspecting dynamic linker of %s using Nix patchelf..." % ctx.file.binary_to_inspect.short_path,
    )
    
    return [DefaultInfo(files = depset([out_file]))]

nix_patchelf_inspect = rule(
    implementation = _nix_patchelf_inspect_impl,
    attrs = {
        "patchelf_tool": attr.label(
            default = Label("//:patchelf"),
            executable = True,
            cfg = "exec",
        ),
        "binary_to_inspect": attr.label(mandatory = True, allow_single_file = True),
        "out": attr.string(mandatory = True),
    },
)
