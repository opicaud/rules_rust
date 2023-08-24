"""Module extension for generating third-party crates for use in bazel."""

load("@bazel_tools//tools/build_defs/repo:git.bzl", "new_git_repository")
load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")
load("//crate_universe:defs.bzl", _crate_universe_crate = "crate")
load("//crate_universe/private:crates_vendor.bzl", "CRATES_VENDOR_ATTRS", "write_config_file", "write_splicing_manifest")
load("//crate_universe/private:generate_utils.bzl", "render_config")
load("//crate_universe/private/module_extensions:cargo_bazel_bootstrap.bzl", "get_cargo_bazel_runner")

def _generate_repo_impl(repo_ctx):
    for path, contents in repo_ctx.attr.contents.items():
        repo_ctx.file(path, contents)

_generate_repo = repository_rule(
    implementation = _generate_repo_impl,
    attrs = dict(
        contents = attr.string_dict(mandatory = True),
    ),
)

def _generate_annotations(module_ctx, annotation_files):
    annotations = {}

    def add_annotation(k, v):
        if k not in annotations:
            annotations[k] = []
        annotations[k].append(v)

    for file in annotation_files:
        for name, annotations_for_crate in json.decode(module_ctx.read(file)).items():
            for annotation_for_crate in annotations_for_crate:
                add_annotation(name, _crate_universe_crate.annotation(**annotation_for_crate))

    return annotations

