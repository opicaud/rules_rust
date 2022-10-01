"Module extensions for using rules_rust with bzlmod"

load("//rust:repositories.bzl", "rust_register_toolchains")
load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")

def _toolchains_impl(ctx):
    mod = ctx.modules[0]
    for toolchain in mod.tags.toolchain:
        rust_register_toolchains(edition = toolchain.edition, register_toolchains = False)

toolchains_toolchain = tag_class(attrs = {"edition": attr.string()})
toolchains = module_extension(
    implementation = _toolchains_impl,
    tag_classes = {"toolchain": toolchains_toolchain},
)

def _create_build_file_content(name):
    return """
load("@rules_rust//rust/private:rust.bzl", "rust_library_without_process_wrapper")

rust_library_without_process_wrapper(
    name = "{}",
    srcs = glob(["src/*.rs"]),
    edition = "2018",
    visibility = ["@rules_rust//util/process_wrapper:__pkg__"],
)
""".format(name)

def _raw_cargo_impl(ctx):
    for mod in ctx.modules:
        for crate in mod.tags.crate:
            http_archive(
                name = "raw_cargo_{}_{}".format(crate.name, crate.version.replace(".", "_")),
                sha256 = crate.sha256,
                url = "https://crates.io/api/v1/crates/{}/{}/download".format(crate.name, crate.version),
                strip_prefix = "{}-{}".format(crate.name, crate.version),
                type = "tar.gz",
                build_file_content = _create_build_file_content(crate.name),
            )

raw_cargo_crate = tag_class(attrs = {"name": attr.string(), "version": attr.string(), "sha256": attr.string()})
raw_cargo = module_extension(
    implementation = _raw_cargo_impl,
    tag_classes = {"crate": raw_cargo_crate},
)
