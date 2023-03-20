load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")
load("//rust:repositories.bzl", "TINYJSON_KWARGS")

def _non_bzlmod_deps_impl(module_ctx):
    http_archive(**TINYJSON_KWARGS)

non_bzlmod_deps_non_bzlmod_deps = tag_class(attrs = {})
non_bzlmod_deps = module_extension(
    doc = "Dependencies for rules_rust",
    implementation = _non_bzlmod_deps_impl,
    tag_classes = dict(
        non_bzlmod_deps = non_bzlmod_deps_non_bzlmod_deps,
    ),
)
