"""Module extension for bootstrapping cargo-bazel."""

load("//crate_universe:deps_bootstrap.bzl", _cargo_bazel_bootstrap_repo_rule = "cargo_bazel_bootstrap")

def _cargo_bazel_bootstrap_impl(_):
    _cargo_bazel_bootstrap_repo_rule(
        rust_toolchain_cargo_template = "@rust_host_tools//:bin/{tool}",
        rust_toolchain_rustc_template = "@rust_host_tools//:bin/{tool}",
    )

cargo_bazel_bootstrap = module_extension(
    implementation = _cargo_bazel_bootstrap_impl,
)

def get_cargo_bazel_runner(module_ctx):
    """A helper function to allow executing cargo_bazel in module extensions.

    Args:
        module_ctx: The module extension's context.

    Returns:
        A function that can be called to execute cargo_bazel.
    """
    cargo_path = str(module_ctx.path(Label("@rust_host_tools//:bin/cargo")))
    rustc_path = str(module_ctx.path(Label("@rust_host_tools//:bin/rustc")))
    cargo_bazel = module_ctx.path(Label("@cargo_bazel_bootstrap//:cargo-bazel"))

    def run(args, env = {}, timeout = 600):
        final_args = [cargo_bazel]
        final_args.extend(args)
        final_args.extend([
            "--cargo",
            cargo_path,
            "--rustc",
            rustc_path,
        ])
        result = module_ctx.execute(
            final_args,
            environment = dict(CARGO = cargo_path, RUSTC = rustc_path, **env),
            timeout = timeout,
        )
        if result.return_code != 0:
            if result.stdout:
                print("Stdout:", result.stdout)  # buildifier: disable=print
            pretty_args = " ".join([str(arg) for arg in final_args])
            fail("%s returned with exit code %d:\n%s" % (pretty_args, result.return_code, result.stderr))
        return result

    return run
