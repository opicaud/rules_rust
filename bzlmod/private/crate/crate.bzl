load("//cargo/private:cargo_utils.bzl", _rust_get_rust_tools = "get_rust_tools")
load("//crate_universe/private:generate_utils.bzl", "render_config")
load("//crate_universe/private:common_utils.bzl", "get_rust_tools")
load("//crate_universe/private:crates_repository.bzl", "crates_repository")
load("//rust:repositories.bzl", "rust_register_toolchains")
load("//rust/platform:triple.bzl", "get_host_triple")
load("//crate_universe/private:crates_vendor.bzl", "CRATES_VENDOR_ATTRS", "write_config_file", "write_splicing_manifest", _crates_vendor_repo_rule = "crates_vendor")
load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")
load("@bazel_tools//tools/build_defs/repo:git.bzl", "new_git_repository")
load("//bzlmod/private:generate_repo.bzl", "generate_repo")
load("//bzlmod/private/cargo_bazel_bootstrap:cargo_bazel_bootstrap.bzl", "get_cargo_bazel_runner")
load("//bzlmod/private/crate/tag_classes:annotation.bzl", "annotation_tags_to_json", annotation_tag = "annotation")
load("//bzlmod/private/crate/tag_classes:from_cargo.bzl", from_cargo_tag = "from_cargo")
load("//bzlmod/private/crate/tag_classes:spec.bzl", "spec_tags_to_json", spec_tag = "spec")

def _crate_impl(module_ctx):
    cargo_bazel = get_cargo_bazel_runner(module_ctx)

    for mod in module_ctx.modules:
        mod_path = module_ctx.path(mod.name)

        annotations = annotation_tags_to_json(mod.tags.annotation)
        packages = spec_tags_to_json(mod.tags.spec)

        # At the moment, this is rather inefficient in the case of many tags
        # depending on the same crate, as we have to build each package for each
        # cargo lockfile that depends on it (we generate the same package once
        # per cargo lockfile).
        # This is a non-issue if using cargo workspaces, which I'd generally
        # recommend anyway, but in the long term we should probably try and
        # share repos if they use the same configuration.
        for cfg in mod.tags.from_cargo:
            tag_path = mod_path
            repo_name = mod.name + "_crates"
            if cfg.suffix:
                tag_path = mod_path.get_child(cfg.suffix)
                repo_name += "_" + cfg.suffix

            cargo_lockfile = module_ctx.path(cfg.cargo_lockfile)

            def write_data_file(ctx, name, data):
                path = tag_path.get_child(name)
                module_ctx.file(path, content = data, executable = False)
                return path

            rendering_config = json.decode(render_config())
            rendering_config["regen_command"] = "Run 'cargo update [--workspace]'"
            config_file = write_config_file(
                module_ctx,
                mode = "remote",
                annotations = annotations,
                generate_build_scripts = cfg.generate_build_scripts,
                supported_platform_triples = cfg.supported_platform_triples,
                repository_name = repo_name,
                output_pkg = repo_name,
                workspace_name = repo_name,
                write_data_file = write_data_file,
                generate_binaries = cfg.generate_binaries,
                rendering_config = rendering_config,
            )

            manifests = {module_ctx.path(m): m for m in cfg.manifests}
            splicing_manifest = write_splicing_manifest(
                module_ctx,
                packages = packages,
                splicing_config = "",
                cargo_config = cfg.cargo_config,
                manifests = {str(p): str(l) for p, l in manifests.items()},
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

            # TODO: Thanks to the namespacing of bzlmod, although we generate
            # defs.bzl, it isn't useful (it generates deps like
            # "<module_name>_crates__env_logger-0.9.3//:env_logger", which
            # don't work because that repository isn't visible from main).
            # To solve this, we need to generate the alias
            # @crates//:env_logger-0.9.3 as well as the @crates//:env_logger
            # that it already generates, and point defs.bzl there instead.
            cargo_bazel([
                "generate",
                "--cargo-lockfile",
                cargo_lockfile,
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
            generate_repo(
                name = repo_name,
                contents = {
                    "BUILD.bazel": module_ctx.read(crates_dir.get_child("BUILD.bazel")),
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

                patch_tool = repo.get("patch_tool", None)
                patches = repo.get("patches", None)
                patch_args = repo.get("patch_args", None)

                build_file_content = module_ctx.read(crates_dir.get_child("BUILD.%s-%s.bazel" % (name, version)))
                if "Http" in repo:
                    # Replicates repo_http.j2
                    http_archive(
                        name = crate_repo_name,
                        patch_args = patch_args,
                        patch_tool = patch_tool,
                        patches = patches,
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
                        init_submodules = True,
                        patch_args = patch_args,
                        patch_tool = patch_tool,
                        patches = patches,
                        shallow_since = repo.get("shallow_since", None),
                        remote = repo["Git"]["remote"],
                        build_file_content = build_file_content,
                        strip_prefix = repo.get("strip_prefix", None),
                        **repo["commitish"],
                    )
                else:
                    fail("Invalid repo: expected Http or Git to exist for crate %s-%s, got %s" % (name, version, repo))

crate = module_extension(
    implementation = _crate_impl,
    tag_classes = dict(
        annotation = annotation_tag,
        from_cargo = from_cargo_tag,
        spec = spec_tag,
    ),
)
