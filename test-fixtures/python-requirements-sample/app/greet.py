"""Flat-layout module, importable without the project being pip-installed."""

import tomli_w


def greet(name: str) -> str:
    """Return a greeting, round-tripped through a real third-party dependency.

    The tomli_w call is the point: it fails with ImportError unless
    requirements.txt was actually installed, so a CI step that silently skipped
    the install cannot pass this test.
    """
    return tomli_w.dumps({"greeting": f"Hello, {name}!"}).strip()
