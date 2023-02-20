load("//crate_universe:deps_bootstrap.bzl", _cargo_bazel_bootstrap_repo_rule = "cargo_bazel_bootstrap")
load("//rust/private:common.bzl", "rust_common")
load(
    "//rust/private:repository_utils.bzl",
    "DEFAULT_EXTRA_TARGET_TRIPLES",
    "DEFAULT_NIGHTLY_VERSION",
    "DEFAULT_STATIC_RUST_URL_TEMPLATES",
)
load("//rust:repositories.bzl", "rust_register_toolchains", "rust_toolchain_tools_repository")

def generate_uid(toolchain):
    """
    Generates a UID representing a toolchain. This allows us to share toolchains
    between different modules if they happen to use the same configuration.
    """
    unique_config = [
        toolchain.allocator_library,
        str(toolchain.dev_components),
        toolchain.edition,
        toolchain.rust_analyzer_version,
        toolchain.rustfmt_version,
    ]
    unique_config.append("sha256s")
    for k, v in toolchain.sha256s:
        unique_config.append(k)
        unique_config.append(v)
    unique_config.append("extra_target_triples")
    unique_config.extend(toolchain.extra_target_triples)
    unique_config.append("urls")
    unique_config.extend(toolchain.urls)
    unique_config.append("versions")
    unique_config.extend(toolchain.versions)
    return hash("".join([str(hash(i)) for i in unique_config]))

def _toolchains_impl(module_ctx):
    toolchains = {}
    for mod in module_ctx.modules:
        for toolchain in mod.tags.toolchain:
            repo_name = "%s_rust_toolchains" % mod.name
            if toolchain.suffix:
                repo_name += "_" + toolchain.suffix

            namespace = "internal_%d" % generate_uid(toolchain)
            if namespace not in toolchains:
                toolchains[namespace] = (toolchain, [])
            toolchains[namespace][1].append("%s_rust_toolchains" % mod.name)

    for namespace, (toolchain, repos) in toolchains.items():
        rust_register_toolchains(
            hub_repos = repos,
            repo_namespace = namespace,
            register_toolchains = False,
            edition = toolchain.edition,
            allocator_library = toolchain.allocator_library,
            rustfmt_version = toolchain.rustfmt_version,
            sha256s = toolchain.sha256s,
            extra_target_triples = toolchain.extra_target_triples,
            urls = toolchain.urls,
            version = toolchain.versions,
        )

toolchains_toolchain = tag_class(
    doc = "Generates a repo '<module_name>_rust_toolchain",
    attrs = dict(
        suffix = attr.string(
            doc = "If provided, instead of generating <module_name>_rust_toolchain, " +
                  "generates <module_name>_rust_toolchain_<suffix>.\n" +
                  "This is required to generate multiple toolchains in the same module.",
        ),
        allocator_library = attr.string(),
        dev_components = attr.bool(default = False),
        edition = attr.string(),
        extra_target_triples = attr.string_list(default = DEFAULT_EXTRA_TARGET_TRIPLES),
        rust_analyzer_version = attr.string(),
        rustfmt_version = attr.string(default = DEFAULT_NIGHTLY_VERSION),
        sha256s = attr.string_dict(),
        urls = attr.string_list(default = DEFAULT_STATIC_RUST_URL_TEMPLATES),
        versions = attr.string_list(default = []),
    ),
)

toolchains = module_extension(
    implementation = _toolchains_impl,
    tag_classes = dict(
        toolchain = toolchains_toolchain,
    ),
)
