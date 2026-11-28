"""Writes the text of an HTML notice file to standard output.

scripts/copy_ffi_notices.sh copies an HTML notice of MapLibre Native FFI as
this text, and packages/flutter_mapigrade/test/notices/ffi_notices_test.dart
compares the package's copy with it (design D248 of the
port-ffi-gesture-recognizer change). The text has no markup: each heading,
paragraph and list item is on lines of its own, separated by an empty line,
the text of <pre> elements is unchanged, and character references are
decoded.

    python3 -I scripts/html_notice_to_text.py notice.html > notice.txt
"""

import html.parser
import re
import sys

BLOCK_ELEMENTS = {
    "br", "details", "div", "h1", "h2", "h3", "h4", "h5", "h6", "li", "p",
    "pre", "summary", "ul", "ol",
}


class TextParser(html.parser.HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.parts = []
        self.pre_depth = 0
        self.head_depth = 0

    def handle_starttag(self, tag, attrs):
        if tag == "head":
            self.head_depth += 1
        if tag == "pre":
            self.pre_depth += 1
        if tag in BLOCK_ELEMENTS:
            self.parts.append("\n\n")
        if tag == "li":
            self.parts.append("- ")

    def handle_endtag(self, tag):
        if tag == "head":
            self.head_depth -= 1
        if tag == "pre":
            self.pre_depth -= 1
        if tag in BLOCK_ELEMENTS:
            self.parts.append("\n\n")

    def handle_data(self, data):
        if self.head_depth:
            return
        if self.pre_depth:
            self.parts.append(data)
            return
        text = re.sub(r"\s+", " ", data)
        if not self.parts or self.parts[-1].endswith(("\n", "- ")):
            text = text.lstrip()
        if text:
            self.parts.append(text)


def main():
    parser = TextParser()
    with open(sys.argv[1], encoding="utf-8") as file:
        parser.feed(file.read())
    parser.close()
    text = "".join(parser.parts)
    lines = [line.rstrip() if line.strip() else "" for line in text.split("\n")]
    text = re.sub(r"\n{3,}", "\n\n", "\n".join(lines)).strip() + "\n"
    sys.stdout.write(text)


if __name__ == "__main__":
    main()
