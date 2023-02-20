load("//crate_universe:defs.bzl", "crate")

_SPEC_ATTRS = dict(
    name = attr.string(mandatory = True, doc = "The name of the crate"),
    package = attr.string(doc = "The explicit name of the package (used when attempting to alias a crate)."),
    version = attr.string(doc = "The exact version of the crate. Cannot be used with `git`."),
    default_features = attr.bool(doc = "Maps to the `default-features` flag."),
    features = attr.string_list(doc = "A list of features to use for the crate"),
    git = attr.string(doc = "The Git url to use for the crate. Cannot be used with `version`."),
    rev = attr.string(doc = "The git revision of the remote crate. Tied with the `git` param."),
)

spec = tag_class(
    doc = """A constructor for a crate dependency.

                 See [specifying dependencies][sd] in the Cargo book for more details.

                 [sd]: https://doc.rust-lang.org/cargo/reference/specifying-dependencies.html
""",
    attrs = _SPEC_ATTRS,
)

def _spec_tag_to_json(tag):
    kwargs = {k: getattr(tag, k) for k in _SPEC_ATTRS if k != "name"}
    return crate.spec(**kwargs)

def spec_tags_to_json(tags):
    return {tag.name: _spec_tag_to_json(tag) for tag in tags}