def _crate_impl(module_ctx):
    cargo_bazel = get_cargo_bazel_runner(module_ctx)

    for mod in module_ctx.modules:
        mod_path = module_ctx.path(mod.name)

        # At the moment, we namespace each different instance of the module
        # extension. This ensures that if I do the following:
        # crate.from_cargo(manifests=["a/Cargo.toml"], suffix="a")
        # crate.from_cargo(manifests=["b/Cargo.toml"], suffix="b")
        #
        # If a/Cargo.toml declares a dep on anyhow with no features, and
        # b/Cargo.toml declares a dep on anyhow with the "backtrace" feature,
        # then "crates_a//:anyhow" won't be able to use backtrace.
        #
        # However, it also means that if they use the exact same config, then
        # we'll have to build it twice.
        #
        # This is a non-issue if using cargo workspaces, which I'd generally
        # recommend anyway, but in the long term we may want to consider sharing
        # repos if they use the same configuration.
        for cfg in mod.tags.from_cargo:
            annotations = _generate_annotations(module_ctx, cfg.annotation_files)
            tag_path = mod_path
            repo_name = mod.name + "_crates"
            if cfg.suffix:
                tag_path = mod_path.get_child(cfg.suffix)
                repo_name += "_" + cfg.suffix

            cargo_lockfile = module_ctx.path(cfg.cargo_lockfile)

            def write_data_file(
                    ctx,  # @unused
                    name,
                    data):
                path = tag_path.get_child(name)  # buildifier: disable=uninitialized
                module_ctx.file(path, content = data, executable = False)
                return path

            rendering_config = json.decode(render_config(
                regen_command = "Run 'cargo update [--workspace]'",
            ))
            config_file = write_config_file(
                module_ctx,
                mode = "remote",
                annotations = annotations,
                generate_build_scripts = cfg.generate_build_scripts,
                supported_platform_triples = cfg.supported_platform_triples,
                repository_name = repo_name,
                output_pkg = repo_name,
                repo_name = repo_name,
                write_data_file = write_data_file,
                generate_binaries = cfg.generate_binaries,
                rendering_config = rendering_config,
            )

            manifests = {module_ctx.path(m): m for m in cfg.manifests}
            splicing_manifest = write_splicing_manifest(
                module_ctx,
                packages = {},
                splicing_config = "",
                cargo_config = cfg.cargo_config,
                manifests = {str(k): str(v) for k, v in manifests.items()},
                write_data_file = write_data_file,
                manifest_to_path = module_ctx.path,
            )

            splicing_output_dir = tag_path.get_child("splicing-output")
            cargo_bazel([
                "splice",
                "--output-dir",
                splicing_output_dir,
                "--config",
                config_file,
                "--splicing-manifest",
                splicing_manifest,
                "--cargo-lockfile",
                cargo_lockfile,
            ])

            # Create a lockfile, since we need to parse it to generate spoke
            # repos.
            lockfile_path = tag_path.get_child("lockfile.json")
            module_ctx.file(lockfile_path, "")

            # cargo-bazel generate takes the lockfile as input, but also writes
            # to the lockfile. This means that even though nothing changes, the
            # modified timestamp of the file is updated. Since the lock file is
            # an input to the rule, this would invalidate the repo rule,
            # requiring it to be rerun on every invocation.
            # To solve this, we allow it to touch a copy of the lock file,
            # rather than the original.
            cargo_lockfile_copy = tag_path.get_child("copy/Cargo.lock")
            module_ctx.file(
                cargo_lockfile_copy,
                module_ctx.read(cargo_lockfile),
            )
            cargo_bazel([
                "generate",
                "--cargo-lockfile",
                cargo_lockfile_copy,
                "--config",
                config_file,
                "--splicing-manifest",
                splicing_manifest,
                "--repository-dir",
                tag_path,
                "--metadata",
                splicing_output_dir.get_child("metadata.json"),
                "--repin",
                "--lockfile",
                lockfile_path,
            ])

            crates_dir = tag_path.get_child(repo_name)
            _generate_repo(
                name = repo_name,
                contents = {
                    "BUILD.bazel": module_ctx.read(crates_dir.get_child("BUILD.bazel")),
                    "defs.bzl": module_ctx.read(crates_dir.get_child("defs.bzl")),
                },
            )

            contents = json.decode(module_ctx.read(lockfile_path))

            for crate in contents["crates"].values():
                repo = crate["repository"]
                if repo == None:
                    continue
                name = crate["name"]
                version = crate["version"]

                # "+" isn't valid in a repo name.
                crate_repo_name = "%s__%s-%s" % (repo_name, name, version.replace("+", "-"))

                build_file_content = module_ctx.read(crates_dir.get_child("BUILD.%s-%s.bazel" % (name, version)))
                if "Http" in repo:
                    # Replicates functionality in repo_http.j2.
                    repo = repo["Http"]
                    http_archive(
                        name = crate_repo_name,
                        patch_args = repo.get("patch_args", None),
                        patch_tool = repo.get("patch_tool", None),
                        patches = repo.get("patches", None),
                        remote_patch_strip = 1,
                        sha256 = repo["sha256"],
                        type = "tar.gz",
                        urls = [repo["url"]],
                        strip_prefix = "%s-%s" % (crate["name"], crate["version"]),
                        build_file_content = build_file_content,
                    )
                elif "Git" in repo:
                    # Replicates functionality in repo_git.j2
                    repo = repo["Git"]
                    new_git_repository(
                        name = crate_repo_name,
                        init_submodules = True,
                        patch_args = repo.get("patch_args", None),
                        patch_tool = repo.get("patch_tool", None),
                        patches = repo.get("patches", None),
                        shallow_since = repo.get("shallow_since", None),
                        remote = repo["remote"],
                        build_file_content = build_file_content,
                        strip_prefix = repo.get("strip_prefix", None),
                        commit = repo["commitish"].get("Rev", None),
                        #**repo["commitish"]
                    )
                else:
                    fail("Invalid repo: expected Http or Git to exist for crate %s-%s, got %s" % (name, version, repo))

_from_cargo = tag_class(
    doc = "Generates a repo <mod_name>_crates",
    attrs = dict(
        suffix = attr.string(
            doc = "If provided, instead generates a repo <mod_name>_crates_<suffix>. " +
                  "This can help avoid conflicts if you declare multiple from_cargo in a single module.",
        ),
        cargo_lockfile = CRATES_VENDOR_ATTRS["cargo_lockfile"],
        manifests = CRATES_VENDOR_ATTRS["manifests"],
        cargo_config = CRATES_VENDOR_ATTRS["cargo_config"],
        generate_binaries = CRATES_VENDOR_ATTRS["generate_binaries"],
        generate_build_scripts = CRATES_VENDOR_ATTRS["generate_build_scripts"],
        supported_platform_triples = CRATES_VENDOR_ATTRS["supported_platform_triples"],
        annotation_files = attr.label_list(allow_files = [".json"]),
    ),
)

crate = module_extension(
    implementation = _crate_impl,
    tag_classes = dict(
        from_cargo = _from_cargo,
    ),
)
