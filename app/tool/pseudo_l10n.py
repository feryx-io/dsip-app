#!/usr/bin/env python3
"""The app's pseudo-locales (app plan A7), made from lib/l10n/app_en.arb, as Android makes its own:

- en_XA: every letter accented, each message bracketed and about a third longer, so a layout that cannot take a longer
  translation, or text that is not in the ARB, shows.

Only en_XA ships: a right-to-left pseudo-locale (Android's ar_XB) would need an Arabic base locale, which would show
English to people reading Arabic; the tests lay the screens out right to left instead (`DsipApp.textDirection`).

Placeholders ({name}) and ICU plural/select syntax are kept; only literal text changes. Run it after editing
app_en.arb, then `flutter gen-l10n`:

    python3 tool/pseudo_l10n.py
"""
import json
from pathlib import Path

L10N = Path(__file__).resolve().parents[1] / "lib" / "l10n"

ACCENTS = str.maketrans(
    "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ",
    "àƀçđéƒĝĥíĵķĺɱñóþǫŕšţúṽŵẋýžÀƁÇĐÉƑĜĤÍĴĶĹḾÑÓÞǪŔŠŢÚṼŴẊÝŽ",
)
PAD = " one two three four five six seven eight nine ten"


def split(msg: str, i: int = 0, depth: int = 0):
    """`msg` from `i` as parts: ('text', s) or ('arg', s) for a {…} at this level, until an unmatched '}'."""
    parts, text = [], ""
    while i < len(msg):
        c = msg[i]
        if c == "{":
            if text:
                parts.append(("text", text))
                text = ""
            j, level = i + 1, 1
            while level:
                level += {"{": 1, "}": -1}.get(msg[j], 0)
                j += 1
            parts.append(("arg", msg[i:j]))
            i = j
        elif c == "}" and depth:
            break
        else:
            text += c
            i += 1
    if text:
        parts.append(("text", text))
    return parts


def transform_arg(arg: str, text_fn) -> str:
    """A {…}: a simple placeholder as it is; a plural/select with each branch's message transformed."""
    inner = arg[1:-1]
    if inner.count(",") < 2:
        return arg
    head, _, rest = inner.partition(",")
    kind, _, branches = rest.partition(",")
    out, i = [], 0
    while i < len(branches):
        j = branches.index("{", i)
        selector = branches[i:j]
        k, level = j + 1, 1
        while level:
            level += {"{": 1, "}": -1}.get(branches[k], 0)
            k += 1
        out.append(selector + "{" + transform(branches[j + 1 : k - 1], text_fn) + "}")
        i = k
    return "{" + head + "," + kind + "," + "".join(out) + "}"


def transform(msg: str, text_fn) -> str:
    return "".join(text_fn(s) if kind == "text" else transform_arg(s, text_fn) for kind, s in split(msg))


def pseudo_xa(msg: str) -> str:
    body = transform(msg, lambda s: s.translate(ACCENTS))
    letters = sum(c.isalpha() for c in msg)
    return "[" + body + PAD[: max(1, letters // 3)] + "]"


def main() -> None:
    en = json.loads((L10N / "app_en.arb").read_text())
    for locale, fn in (("en_XA", pseudo_xa),):
        out = {"@@locale": locale}
        for key, value in en.items():
            if not key.startswith("@"):
                out[key] = fn(value)
        (L10N / f"app_{locale}.arb").write_text(json.dumps(out, indent=2, ensure_ascii=False) + "\n")
        print(f"wrote app_{locale}.arb ({len(out) - 1} messages)")


if __name__ == "__main__":
    main()
