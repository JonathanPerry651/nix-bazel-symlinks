# nix_unification.bzl

def _nix_unification_impl(repository_ctx):
    build_content = []
    build_content.append("load(\"@nix_bazel_links//:nix_binary.bzl\", \"nix_binary\")")
    build_content.append("")
    
    # 1. Hello wrapped binary
    build_content.append("nix_binary(")
    build_content.append("    name = \"hello\",")
    build_content.append("    binary = \"@nix_pkg_18mrc8i5l3r5xnxrv091x25nsnwa1xzp//:bin/hello\",")
    build_content.append("    linker = \"@nix_pkg_1bdzriipn18184zpwh2lfdabk2gqcgxn//:lib/ld-linux-aarch64.so.1\",")
    build_content.append("    lib_files = [")
    build_content.append("        \"@nix_pkg_7a3zsvzzm9ki2r3w2cl0mx12zjicinkj//:lib/libgcc_s.so.1\",")
    build_content.append("        \"@nix_pkg_f04zlspmsqzyv15kcxbn6mx4wb71a0jm//:lib/libidn2.so.0\",")
    build_content.append("        \"@nix_pkg_xag03kgklavhhq66qnac59pqxpxvjqga//:lib/libunistring.so.5\",")
    build_content.append("    ],")
    build_content.append("    additional_libs = [")
    build_content.append("        \"@nix_store//:18mrc8i5l3r5xnxrv091x25nsnwa1xzp\",")
    build_content.append("        \"@nix_store//:7a3zsvzzm9ki2r3w2cl0mx12zjicinkj\",")
    build_content.append("        \"@nix_store//:f04zlspmsqzyv15kcxbn6mx4wb71a0jm\",")
    build_content.append("        \"@nix_store//:xag03kgklavhhq66qnac59pqxpxvjqga\",")
    build_content.append("    ],")
    build_content.append("    visibility = [\"//visibility:public\"],")
    build_content.append(")")
    build_content.append("")
    
    # 2. Patchelf wrapped binary
    build_content.append("nix_binary(")
    build_content.append("    name = \"patchelf\",")
    build_content.append("    binary = \"@nix_pkg_4yp2n6439qwqa60hjyx4lx9550ckgvd9//:bin/patchelf\",")
    build_content.append("    linker = \"@nix_pkg_1bdzriipn18184zpwh2lfdabk2gqcgxn//:lib/ld-linux-aarch64.so.1\",")
    build_content.append("    lib_files = [")
    build_content.append("        \"@nix_pkg_7a3zsvzzm9ki2r3w2cl0mx12zjicinkj//:lib/libgcc_s.so.1\",")
    build_content.append("        \"@nix_pkg_7a3zsvzzm9ki2r3w2cl0mx12zjicinkj//:lib/libstdc++.so.6\",")
    build_content.append("    ],")
    build_content.append("    additional_libs = [")
    build_content.append("        \"@nix_store//:4yp2n6439qwqa60hjyx4lx9550ckgvd9\",")
    build_content.append("        \"@nix_store//:7a3zsvzzm9ki2r3w2cl0mx12zjicinkj\",")
    build_content.append("    ],")
    build_content.append("    visibility = [\"//visibility:public\"],")
    build_content.append(")")
    build_content.append("")
    
    # 3. Ripgrep wrapped binary
    build_content.append("nix_binary(")
    build_content.append("    name = \"ripgrep\",")
    build_content.append("    binary = \"@nix_pkg_n2jwjpmx2dg4cznyni372pm9y4a90yhv//:bin/rg\",")
    build_content.append("    linker = \"@nix_pkg_9w5r3pwfr5hvvr2lf1i71mz79qy86f7y//:lib/ld-linux-aarch64.so.1\",")
    build_content.append("    lib_files = [")
    build_content.append("        \"@nix_pkg_kpkqksnxdns56661qwszmzl710ybaici//:lib/libpcre2-8.so.0\",")
    build_content.append("    ],")
    build_content.append("    additional_libs = [")
    build_content.append("        \"@nix_store//:n2jwjpmx2dg4cznyni372pm9y4a90yhv\",")
    build_content.append("        \"@nix_store//:kpkqksnxdns56661qwszmzl710ybaici\",")
    build_content.append("        \"@nix_store//:9w5r3pwfr5hvvr2lf1i71mz79qy86f7y\",")
    build_content.append("        \"@nix_store//:gcjzri64yz2clwwlkay0wbarjbwq8yvp\",")
    build_content.append("        \"@nix_store//:3lbh75xpd3z1pcnxlrzfyaafgvziizw4\",")
    build_content.append("    ],")
    build_content.append("    visibility = [\"//visibility:public\"],")
    build_content.append(")")
    build_content.append("")
    
    # 4. Aliases for raw entrypoint binaries
    build_content.append("alias(")
    build_content.append("    name = \"hello_raw\",")
    build_content.append("    actual = \"@nix_pkg_18mrc8i5l3r5xnxrv091x25nsnwa1xzp//:bin/hello\",")
    build_content.append("    visibility = [\"//visibility:public\"],")
    build_content.append(")")
    build_content.append("")
    
    build_content.append("alias(")
    build_content.append("    name = \"patchelf_raw\",")
    build_content.append("    actual = \"@nix_pkg_4yp2n6439qwqa60hjyx4lx9550ckgvd9//:bin/patchelf\",")
    build_content.append("    visibility = [\"//visibility:public\"],")
    build_content.append(")")
    build_content.append("")
    
    build_content.append("alias(")
    build_content.append("    name = \"ripgrep_raw\",")
    build_content.append("    actual = \"@nix_pkg_n2jwjpmx2dg4cznyni372pm9y4a90yhv//:bin/rg\",")
    build_content.append("    visibility = [\"//visibility:public\"],")
    build_content.append(")")
    build_content.append("")
    
    build_content.append("alias(")
    build_content.append("    name = \"glibc_linker\",")
    build_content.append("    actual = \"@nix_pkg_1bdzriipn18184zpwh2lfdabk2gqcgxn//:lib/ld-linux-aarch64.so.1\",")
    build_content.append("    visibility = [\"//visibility:public\"],")
    build_content.append(")")
    build_content.append("")
    
    repository_ctx.file("BUILD.bazel", "\n".join(build_content))

nix_unification = repository_rule(
    implementation = _nix_unification_impl,
)
