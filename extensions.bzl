"Module extensions for using rules_rust with bzlmod"

load("//rust:repositories.bzl", "rust_register_toolchains")

def _toolchains_impl(ctx):
    mod = ctx.modules[0]
    for toolchain in mod.tags.toolchain:
        rust_register_toolchains(edition = toolchain.edition, register_toolchains = False)

toolchains_toolchain = tag_class(attrs = {"edition": attr.string()})
toolchains = module_extension(
    implementation = _toolchains_impl,
    tag_classes = {"toolchain": toolchains_toolchain},
)
