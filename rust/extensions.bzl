"Module extensions for using rules_rust with bzlmod"

load("//crate_universe/module_extensions:crate.bzl", _crate = "crate")
load("//rust/private/module_extensions:toolchain.bzl", _rust = "rust")

crate = _crate
rust = _rust
