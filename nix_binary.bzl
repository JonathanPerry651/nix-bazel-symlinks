# nix_binary.bzl

def _runfiles_path(ctx, file):
    if file.short_path.startswith("../"):
        return file.short_path[3:]
    else:
        return ctx.workspace_name + "/" + file.short_path

def _nix_binary_impl(ctx):
    binary_file = ctx.file.binary
    linker_file = ctx.file.linker
    
    # Declare the launcher script
    launcher = ctx.actions.declare_file(ctx.label.name)
    
    script_content = []
    script_content.append("#!/bin/bash")
    script_content.append("set -euo pipefail")
    script_content.append("")
    script_content.append("# 1. Locate the physical .runfiles directory robustly")
    script_content.append("if [ -n \"${RUNFILES_DIR:-}\" ]; then")
    script_content.append("    if [[ \"${RUNFILES_DIR}\" == */_main || \"${RUNFILES_DIR}\" == */main || \"${RUNFILES_DIR}\" == */nix_bazel_links ]]; then")
    script_content.append("        RUNFILES_ROOT=\"$(dirname \"${RUNFILES_DIR}\")\"")
    script_content.append("    else")
    script_content.append("        RUNFILES_ROOT=\"${RUNFILES_DIR}\"")
    script_content.append("    fi")
    script_content.append("else")
    script_content.append("    SELF_DIR=\"$(cd \"$(dirname \"${BASH_SOURCE[0]}\")\" && pwd)\"")
    script_content.append("    RUNFILES_ROOT=\"${SELF_DIR}/$(basename \"${BASH_SOURCE[0]}\").runfiles\"")
    script_content.append("fi")
    script_content.append("RUNFILES_ROOT=\"${RUNFILES_ROOT}/\"")
    script_content.append("")
    script_content.append("# 2. Helper to resolve file paths across execution environments (bazel run, test, action)")
    script_content.append("find_file() {")
    script_content.append("    local rf_path=\"$1\"")
    script_content.append("    # Try physical runfiles directory")
    script_content.append("    if [ -d \"${RUNFILES_ROOT}\" ] && [ -f \"${RUNFILES_ROOT}${rf_path}\" ]; then")
    script_content.append("        echo \"${RUNFILES_ROOT}${rf_path}\"")
    script_content.append("        return 0")
    script_content.append("    fi")
    script_content.append("    # Try runfiles manifest")
    script_content.append("    if [ -f \"${RUNFILES_MANIFEST_FILE:-}\" ]; then")
    script_content.append("        local manifest_match")
    script_content.append("        manifest_match=$(grep -m 1 \"^${rf_path} \" \"${RUNFILES_MANIFEST_FILE}\" | cut -d' ' -f2-)")
    script_content.append("        if [ -n \"${manifest_match}\" ] && [ -f \"${manifest_match}\" ]; then")
    script_content.append("            echo \"${manifest_match}\"")
    script_content.append("            return 0")
    script_content.append("        fi")
    script_content.append("    fi")
    script_content.append("    # Try execution root path mapping")
    script_content.append("    local exec_root_path=\"\"")
    script_content.append("    if [[ \"${rf_path}\" == _main/* ]]; then")
    script_content.append("        exec_root_path=\"${rf_path#_main/}\"")
    script_content.append("    elif [[ \"${rf_path}\" == nix_bazel_links/* ]]; then")
    script_content.append("        exec_root_path=\"${rf_path#nix_bazel_links/}\"")
    script_content.append("    else")
    script_content.append("        exec_root_path=\"external/${rf_path}\"")
    script_content.append("    fi")
    script_content.append("    # Check relative to current working directory (execution root)")
    script_content.append("    if [ -f \"${exec_root_path}\" ]; then")
    script_content.append("        echo \"$(pwd)/${exec_root_path}\"")
    script_content.append("        return 0")
    script_content.append("    fi")
    script_content.append("    # Check relative to script's execution root")
    script_content.append("    local dir")
    script_content.append("    dir=\"$(cd \"$(dirname \"${BASH_SOURCE[0]}\")\" && pwd)\"")
    script_content.append("    while [ \"${dir}\" != \"/\" ]; do")
    script_content.append("        if [ -d \"${dir}/bazel-out\" ] || [ -d \"${dir}/external\" ]; then")
    script_content.append("            if [ -f \"${dir}/${exec_root_path}\" ]; then")
    script_content.append("                echo \"${dir}/${exec_root_path}\"")
    script_content.append("                return 0")
    script_content.append("            fi")
    script_content.append("        fi")
    script_content.append("        dir=\"$(dirname \"${dir}\")\"")
    script_content.append("    done")
    script_content.append("    # Fallback to RUNFILES_ROOT")
    script_content.append("    echo \"${RUNFILES_ROOT}${rf_path}\"")
    script_content.append("}")
    script_content.append("")
    
    linker_runfiles_path = _runfiles_path(ctx, linker_file)
    binary_runfiles_path = _runfiles_path(ctx, binary_file)
    
    script_content.append("# 3. Define absolute linker and binary paths inside runfiles")
    script_content.append("LD_SO=$(find_file \"%s\")" % linker_runfiles_path)
    script_content.append("BINARY=$(find_file \"%s\")" % binary_runfiles_path)
    script_content.append("")
    script_content.append("# 4. Build the library paths dynamically using absolute runfiles paths")
    script_content.append("LIB_PATHS=()")
    script_content.append("LIB_PATHS+=(\"$(dirname \"${LD_SO}\")\")")
    
    for file in ctx.files.lib_files:
        runfiles_path = _runfiles_path(ctx, file)
        script_content.append("LIB_FILE=$(find_file \"%s\")" % runfiles_path)
        script_content.append("LIB_PATHS+=(\"$(dirname \"${LIB_FILE}\")\")")
        
    script_content.append("")
    script_content.append("IFS=:; LIB_PATH=\"${LIB_PATHS[*]}\"; unset IFS")
    script_content.append("")
    script_content.append("# 5. Execute binary via dynamic linker")
    script_content.append("exec \"${LD_SO}\" --library-path \"${LIB_PATH}\" \"${BINARY}\" \"$@\"")
    
    ctx.actions.write(
        output = launcher,
        content = "\n".join(script_content),
        is_executable = True,
    )
    
    # Propagate runfiles transitively
    additional_libs_files = depset(transitive = [dep[DefaultInfo].files for dep in ctx.attr.additional_libs])
    lib_files_files = depset(transitive = [dep[DefaultInfo].files for dep in ctx.attr.lib_files])
    
    runfiles = ctx.runfiles(
        files = [binary_file, linker_file],
        transitive_files = depset(transitive = [additional_libs_files, lib_files_files]),
    )
    
    # Merge runfiles from dependencies to propagate transitives
    for dep in ctx.attr.lib_files:
        runfiles = runfiles.merge(dep[DefaultInfo].default_runfiles)
        
    for dep in ctx.attr.additional_libs:
        runfiles = runfiles.merge(dep[DefaultInfo].default_runfiles)
        
    # Merge runfiles from the Bash runfiles library
    runfiles = runfiles.merge(ctx.attr._runfiles_lib[DefaultInfo].default_runfiles)
    
    return [
        DefaultInfo(
            executable = launcher,
            runfiles = runfiles,
        )
    ]

nix_binary = rule(
    implementation = _nix_binary_impl,
    attrs = {
        "binary": attr.label(mandatory = True, allow_single_file = True),
        "linker": attr.label(mandatory = True, allow_single_file = True),
        "lib_files": attr.label_list(mandatory = True),
        "additional_libs": attr.label_list(default = []),
        "_runfiles_lib": attr.label(
            default = Label("@bazel_tools//tools/bash/runfiles"),
        ),
    },
    executable = True,
)
