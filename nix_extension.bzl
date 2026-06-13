# nix_extension.bzl

load("//:nix_import.bzl", "nix_import")
load("//:nix_store.bzl", "nix_store")
load("//:nix_unification.bzl", "nix_unification")

def _nix_extension_impl(ctx):
    # Read the JSON lockfile
    lock_path = ctx.path(Label("//:nix_lock.json"))
    lock_content = ctx.read(lock_path)
    lock_data = json.decode(lock_content)
    
    # 1. Declare the Nix repositories dynamically fetched from cache.nixos.org
    for hash, pkg in lock_data["resolved_packages"].items():
        nix_import(
            name = "nix_pkg_" + hash,
            hash = hash,
            pkg_name = pkg["pkg_name"],
        )
    
    # 2. Declare the nix_store forest containing the symlink mapping
    packages_dict = {}
    for hash, pkg in lock_data["resolved_packages"].items():
        packages_dict[hash] = pkg["store_name"]
        
    nix_store(
        name = "nix_store",
        packages = packages_dict,
    )

    # 3. Declare the unification repo
    nix_unification(
        name = "nix",
        lock_file = Label("//:nix_lock.json"),
    )

nix_extension = module_extension(
    implementation = _nix_extension_impl,
)
