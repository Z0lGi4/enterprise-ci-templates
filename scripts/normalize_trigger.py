"""Give a caller's bare `pull_request:` trigger the explicit activity types.

The review gate skips drafts, and `ready_for_review` is not one of GitHub's
default pull_request activity types, so a bare trigger would never re-fire
when a draft is marked ready. Reads a workflow on stdin, writes it to
stdout; a trigger that already lists types is left alone.
"""
import re
import sys

TYPES = "    types: [opened, synchronize, reopened, ready_for_review]\n"
text = sys.stdin.read()
text = re.sub(r"^(  pull_request:[ \t]*\n)(?!    types:)", lambda m: m.group(1) + TYPES, text, count=1, flags=re.M)
sys.stdout.write(text)
