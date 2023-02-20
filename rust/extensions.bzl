"Module extensions for using rules_rust with bzlmod"

load("//bzlmod/private/cargo_bazel_bootstrap:cargo_bazel_bootstrap.bzl", _cargo_bazel_bootstrap = "cargo_bazel_bootstrap")
load("//bzlmod/private/toolchains:toolchains.bzl", _toolchains = "toolchains")

cargo_bazel_bootstrap = _cargo_bazel_bootstrap
toolchains = _toolchains
