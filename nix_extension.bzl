# nix_extension.bzl

load("//:nix_import.bzl", "nix_import")
load("//:nix_store.bzl", "nix_store")

def _nix_extension_impl(ctx):
    # 1. Declare the 8 Nix repositories dynamically fetched from cache.nixos.org
    nix_import(
        name = "nix_pkg_18mrc8i5l3r5xnxrv091x25nsnwa1xzp",
        hash = "18mrc8i5l3r5xnxrv091x25nsnwa1xzp",
        pkg_name = "hello",
    )
    
    nix_import(
        name = "nix_pkg_4yp2n6439qwqa60hjyx4lx9550ckgvd9",
        hash = "4yp2n6439qwqa60hjyx4lx9550ckgvd9",
        pkg_name = "patchelf",
    )
    
    nix_import(
        name = "nix_pkg_1bdzriipn18184zpwh2lfdabk2gqcgxn",
        hash = "1bdzriipn18184zpwh2lfdabk2gqcgxn",
        pkg_name = "glibc",
    )
    
    nix_import(
        name = "nix_pkg_7a3zsvzzm9ki2r3w2cl0mx12zjicinkj",
        hash = "7a3zsvzzm9ki2r3w2cl0mx12zjicinkj",
        pkg_name = "gcc-lib",
    )
    
    nix_import(
        name = "nix_pkg_l5ypyhyv1df633ldrdj8fyhnxaqqw6s7",
        hash = "l5ypyhyv1df633ldrdj8fyhnxaqqw6s7",
        pkg_name = "gcc-libgcc",
    )
    
    nix_import(
        name = "nix_pkg_f04zlspmsqzyv15kcxbn6mx4wb71a0jm",
        hash = "f04zlspmsqzyv15kcxbn6mx4wb71a0jm",
        pkg_name = "libidn2",
    )
    
    nix_import(
        name = "nix_pkg_xag03kgklavhhq66qnac59pqxpxvjqga",
        hash = "xag03kgklavhhq66qnac59pqxpxvjqga",
        pkg_name = "libunistring",
    )
    
    nix_import(
        name = "nix_pkg_xzs7w65n77a94hmpwkfsnwqkj2k5akn4",
        hash = "xzs7w65n77a94hmpwkfsnwqkj2k5akn4",
        pkg_name = "xgcc-libgcc",
    )
    
    nix_import(
        name = "nix_pkg_n2jwjpmx2dg4cznyni372pm9y4a90yhv",
        hash = "n2jwjpmx2dg4cznyni372pm9y4a90yhv",
        pkg_name = "ripgrep",
    )
    
    nix_import(
        name = "nix_pkg_kpkqksnxdns56661qwszmzl710ybaici",
        hash = "kpkqksnxdns56661qwszmzl710ybaici",
        pkg_name = "pcre2",
    )
    
    nix_import(
        name = "nix_pkg_9w5r3pwfr5hvvr2lf1i71mz79qy86f7y",
        hash = "9w5r3pwfr5hvvr2lf1i71mz79qy86f7y",
        pkg_name = "glibc-2.35",
    )
    
    nix_import(
        name = "nix_pkg_gcjzri64yz2clwwlkay0wbarjbwq8yvp",
        hash = "gcjzri64yz2clwwlkay0wbarjbwq8yvp",
        pkg_name = "libidn2-2.3.2",
    )
    
    nix_import(
        name = "nix_pkg_3lbh75xpd3z1pcnxlrzfyaafgvziizw4",
        hash = "3lbh75xpd3z1pcnxlrzfyaafgvziizw4",
        pkg_name = "libunistring-1.0",
    )

    # 2. Declare the nix_store forest containing the symlink mapping
    nix_store(
        name = "nix_store",
        packages = {
            "18mrc8i5l3r5xnxrv091x25nsnwa1xzp": "18mrc8i5l3r5xnxrv091x25nsnwa1xzp-hello-2.12.3",
            "4yp2n6439qwqa60hjyx4lx9550ckgvd9": "4yp2n6439qwqa60hjyx4lx9550ckgvd9-patchelf-0.15.2",
            "1bdzriipn18184zpwh2lfdabk2gqcgxn": "1bdzriipn18184zpwh2lfdabk2gqcgxn-glibc-2.42-61",
            "7a3zsvzzm9ki2r3w2cl0mx12zjicinkj": "7a3zsvzzm9ki2r3w2cl0mx12zjicinkj-gcc-15.2.0-lib",
            "l5ypyhyv1df633ldrdj8fyhnxaqqw6s7": "l5ypyhyv1df633ldrdj8fyhnxaqqw6s7-gcc-15.2.0-libgcc",
            "f04zlspmsqzyv15kcxbn6mx4wb71a0jm": "f04zlspmsqzyv15kcxbn6mx4wb71a0jm-libidn2-2.3.8",
            "xag03kgklavhhq66qnac59pqxpxvjqga": "xag03kgklavhhq66qnac59pqxpxvjqga-libunistring-1.4.2",
            "xzs7w65n77a94hmpwkfsnwqkj2k5akn4": "xzs7w65n77a94hmpwkfsnwqkj2k5akn4-xgcc-15.2.0-libgcc",
            "n2jwjpmx2dg4cznyni372pm9y4a90yhv": "n2jwjpmx2dg4cznyni372pm9y4a90yhv-ripgrep-13.0.0",
            "kpkqksnxdns56661qwszmzl710ybaici": "kpkqksnxdns56661qwszmzl710ybaici-pcre2-10.40",
            "9w5r3pwfr5hvvr2lf1i71mz79qy86f7y": "9w5r3pwfr5hvvr2lf1i71mz79qy86f7y-glibc-2.35-224",
            "gcjzri64yz2clwwlkay0wbarjbwq8yvp": "gcjzri64yz2clwwlkay0wbarjbwq8yvp-libidn2-2.3.2",
            "3lbh75xpd3z1pcnxlrzfyaafgvziizw4": "3lbh75xpd3z1pcnxlrzfyaafgvziizw4-libunistring-1.0",
        },
    )

nix_extension = module_extension(
    implementation = _nix_extension_impl,
)
