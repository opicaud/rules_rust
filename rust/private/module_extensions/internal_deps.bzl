"""Bzlmod module extensions that are only used internally"""

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")
load("//rust/private:repository_utils.bzl", "TINYJSON_KWARGS")
load("//tools/rust_analyzer/3rdparty/crates:defs.bzl", rust_analyzer_deps = "crate_repositories")

def _internal_deps_impl(_module_ctx):
    http_archive(**TINYJSON_KWARGS)

    rust_analyzer_deps()

internal_deps = module_extension(
    doc = "Dependencies for rules_rust",
    implementation = _internal_deps_impl,
)
