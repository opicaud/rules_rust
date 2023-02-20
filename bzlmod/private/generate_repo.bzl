def _generate_repo_impl(repo_ctx):
    for path, contents in repo_ctx.attr.contents.items():
        repo_ctx.file(path, contents)

generate_repo = repository_rule(
    implementation = _generate_repo_impl,
    attrs = dict(
        contents = attr.string_dict(mandatory = True),
    ),
)
