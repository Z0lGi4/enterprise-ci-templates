"""A SECOND top-level package. Its only job is to exist.

With two top-level packages and no [project]/[build-system], setuptools'
flat-layout auto-discovery refuses to build ("Multiple top-level packages
discovered in a flat-layout") and `pip install -e .` fails — which is exactly
what happens on seoforge-ai (17 top-level dirs). Do not merge these two
packages into one; the ambiguity IS the fixture.
"""


def shout(text: str) -> str:
    return text.upper()
