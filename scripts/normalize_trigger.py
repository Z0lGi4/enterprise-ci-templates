"""Make a caller's `pull_request:` trigger list its activity types explicitly.

The review gate skips drafts, and `ready_for_review` is not one of GitHub's
default pull_request activity types, so a bare trigger never re-fires when a
draft is marked ready: the required check stays on its stale "skipped"
result. Reads a workflow on stdin, writes it to stdout.

Exits 1 with a message for any shape it cannot prove correct (the list
shorthand `on: [push, pull_request]`, a `types:` list without
ready_for_review, no `pull_request:` mapping at all): the release must fail
for that adopter rather than silently leave the trigger untyped.
"""
import re
import sys

# Byte-faithful on every platform: no CRLF translation on the way in or out.
sys.stdin.reconfigure(newline="")
sys.stdout.reconfigure(newline="")

TYPES = "    types: [opened, synchronize, reopened, ready_for_review]"
KEY = re.compile(r"^  pull_request:[ \t]*(#.*)?(\r?\n)", re.M)
NEXT_KEY = re.compile(r"^(?:  [^ \t\r\n#]|[^ \t\r\n#])", re.M)  # next 2-space or top-level key


def fail(msg):
    sys.stderr.write(f"normalize_trigger: {msg}; fix the trigger by hand\n")
    sys.exit(1)


text = sys.stdin.read()
m = KEY.search(text)
if not m:
    fail("no `  pull_request:` block mapping found")
nxt = NEXT_KEY.search(text, m.end())
block = text[m.end():nxt.start() if nxt else len(text)]
if "ready_for_review" in block:
    sys.stdout.write(text)
    sys.exit(0)
if re.search(r"^\s+types:", block, re.M):
    fail("pull_request already has a `types:` list without ready_for_review")
eol = m.group(2)  # keep the file's own line ending
sys.stdout.write(text[:m.end()] + TYPES + eol + text[m.end():])
