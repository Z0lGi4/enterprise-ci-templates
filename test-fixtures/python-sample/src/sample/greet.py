def greet(name: str) -> str:
    return f"Hello, {name}!"


def shout(name: str) -> str:
    """Exists so the template's own PR has a changed, covered line for diff-cover."""
    return greet(name).upper()
