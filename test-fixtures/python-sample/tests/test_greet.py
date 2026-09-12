from sample.greet import greet


def test_greet():
    assert greet("world") == "Hello, world!"


def test_shout():
    from sample.greet import shout

    assert shout("ada").isupper()
