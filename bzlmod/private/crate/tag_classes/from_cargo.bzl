load("//crate_universe/private:crates_vendor.bzl", "CRATES_VENDOR_ATTRS", "write_config_file", "write_splicing_manifest", _crates_vendor_repo_rule = "crates_vendor")

from_cargo = tag_class(
    doc = "Generates a repo <mod_name>_crates",
    attrs = dict(
        suffix = attr.string(
            doc = "If provided, instead generates a repo <mod_name>_crates_<suffix>. " +
            "This can help avoid conflicts if you declare multiple from_cargo in a single module."
        ),
        cargo_lockfile = CRATES_VENDOR_ATTRS["cargo_lockfile"],
        manifests = CRATES_VENDOR_ATTRS["manifests"],
        cargo_config = CRATES_VENDOR_ATTRS["cargo_config"],
        generate_binaries = CRATES_VENDOR_ATTRS["generate_binaries"],
        generate_build_scripts = CRATES_VENDOR_ATTRS["generate_build_scripts"],
        supported_platform_triples = CRATES_VENDOR_ATTRS["supported_platform_triples"],
    )
)
