#!/usr/bin/env python3
"""Rebuild the FAQPage JSON-LD in site/public/index.html from the visible FAQ.

Search engines only accept FAQ markup that matches the text on the page, so
the <details> list in #fragen is the single source. Run after editing it.
"""
import html, json, re, pathlib

page = pathlib.Path(__file__).resolve().parent.parent / "site/public/index.html"
src = page.read_text()
faq = src[src.index('<div class="faq-list">'):]
faq = faq[:faq.index("</section>")]

def text(fragment):
    return html.unescape(re.sub(r"\s+", " ", re.sub(r"<[^>]+>", "", fragment))).strip()

items = [{"@type": "Question", "name": text(q),
          "acceptedAnswer": {"@type": "Answer", "text": text(a)}}
         for q, a in re.findall(r"<summary>(.*?)</summary>\s*<p>(.*?)</p>", faq, re.S)]
block = json.dumps({"@context": "https://schema.org", "@type": "FAQPage", "@id": "https://inlaut.de/#fragen",
                    "mainEntity": items}, ensure_ascii=False, indent=2)
block = '<script type="application/ld+json" id="faq-schema">\n' + block + "\n  </script>"
pattern = re.compile(r'<script type="application/ld\+json" id="faq-schema">.*?</script>', re.S)
if pattern.search(src):
    src = pattern.sub(lambda _: block, src)
else:
    src = src.replace("</head>", "  " + block + "\n</head>", 1)
page.write_text(src)
print(f"{len(items)} questions")
