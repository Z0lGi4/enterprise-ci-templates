import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.greet import greet
from helpers.shout import shout


def test_greet_uses_the_requirements_txt_dependency():
    assert greet("world") == 'greeting = "Hello, world!"'


def test_greet_escapes_quotes():
    assert greet('a"b') == 'greeting = "Hello, a\\"b!"'


def test_shout():
    assert shout("hi") == "HI"
