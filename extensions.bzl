"Module extensions for using rules_rust with bzlmod"

load("//cargo/private:cargo_utils.bzl", _rust_get_rust_tools = "get_rust_tools")
load("//crate_universe/private:common_utils.bzl", "get_rust_tools")
load("//crate_universe/private:crates_vendor.bzl", "CRATES_VENDOR_ATTRS", "write_config_file", "write_splicing_manifest", _crates_vendor_repo_rule = "crates_vendor")
load("//crate_universe/private:crates_repository.bzl", "crates_repository")
load("//crate_universe:deps_bootstrap.bzl", _cargo_bazel_bootstrap_repo_rule = "cargo_bazel_bootstrap")
load("//crate_universe:defs.bzl", "crate")
load("//rust:repositories.bzl", "rust_register_toolchains")
load("//rust/platform:triple.bzl", "get_host_triple")
load("//rust:defs.bzl", "rust_common")
load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")
load("@bazel_tools//tools/build_defs/repo:git.bzl", "new_git_repository")

crate_annotation = crate.annotation

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

def _crate_to_repo_name(name, version):
    return "raw_cargo_{}_{}".format(name, version.replace(".", "_"))

def _raw_cargo_impl(ctx):
    for mod in ctx.modules:
        for crate in mod.tags.crate:
            http_archive(
                name = _crate_to_repo_name(crate.name, crate.version),
                sha256 = crate.sha256,
                url = "https://crates.io/api/v1/crates/{}/{}/download".format(crate.name, crate.version),
                strip_prefix = "{}-{}".format(crate.name, crate.version),
                type = "tar.gz",
                build_file_content = _create_build_file_content(crate.name),
            )

raw_cargo_crate = tag_class(attrs = {"name": attr.string(), "version": attr.string(), "sha256": attr.string()})
crate_config = tag_class(attrs = {"name": attr.string(), "version": attr.string(), "sha256": attr.string()})
raw_cargo = module_extension(
    implementation = _raw_cargo_impl,
    tag_classes = {"crate": raw_cargo_crate},
)

def _cargo_bazel_bootstrap_impl(module_ctx):
    _cargo_bazel_bootstrap_repo_rule()

cargo_bazel_bootstrap_tag = tag_class(attrs = {})
cargo_bazel_bootstrap = module_extension(
    implementation = _cargo_bazel_bootstrap_impl,
    tag_classes = {"cargo_bazel_bootstrap": cargo_bazel_bootstrap_tag},
)

def _create_repo_impl(repo_ctx):
    for path, target in repo_ctx.attr.files.items():
        repo_ctx.symlink(target, path)

create_repo = repository_rule(
    implementation = _create_repo_impl,
    attrs = dict(
        files = attr.string_dict(mandatory = True)
    ),
)

