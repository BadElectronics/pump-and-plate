#!/usr/bin/env python3
"""Builds the website in docs/ (served by GitHub Pages) from site/.

Fill in site/site.json, then run:  python3 scripts/make-site.py
Values left empty show as highlighted placeholders, so nothing goes live
with a blank where a name or address should be.

With --preview DIR it also writes a copy for a page preview whose main page
has no <html>/<head> wrapper (the preview adds its own).
"""
import json
import re
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SITE = ROOT / "site"
OUT = ROOT / "docs"

PLACEHOLDERS = {
    "LLC": "your LLC's legal name",
    "DOMAIN": "yourdomain.com",
    "SUPPORT_EMAIL": "support@yourdomain.com",
    "PRIVACY_EMAIL": "privacy@yourdomain.com",
    "GITHUB": "https://github.com/",
    "UPDATED": "",
}

NAV = [("index.html", "Home"), ("privacy.html", "Privacy"), ("support.html", "Support")]


def fill(text, values, in_attr=False):
    def sub(m):
        key = m.group(1)
        value = values.get(key) or ""
        if value:
            return value
        shown = PLACEHOLDERS.get(key, key)
        return shown if in_attr else f'<span class="ph">{shown}</span>'
    # Attributes first (href="{{X}}..."), where markup can't go.
    text = re.sub(r'(="[^"]*)\{\{(\w+)\}\}', lambda m: m.group(1) + (values.get(m.group(2)) or PLACEHOLDERS.get(m.group(2), "")), text)
    return re.sub(r"\{\{(\w+)\}\}", sub, text)


def page(name, values, wrapped=True):
    raw = (SITE / "pages" / name).read_text()
    title = re.search(r"<!-- title: (.*?) -->", raw).group(1)
    description = re.search(r"<!-- description: (.*?) -->", raw).group(1)
    body = re.sub(r"<!-- (title|description): .*? -->\n", "", raw)
    nav = "\n".join(
        f'      <a href="{href}"{" aria-current=\"page\"" if href == name else ""}>{label}</a>' for href, label in NAV
    )
    llc = values.get("LLC") or ""
    footer_owner = f"© 2026 {llc}" if llc else f'© 2026 <span class="ph">{PLACEHOLDERS["LLC"]}</span>'
    inner = f"""<title>{title}</title>
<meta name="description" content="{description}">
<link rel="stylesheet" href="style.css">
<link rel="icon" href="favicon.png" type="image/png">
<link rel="apple-touch-icon" href="apple-touch-icon.png">
<header class="wrap bar">
  <a class="brand" href="index.html"><img src="favicon.png" alt="" width="32" height="32">Pump and Plate</a>
  <nav class="nav" aria-label="Pages">
{nav}
  </nav>
</header>
<main class="wrap">
{body}
</main>
<footer class="wrap">
  <div class="links">
    <a href="privacy.html">Privacy policy</a>
    <a href="support.html">Support</a>
    <a href="{{{{GITHUB}}}}">Source code</a>
  </div>
  <p>{footer_owner}. Pump and Plate is free software under the GNU GPL v3. This site uses no cookies and no trackers.</p>
</footer>
"""
    inner = fill(inner, values)
    if not wrapped:
        return inner
    return f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="referrer" content="no-referrer">
</head>
<body>
{inner}</body>
</html>
"""


def build(out, values, preview=False):
    if out.exists():
        shutil.rmtree(out)
    out.mkdir(parents=True)
    for asset in ["style.css", "icon.png", "favicon.png", "apple-touch-icon.png"]:
        shutil.copy(SITE / asset, out / asset)
    shutil.copytree(SITE / "fonts", out / "fonts")
    for name, _ in NAV:
        html = page(name, values, wrapped=not (preview and name == "index.html"))
        if not (preview and name == "index.html"):
            # Move the head tags into <head>.
            head, rest = html.split("</head>\n<body>\n", 1)
            tags = re.findall(r"<(?:title>.*?</title|meta name=\"description\"[^>]*|link [^>]*)>", rest)
            for t in tags:
                rest = rest.replace(t + "\n", "", 1)
            html = head + "\n".join(tags) + "\n</head>\n<body>\n" + rest
        (out / name).write_text(html)
    domain = values.get("DOMAIN") or ""
    if not preview:
        (out / ".nojekyll").write_text("")
        if domain:
            (out / "CNAME").write_text(domain + "\n")


def main():
    values = json.loads((SITE / "site.json").read_text())
    build(OUT, values)
    print(f"Built {OUT}")
    if "--preview" in sys.argv:
        target = Path(sys.argv[sys.argv.index("--preview") + 1])
        build(target, values, preview=True)
        print(f"Built preview in {target}")


if __name__ == "__main__":
    main()
