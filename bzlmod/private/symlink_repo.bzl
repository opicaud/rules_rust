def _symlink_repo_impl(repo_ctx):
    for path, target in repo_ctx.attr.files.items():
        repo_ctx.symlink(target, path)

symlink_repo = repository_rule(
    implementation = _symlink_repo_impl,
    attrs = dict(
        files = attr.string_dict(mandatory = True),
    ),
)
