load("//crate_universe:defs.bzl", "crate")

_ANNOTATION_ATTRS = dict(
    crate = attr.string(
        mandatory = True,
        doc = "The crate to apply the annotation to. The wildcard `*` matches any version, including prerelease versions.",
    ),
    version = attr.string(
        default = "*",
        doc = "The version or semver-conditions to match with a crate.",
    ),
    additive_build_file_content = attr.string(
        doc = "Extra contents to write to the bottom of generated BUILD files.",
    ),
    additive_build_file = attr.label(
        allow_single_file = True,
        doc = "A file containing extra contents to write to the bottom of generated BUILD files",
    ),
    build_script_data = attr.label_list(
        doc = "A list of labels to add to a crate's `cargo_build_script::data` attribute.",
    ),
    build_script_tools = attr.label_list(
        doc = "A list of labels to add to a crate's `cargo_build_script::tools` attribute.",
    ),
    build_script_data_glob = attr.string_list(
        doc = "A list of glob patterns to add to a crate's `cargo_build_script::data` attribute",
    ),
    build_script_deps = attr.label_list(
        doc = "A list of labels to add to a crate's `cargo_build_script::deps` attribute.",
    ),
    build_script_env = attr.string_dict(
        doc = "Additional environment variables to set on a crate's `cargo_build_script::env` attribute.",
    ),
    build_script_proc_macro_deps = attr.label_list(
        doc = "A list of labels to add to a crate's `cargo_build_script::proc_macro_deps` attribute.",
    ),
    build_script_rustc_env = attr.string_dict(
        doc = "Additional environment variables to set on a crate's `cargo_build_script::env` attribute.",
    ),
    build_script_toolchains = attr.label_list(
        doc = "A list of labels to set on a crates's `cargo_build_script::toolchains` attribute.",
    ),
    compile_data = attr.label_list(
        doc = "A list of labels to add to a crate's `rust_library::compile_data` attribute.",
    ),
    compile_data_glob = attr.string_list(
        doc = "A list of glob patterns to add to a crate's `rust_library::compile_data` attribute",
    ),
    crate_features = attr.string_list(
        doc = "A list of strings to add to a crate's `rust_library::crate_features` attribute.",
    ),
    data = attr.label_list(
        doc = "A list of labels to add to a crate's `rust_library::data` attribute.",
    ),
    data_glob = attr.string_list(
        doc = "A list of glob patterns to add to a crate's `rust_library::data` attribute.",
    ),
    deps = attr.label_list(
        doc = "A list of labels to add to a crate's `rust_library::deps` attribute.",
    ),
    disable_pipelining = attr.bool(
        doc = "If True, disables pipelining for library targets for this crate.",
    ),
    gen_all_binaries = attr.bool(
        doc = "If true, generates all binaries for a crate."
    ),
    gen_binaries = attr.string_list(
        doc = "Thu subset of the crate's bins that should get `rust_binary` targets produced."
    ),
    gen_build_script = attr.bool(
        doc = "An authorative flag to determine whether or not to produce `cargo_build_script` targets for the current crate.",
    ),
    patch_args = attr.string_list(
        doc = "The `patch_args` attribute of a Bazel repository rule. See [http_archive.patch_args](https://docs.bazel.build/versions/main/repo/http.html#http_archive-patch_args)",
    ),
    patch_tool = attr.string(
        doc = "The `patch_tool` attribute of a Bazel repository rule. See [http_archive.patch_tool](https://docs.bazel.build/versions/main/repo/http.html#http_archive-patch_tool)",
    ),
    patches = attr.label_list(
        doc = "The `patches` attribute of a Bazel repository rule. See [http_archive.patches](https://docs.bazel.build/versions/main/repo/http.html#http_archive-patches)",
    ),
    proc_macro_deps = attr.label_list(
        doc = "A list of labels to add to a crate's `rust_library::proc_macro_deps` attribute.",
    ),
    rustc_env = attr.string_dict(
        doc = "Additional variables to set on a crate's `rust_library::rustc_env` attribute.",
    ),
    rustc_env_files = attr.label_list(
        doc = "A list of labels to set on a crate's `rust_library::rustc_env_files` attribute.",
    ),
    rustc_flags = attr.string_list(
        doc = "A list of strings to set on a crate's `rust_library::rustc_flags` attribute.",
    ),
    shallow_since = attr.string(
        doc = "An optional timestamp used for crates originating from a git repository instead of a crate registry. This flag optimizes fetching the source code.",
    ),

)

annotation = tag_class(
    doc = "A collection of extra attributes and settings for a particular crate",
    attrs = _ANNOTATION_ATTRS,
)

def annotation_tags_to_json(tags):
    annotations = {}
    for tag in tags:
        if tag.crate not in annotations:
            annotations[tag.crate] = []

        kwargs = {k: getattr(tag, k) for k in _ANNOTATION_ATTRS}
        kwargs.pop("crate")
        if kwargs.pop("gen_all_binaries"):
            kwargs["gen_binaries"] = True
        annotations[tag.crate].append(crate.annotation(**kwargs))
    return annotations