# Note that between separate invocations, nothing is shared.
# If you want that, use a cargo workspace and invoke it once for the whole
# workspace.
# Example usage:
# crates_vendor(name = "foo_deps", manifests = ["//foo:Cargo.toml"], cargo_lockfile = "//foo:Cargo.lock")
# crates_vendor(name = "bar_deps", manifests = ["//bar:Cargo.toml"], cargo_lockfile = "//bar:Cargo.lock")
# Where foo/Cargo.toml contains anyhow = {version = "1.2.3"}
# And   bar/Cargo.toml contains anyhow = {version = "1.2.3", features = ["backtrace"]}
# Generates 3 repos:
# @anyhow_1.2.3_sources: http_archive for anyhow
# @foo_deps//:anyhow, which builds @anyhow_1.2.3_sources with no features
# @bar_deps//:anyhow, which builds @anyhow_1.2.3_sources with backtrace
def _crates_vendor_impl(module_ctx):
    # Required to analyze cargo.toml & cargo.lock files.
    _cargo_bazel_bootstrap_repo_rule()

    rustc_template = "@rust_{system}_{arch}__{triple}_tools//:bin/{tool}"
    cargo_template = "@rust_{system}_{arch}__{triple}_tools//:bin/{tool}"
    # Determine the current host's platform triple
    host_triple = get_host_triple(module_ctx)
    # Locate Rust tools (cargo, rustc)
    tools = _rust_get_rust_tools(
        cargo_template = cargo_template,
        rustc_template = rustc_template,
        host_triple  = host_triple,
        version = rust_common.default_version,
    )

    lockfiles = {}

    # Use Dict[string, None] because set isn't supported.
    for mod in module_ctx.modules:
        mod_path = module_ctx.path(mod.name)
        repo_name = "crates_" + str(mod.name)

        for repo in mod.tags.crates_vendor:
            annotations_by_crate_out = {}
            if repo.annotations_file:
                annotations_by_crate = json.decode(module_ctx.read(repo.annotations_file))
                for crate, annotations in annotations_by_crate.items():
                    annotations_out = []
                    for annotation in annotations:
                        annotations_out.append(crate_annotation(**annotation))
                    annotations_by_crate_out[crate] = annotations_out

            def write_data_file(ctx, name, data):
                path = mod_path.get_child(name)
                module_ctx.file(path, content = data, executable = False)
                return path

            config_file = write_config_file(
                module_ctx,
                regen_command = "Update the lockfile",
                mode = "bzlmod",
                annotations = annotations_by_crate_out,
                generate_build_scripts = repo.generate_build_scripts,
                supported_platform_triples = repo.supported_platform_triples,
                repository_name = repo_name,
                output_pkg = repo_name,
                workspace_name = repo_name,
                write_data_file = write_data_file,
            )



            def manifest_to_path(manifest):
                return module_ctx.path(manifest)

            manifests = {module_ctx.path(m): m for m in repo.manifests}
            splicing_manifest = write_splicing_manifest(
                module_ctx,
                packages = repo.packages,
                splicing_config = repo.splicing_config,
                cargo_config = repo.cargo_config,
                manifests = {str(p): str(l) for p, l in manifests.items()},
                write_data_file = write_data_file,
                manifest_to_path = manifest_to_path,
            )

            lockfile_path = module_ctx.path(repo.lockfile)

            args = [
                module_ctx.path(Label("@cargo_bazel_bootstrap//:cargo-bazel")),
                "generate",
                "--cargo-lockfile",
                module_ctx.path(repo.cargo_lockfile),
                "--config",
                config_file,
                "--splicing-manifest",
                splicing_manifest,
                "--repository-dir",
                mod_path,
                "--cargo",
                module_ctx.path(tools.cargo),
                "--rustc",
                module_ctx.path(tools.rustc),
                "--lockfile",
                lockfile_path,
            ]
            # TODO: remove the lockfile object. Generate this in the module extension.
            print(" ".join([str(x) for x in args]))
            result = module_ctx.execute(args)
            if result.return_code != 0:
                if result.stdout:
                    print("Stdout:", result.stdout)
                fail("Cargo-bazel returned with exit code %d:\n%s" % (result.return_code, result.stderr))

            crates_dir = mod_path.get_child(repo_name)
            create_repo(
                name = repo_name,
                files = {
                    "BUILD.bazel": str(crates_dir.get_child("BUILD.bazel")),
                    "defs.bzl": str(crates_dir.get_child("defs.bzl")),
                }
            )

            contents = json.decode(module_ctx.read(lockfile_path))

            for crate in contents["crates"].values():
                repo = crate["repository"]
                if repo == None:
                    continue
                name = crate["name"]
                version = crate["version"]
                crate_repo_name = "%s__%s-%s" % (repo_name, name, version)

                build_file_content = module_ctx.read(crates_dir.get_child("BUILD.%s-%s.bazel" % (name, version)))
                if "Http" in repo:
                    # Replicates repo_http.j2
                    http_archive(
                        name = crate_repo_name,
                        # TODO: patch_args
                        # TODO: patch_tool
                        # TODO: patches
                        sha256 = repo["Http"]["sha256"],
                        type = "tar.gz",
                        urls = [repo["Http"]["url"]],
                        strip_prefix = "%s-%s" % (crate["name"], crate["version"]),
                        build_file_content = build_file_content,
                    )
                elif "Git" in repo:
                    # Replicates repo_git.j2
                    new_git_repository(
                        name = crate_repo_name,
                        # TODO: commit, tag, branch
                        init_submodules = True,
                        # TODO: patch_args, patch_tool, patches, shallow_since
                        remote = repo["Git"]["remote"],
                        build_file_content = build_file_content,
                        # TODO: strip_prefix
                    )
                else:
                    fail("Invalid repo: expected Http or Git to exist for crate %s-%s, got %s" % (name, version, repo))

crates_vendor_tag = tag_class(attrs = dict(
    # When not using bzlmod, we pass in a struct, but we have no way of
    # referencing this struct from module.bazel.
    # TODO: investigate turning annotations into a tag class.
    annotations_file = attr.label(allow_single_file = True),

    # TODO: these fail for the same reason we can't use annotations_file.
    packages = CRATES_VENDOR_ATTRS["packages"],
    splicing_config = CRATES_VENDOR_ATTRS["splicing_config"],
    cargo_config = CRATES_VENDOR_ATTRS["cargo_config"],
    generate_build_scripts = CRATES_VENDOR_ATTRS["generate_build_scripts"],
    supported_platform_triples = CRATES_VENDOR_ATTRS["supported_platform_triples"],
    cargo_lockfile = CRATES_VENDOR_ATTRS["cargo_lockfile"],
    manifests = CRATES_VENDOR_ATTRS["manifests"],
    lockfile = attr.label(),
))
crates_vendor = module_extension(
    implementation = _crates_vendor_impl,
    tag_classes = {"crates_vendor": crates_vendor_tag},
)
