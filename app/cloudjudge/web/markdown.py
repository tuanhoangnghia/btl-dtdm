"""Bộ render markdown tối giản cho đề bài: tiêu đề #, khối ```code```, `code`, **đậm**, danh sách -, đoạn văn.

Mọi nội dung được escape trước, nên đề bài không chèn được HTML/JS.
"""
from __future__ import annotations

import re

from markupsafe import Markup, escape


def _inline(text: str) -> str:
    s = str(escape(text))
    s = re.sub(r"`([^`]+)`", r"<code>\1</code>", s)
    s = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", s)
    return s


def render(md: str) -> Markup:
    out: list[str] = []
    para: list[str] = []
    items: list[str] = []
    lines = md.replace("\r\n", "\n").split("\n")
    i = 0

    def flush():
        if para:
            out.append("<p>" + " ".join(_inline(p) for p in para) + "</p>")
            para.clear()
        if items:
            out.append("<ul>" + "".join(f"<li>{_inline(x)}</li>" for x in items) + "</ul>")
            items.clear()

    while i < len(lines):
        line = lines[i]
        if line.startswith("```"):
            flush()
            code = []
            i += 1
            while i < len(lines) and not lines[i].startswith("```"):
                code.append(lines[i])
                i += 1
            out.append("<pre><code>" + str(escape("\n".join(code))) + "</code></pre>")
        elif m := re.match(r"(#{1,4})\s+(.*)", line):
            flush()
            level = len(m.group(1)) + 1  # h1 dành cho tiêu đề bài
            out.append(f"<h{level}>{_inline(m.group(2))}</h{level}>")
        elif m := re.match(r"\s*[-*]\s+(.*)", line):
            if para:
                flush()
            items.append(m.group(1))
        elif not line.strip():
            flush()
        else:
            if items:
                flush()
            para.append(line.strip())
        i += 1
    flush()
    return Markup("\n".join(out))
