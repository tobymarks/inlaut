#!/usr/bin/env python3
"""Render inlaut Instagram carousels (1080x1350) and the profile picture.

Slides are HTML in the brand colours, rendered with headless Chrome so German
text and umlauts come out exactly. Usage: python3 build.py [post-name ...]
"""
import pathlib, subprocess, sys

HERE = pathlib.Path(__file__).resolve().parent
OUT = HERE / "posts"
KIT = (HERE.parent / "inlaut-brand-kit" / "logo").as_uri()
SCREENS = (HERE.parent.parent / "site" / "public" / "screens").as_uri()
PERSONAS = (HERE.parent.parent / "site" / "public" / "personas").as_uri()
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

CSS = """
* { box-sizing: border-box; margin: 0; padding: 0; }
html, body { width: 1080px; height: 1350px; overflow: hidden; }
body { font-family: -apple-system, "SF Pro Display", "Helvetica Neue", sans-serif;
  -webkit-font-smoothing: antialiased; letter-spacing: -0.02em; }
.slide { position: relative; width: 1080px; height: 1350px; padding: 96px 96px 88px; display: flex; flex-direction: column; }
.dark { background: #103D3B; color: #F6F7F4; }
.light { background: #F6F7F4; color: #172C2B; }
.top { display: flex; justify-content: space-between; align-items: center; height: 56px; }
.top img { height: 48px; }
.count { font-size: 26px; font-weight: 500; opacity: .6; font-variant-numeric: tabular-nums; }
.body { flex: 1; display: flex; flex-direction: column; justify-content: center; }
.foot { display: flex; justify-content: space-between; align-items: center; font-size: 28px; font-weight: 500; }
.dark .foot { color: #BCEBD9; } .light .foot { color: #236E64; }
.eyebrow { font-size: 30px; font-weight: 600; letter-spacing: .02em; margin-bottom: 32px; }
.dark .eyebrow { color: #BCEBD9; } .light .eyebrow { color: #236E64; }
.tag { align-self: flex-start; font-size: 28px; font-weight: 600; padding: 12px 24px; border-radius: 999px; margin-bottom: 40px; }
.dark .tag { background: #BCEBD9; color: #103D3B; } .light .tag { background: #103D3B; color: #BCEBD9; }
h1 { font-size: 104px; line-height: 1.03; font-weight: 600; letter-spacing: -0.045em; }
h2 { font-size: 80px; line-height: 1.07; font-weight: 600; letter-spacing: -0.04em; }
.dark h1 em, .dark h2 em { font-style: normal; color: #BCEBD9; }
.light h1 em, .light h2 em { font-style: normal; color: #236E64; }
p.lead { font-size: 40px; line-height: 1.4; margin-top: 44px; max-width: 870px; }
.dark p.lead { color: #D6E6E0; } .light p.lead { color: #536A67; }
.steps { margin-top: 64px; display: flex; flex-direction: column; gap: 40px; }
.step { display: flex; gap: 36px; align-items: center; font-size: 44px; font-weight: 500; }
.num { flex-shrink: 0; width: 88px; height: 88px; border-radius: 50%; display: grid; place-items: center; font-size: 38px; font-weight: 600; }
.light .num { background: #103D3B; color: #BCEBD9; } .dark .num { background: #BCEBD9; color: #103D3B; }
.note { margin-top: 56px; font-size: 34px; line-height: 1.4; padding: 28px 36px; border-radius: 24px; }
.light .note { background: #E7EEE8; } .dark .note { background: #153330; color: #D6E6E0; }
.list { margin-top: 60px; display: flex; flex-direction: column; gap: 0; }
.item { display: flex; gap: 28px; align-items: baseline; font-size: 44px; font-weight: 500; padding: 26px 0; border-top: 2px solid #D7E2DC; }
.dark .item { border-color: #35514B; }
.item b { color: #236E64; font-weight: 600; } .dark .item b { color: #BCEBD9; }
.cols { margin-top: 64px; display: grid; grid-template-columns: 1fr 1fr; gap: 28px; }
.col { border-radius: 28px; padding: 44px 40px; font-size: 34px; line-height: 1.35; }
.col h3 { font-size: 36px; font-weight: 600; margin-bottom: 28px; }
.col ul { list-style: none; display: flex; flex-direction: column; gap: 22px; }
.col.muted { background: #E7EEE8; color: #536A67; } .col.brand { background: #103D3B; color: #F6F7F4; }
.col.brand h3 { color: #BCEBD9; }
.shot { margin-top: 48px; border-radius: 28px; overflow: hidden; background: #DFEDE5; display: grid; place-items: center; }
.shot img { display: block; }
.crop { position: relative; width: 888px; height: 592px; overflow: hidden; margin-top: 48px; border-radius: 28px; }
.crop img { position: absolute; width: 1421px; left: -266px; top: -139px; }
.label { margin-top: 22px; font-size: 26px; opacity: .65; }
.symbol { width: 220px; margin-bottom: 64px; }
.pill { display: inline-flex; align-items: center; gap: 14px; margin-top: 56px; padding: 22px 34px; border-radius: 999px;
  font-size: 34px; font-weight: 600; background: #BCEBD9; color: #103D3B; align-self: flex-start; }
.light .pill { background: #103D3B; color: #BCEBD9; }
/* Generic example window: deliberately not a copy of any real app. */
.win { margin-top: 56px; background: #fff; border-radius: 28px; box-shadow: 0 24px 60px rgba(16,61,59,.14); overflow: hidden; }
.win-bar { display: flex; align-items: center; gap: 12px; padding: 22px 28px; border-bottom: 2px solid #EEF2EF; font-size: 26px; color: #536A67; }
.dot { width: 16px; height: 16px; border-radius: 50%; background: #D7E2DC; }
.win-title { margin-left: 16px; font-weight: 600; }
.win-body { padding: 36px 40px 40px; font-size: 34px; line-height: 1.5; color: #172C2B; }
.win-body p + p { margin-top: 22px; }
.caret { display: inline-block; width: 3px; height: 38px; background: #172C2B; vertical-align: -6px; margin-left: 4px; }
.listen { display: inline-flex; align-items: center; gap: 14px; margin-top: 28px; padding: 14px 24px; border-radius: 999px;
  background: #F1F5F2; box-shadow: 0 6px 20px rgba(16,61,59,.15); font-size: 26px; font-weight: 600; color: #103D3B; }
.listen i { width: 12px; height: 12px; border-radius: 50%; background: #C84442; }
.listen s { display: inline-flex; gap: 5px; align-items: center; text-decoration: none; }
.listen s span { width: 5px; border-radius: 3px; background: #103D3B; }
.say { margin-top: 48px; font-size: 32px; color: #536A67; }
.say q { display: block; margin-top: 14px; font-size: 38px; line-height: 1.45; color: #172C2B; font-style: italic; quotes: "„" "“"; }
.arrow { margin: 30px 0 0; font-size: 44px; color: #236E64; }
.chips { display: flex; flex-wrap: wrap; gap: 18px; margin-top: 44px; }
.chip { font-size: 32px; padding: 16px 28px; border-radius: 999px; background: #E7EEE8; color: #172C2B; }
.chip b { color: #236E64; }
"""

def page(theme, n, total, body, right=""):
    logo = "inlaut-logo-mint.svg" if theme == "dark" else "inlaut-logo-petrol.svg"
    count = f'<span class="count">{n}/{total}</span>' if total > 1 else ""
    return (f'<!doctype html><html lang="de"><meta charset="utf-8"><style>{CSS}</style><body>'
            f'<div class="slide {theme}"><div class="top"><img src="{KIT}/{logo}" alt="">{count}</div>'
            f'<div class="body">{body}</div><div class="foot"><span>inlaut.de</span><span>{right}</span></div></div></body></html>')

SYMBOL = f'<img class="symbol" src="{KIT}/inlaut-symbol-mint.svg" alt="">'
LEVELS = "".join(f'<span style="height:{h}px"></span>' for h in (10, 18, 26, 14, 30, 20, 12))
LISTEN = f'<span class="listen"><i></i>Hört zu<s>{LEVELS}</s></span>'

def window(title, paragraphs, listening=True):
    body = "".join(f"<p>{p}</p>" for p in paragraphs[:-1]) + f'<p>{paragraphs[-1]}<span class="caret"></span></p>'
    return (f'<div class="win"><div class="win-bar"><span class="dot"></span><span class="dot"></span><span class="dot"></span>'
            f'<span class="win-title">{title}</span></div><div class="win-body">{body}{LISTEN if listening else ""}</div></div>'
            '<p class="label">Beispiel</p>')

def cover(tag, headline, lead=""):
    lead = f'<p class="lead">{lead}</p>' if lead else ""
    return ("dark", f'{SYMBOL}<span class="tag">{tag}</span><h1>{headline}</h1>{lead}', "Wischen →")

def items(*rows):
    return '<div class="list">' + "".join(f'<div class="item"><b>→</b>{r}</div>' for r in rows) + "</div>"

CTA = ("dark", '<h1>Kostenlos.<br><em>Open Source.</em></h1><p class="lead">Diktieren am Mac – lokal, ohne Cloud, ohne Konto. '
       'Für Apple-Silicon-Macs ab macOS 26.</p><span class="pill">inlaut.de · Link in Bio</span>', "")

POSTS = {
"1-vorstellung": [
  ("dark", f'{SYMBOL}<h1>Taste halten.<br>Sprechen.<br><em>Loslassen.</em></h1><p class="lead">Diktieren am Mac. Lokal, ohne Cloud und kostenlos.</p>', "Wischen →"),
  ("light", '<p class="eyebrow">Warum diktieren?</p><h2>Sprechen ist schneller als <em>Tippen.</em></h2><p class="lead">Mail, Notiz, Dokument oder KI-Prompt: Mit inlaut landet dein Text direkt dort, wo dein Cursor steht. In jeder App.</p>', ""),
  ("light", '<p class="eyebrow">So geht’s</p><h2>Drei Schritte.</h2><div class="steps"><div class="step"><span class="num">1</span>🌐-Taste halten</div><div class="step"><span class="num">2</span>Sprechen</div><div class="step"><span class="num">3</span>Loslassen – der Text steht da</div></div><div class="note"><b>Freihändig:</b> Zweimal auf 🌐 tippen startet, einmal tippen beendet.</div>', ""),
  ("dark", '<p class="eyebrow">Lokal</p><h2>Dein Mac hört zu. <em>Sonst niemand.</em></h2><div class="list"><div class="item"><b>✓</b>Keine Cloud</div><div class="item"><b>✓</b>Kein Konto</div><div class="item"><b>✓</b>Kein Tracking</div></div><p class="lead">Die Spracherkennung läuft auf deinem Mac – mit einem auf Deutsch abgestimmten Modell.</p>', ""),
  ("dark", '<h1>Kostenlos.<br><em>Open Source.</em></h1><p class="lead">Für Apple-Silicon-Macs ab macOS 26.</p><span class="pill">inlaut.de · Link in Bio</span>', ""),
],
"2-datenschutz": [
  ("dark", f'{SYMBOL}<h1>Deine Worte bleiben <em>auf deinem Mac.</em></h1>', "Wischen →"),
  ("light", '<p class="eyebrow">Der Unterschied</p><h2>Wo wird dein Diktat erkannt?</h2><div class="cols"><div class="col muted"><h3>Viele Cloud-Dienste</h3><ul><li>Audio geht an einen Server</li><li>Oft mit Konto</li><li>Oft im Abo</li></ul></div><div class="col brand"><h3>inlaut</h3><ul><li>Erkennung auf deinem Mac</li><li>Ohne Konto</li><li>Kostenlos</li></ul></div></div>', ""),
  ("light", '<p class="eyebrow">Und das Mikrofon?</p><h2>Nur an, wenn <em>du</em> sprichst.</h2><p class="lead">Das Mikrofon ist nur beim Diktieren aktiv. Aufnahmen und Texte werden nicht als Verlauf gespeichert und nicht übertragen.</p>', ""),
  ("dark", '<p class="eyebrow">Nachprüfbar</p><h2>Der Code ist <em>offen.</em></h2><p class="lead">Jede Zeile von inlaut steht auf GitHub. Du musst nichts glauben – du kannst nachsehen.</p><span class="pill">github.com/tobymarks/inlaut</span>', ""),
],
"3-so-sieht-es-aus": [
  ("light", f'<p class="eyebrow">So sieht’s aus</p><h2>Diktieren, wo du <em>schreibst.</em></h2><div class="crop"><img src="{SCREENS}/diktat.png" alt=""></div><p class="label">Illustration</p>', ""),
  ("light", f'<p class="eyebrow">Klein in der Menüleiste</p><h2>Alles mit einem Klick.</h2><div class="shot" style="padding:40px 0"><img src="{SCREENS}/menue.png" width="760" height="564" alt=""></div><p class="label">Illustration</p>', ""),
  ("dark", f'<p class="eyebrow">Einstellungen</p><h2>Passend <em>zu dir.</em></h2><div class="shot" style="background:#0C201F;height:760px;align-items:start"><img src="{SCREENS}/einstellungen.png" width="760" alt=""></div><p class="label">Screenshot</p>', ""),
],

# Zielgruppen
"4-studierende": [
  cover("Für Studierende", "Die Hausarbeit beginnt mit einem Gedanken. <em>Sprich ihn aus.</em>"),
  ("light", '<p class="eyebrow">Wofür?</p><h2>Vom Kopf direkt <em>aufs Papier.</em></h2>' + items(
      "Rohfassung runtersprechen", "Gedanken nach der Vorlesung festhalten", "Mails an Dozierende", "Lernzettel in eigenen Worten"), ""),
  ("light", '<p class="eyebrow">Beispiel</p><h2>Erst sprechen, <em>dann feilen.</em></h2>' + window("Hausarbeit – Gliederung", [
      "Warum kommt die Energiewende in vielen Kommunen nur langsam voran?",
      "Drei Gründe stehen im Mittelpunkt: fehlendes Personal, komplizierte Förderung und wenig Bürgerbeteiligung."]), ""),
  ("dark", '<h1>Kostenlos. Ohne Abo. <em>Ohne Konto.</em></h1><p class="lead">Kein Studi-Rabatt nötig: inlaut kostet nichts. Für Apple-Silicon-Macs ab macOS 26.</p><span class="pill">inlaut.de · Link in Bio</span>', ""),
],
"5-homeoffice": [
  cover("Im Homeoffice", "Weniger tippen. <em>Mehr erledigen.</em>"),
  ("light", '<p class="eyebrow">Wofür?</p><h2>Der Kleinkram <em>zwischen den Calls.</em></h2>' + items(
      "Mails beantworten", "Nachrichten in Teams oder Slack", "Notizen direkt nach dem Meeting", "Tickets und Protokolle"), ""),
  ("light", '<p class="eyebrow">Beispiel</p><h2>Antwort in <em>zehn Sekunden.</em></h2>' + window("Re: Zahlen für Q3", [
      "Hallo Jana,", "danke für das Update. Ich schaue mir die Zahlen bis morgen an und melde mich dann bei dir.", "Viele Grüße"]), ""),
  ("dark", '<h2>Funktioniert in jeder App. <em>Dort, wo dein Cursor ist.</em></h2><p class="lead">Mail, Teams, Slack, Word oder Browser: inlaut fügt den Text dort ein, wo du gerade schreibst.</p><span class="pill">inlaut.de · Link in Bio</span>', ""),
],
"6-ki-prompts": [
  cover("Für KI-Nutzer", "Bessere Prompts. <em>Einfach gesprochen.</em>"),
  ("light", '<p class="eyebrow">Warum sprechen?</p><h2>Gute Prompts brauchen <em>Kontext.</em></h2><p class="lead">Beim Sprechen gibst du ihn ganz nebenbei – ausführlicher, als du ihn je tippen würdest.</p>'
      '<div class="chips"><span class="chip">ChatGPT</span><span class="chip">Claude</span><span class="chip">Gemini</span><span class="chip">Cursor</span><span class="chip">Claude Code</span></div>', ""),
  ("light", '<p class="eyebrow">Beispiel</p><h2>Einfach erzählen, <em>was du willst.</em></h2>' + window("Neuer Chat", [
      "Schreib mir eine kurze Einladung für das Team-Frühstück am Freitag um neun. Locker, aber nicht zu flapsig, und erwähne, dass jeder etwas mitbringen kann."]), ""),
  ("dark", '<h2>Dein Prompt bleibt bei dir – <em>bis du ihn abschickst.</em></h2><p class="lead">inlaut erkennt deine Sprache lokal. Was du an die KI schickst, entscheidest du selbst.</p><span class="pill">inlaut.de · Link in Bio</span>', ""),
],
"7-selbststaendige": [
  cover("Für Selbstständige", "Notizen nach dem Kundentermin? <em>In einer Minute.</em>"),
  ("light", '<p class="eyebrow">Wofür?</p><h2>Weniger Büro. <em>Mehr Kunde.</em></h2>' + items(
      "Gesprächsnotizen direkt nach dem Termin", "Angebote und Mails vorformulieren", "Ideen festhalten, bevor sie weg sind"), ""),
  ("dark", '<p class="eyebrow">Vertraulich</p><h2>Kundendaten bleiben <em>auf deinem Mac.</em></h2><p class="lead">Die Spracherkennung läuft lokal. Kein Server verarbeitet oder speichert deine Diktate.</p>', ""),
  CTA,
],
"8-tippen-faellt-schwer": [
  cover("Wenn Tippen schwerfällt", "Müde Hände? <em>Sprich, statt zu tippen.</em>", "Ob Sehnenscheide, Gips oder einfach ein langer Tag."),
  ("light", '<p class="eyebrow">So geht’s</p><h2>Eine Taste. <em>Oder gar keine.</em></h2><div class="steps"><div class="step"><span class="num">1</span>🌐 halten und sprechen</div>'
      '<div class="step"><span class="num">2</span>Zweimal tippen: freihändig</div><div class="step"><span class="num">3</span>Absätze per Sprache</div></div>', ""),
  CTA,
],

# Tipps
"9-tipp-absaetze": [
  cover("Tipp", "Absätze? <em>Einfach sagen.</em>"),
  ("light", '<p class="eyebrow">Du sagst</p><div class="say"><q>Hallo Frau Becker, neuer Absatz, vielen Dank für Ihre Nachricht. Neue Zeile, ich melde mich morgen.</q></div><div class="arrow">↓ inlaut schreibt</div>'
      + window("Mail", ["Hallo Frau Becker,", "vielen Dank für Ihre Nachricht.<br>Ich melde mich morgen."], listening=False), ""),
  ("dark", '<h2>„neue Zeile“ und <em>„neuer Absatz“.</em></h2><p class="lead">Lässt sich in den Einstellungen unter „Zeilen und Absätze per Sprache“ an- und ausschalten.</p><span class="pill">inlaut.de · Link in Bio</span>', ""),
],
"10-tipp-ersetzungen": [
  cover("Tipp", "Dein Fachwort. <em>Immer richtig geschrieben.</em>"),
  ("light", '<p class="eyebrow">Ersetzungen</p><h2>Einmal festlegen. <em>Fertig.</em></h2><p class="lead">Schreibt die Erkennung ein Wort regelmäßig anders, als du es willst, legst du einmal eine Ersetzung an.</p>'
      '<div class="chips"><span class="chip">kuber netes → <b>Kubernetes</b></span><span class="chip">inlaut punkt de → <b>inlaut.de</b></span><span class="chip">post gres → <b>Postgres</b></span></div><p class="label">Beispiele</p>', ""),
  ("dark", '<h2>Ganze Wörter. <em>Groß und klein egal.</em></h2><p class="lead">Ersetzungen gelten nach jedem Diktat – für Namen, Produkte und Abkürzungen aus deinem Alltag.</p><span class="pill">inlaut.de · Link in Bio</span>', ""),
],
"11-tipp-freihaendig": [
  cover("Tipp", "Lange Texte? <em>Hände weg von der Tastatur.</em>"),
  ("light", '<p class="eyebrow">Freihändig diktieren</p><h2>Zweimal tippen. <em>Lossprechen.</em></h2><div class="steps"><div class="step"><span class="num">1</span>2× auf 🌐 tippen: Aufnahme läuft</div>'
      '<div class="step"><span class="num">2</span>In Ruhe sprechen</div><div class="step"><span class="num">3</span>1× tippen: Text wird eingefügt</div></div>', ""),
  ("dark", '<h2>Ideal für <em>lange Gedanken.</em></h2><p class="lead">Lange Diktate teilt inlaut an Sprechpausen auf und erkennt sie Stück für Stück – auf deinem Mac.</p><span class="pill">inlaut.de · Link in Bio</span>', ""),
],
}

# Stories (1080x1920). Top ~250 px and bottom ~340 px stay free for Instagram's own UI.
STORY_CSS = CSS.replace("height: 1350px", "height: 1920px") + """
.slide { padding: 260px 96px 360px; }
h1 { font-size: 112px; } h2 { font-size: 88px; }
.top { position: absolute; top: 150px; left: 96px; right: 96px; }
.foot { position: absolute; bottom: 300px; left: 96px; right: 96px; font-size: 32px; }
"""

def story(theme, body):
    logo = "inlaut-logo-mint.svg" if theme == "dark" else "inlaut-logo-petrol.svg"
    return (f'<!doctype html><html lang="de"><meta charset="utf-8"><style>{STORY_CSS}</style><body>'
            f'<div class="slide {theme}"><div class="top"><img src="{KIT}/{logo}" alt=""></div>'
            f'<div class="body">{body}</div><div class="foot"><span>inlaut.de</span><span></span></div></div></body></html>')

STORIES = {
"story-1-neu": ("dark", f'{SYMBOL}<span class="tag">Neu</span><h1>Diktieren am Mac. <em>Ohne Cloud.</em></h1><p class="lead">inlaut schreibt, was du sagst – direkt dort, wo dein Cursor steht.</p>'),
"story-2-so-gehts": ("light", '<p class="eyebrow">So geht’s</p><h2>Drei Schritte.</h2><div class="steps"><div class="step"><span class="num">1</span>🌐-Taste halten</div>'
    '<div class="step"><span class="num">2</span>Sprechen</div><div class="step"><span class="num">3</span>Loslassen – fertig</div></div>'),
"story-3-sz": ("dark", '<span class="tag">Neu in 0.1.1</span><h1>Straße statt <em>Strasse.</em></h1><p class="lead">inlaut schreibt eindeutige Wörter wie Straße, groß oder Grüße jetzt mit ß.</p>'),
"story-4-download": ("dark", f'{SYMBOL}<h1>Kostenlos.<br><em>Open Source.</em></h1><p class="lead">Für Apple-Silicon-Macs ab macOS 26.</p><span class="pill">inlaut.de</span>'),
}

# WhatsApp status (1080x1920), shared privately by the maintainer. WhatsApp puts its
# header over the top ~220 px and the reply field over the bottom ~260 px.
WA_CSS = STORY_CSS + """
.wa { padding: 0; }
.glow { position: absolute; left: -140px; top: 330px; width: 1360px; opacity: .07; }
.wa-top { position: absolute; top: 250px; left: 96px; right: 96px; }
.wa-top img { height: 52px; }
.wa-body { position: absolute; left: 96px; right: 96px; top: 430px; }
.wa-symbol { width: 300px; filter: drop-shadow(0 0 40px rgba(188,235,217,.45)); margin-bottom: 56px; }
.wa h1 { font-size: 124px; }
.ticks { margin-top: 64px; display: flex; flex-direction: column; gap: 26px; }
.tick { display: flex; gap: 24px; align-items: center; font-size: 44px; font-weight: 500; }
.tick b { width: 60px; height: 60px; border-radius: 50%; display: grid; place-items: center; font-size: 32px; background: #BCEBD9; color: #103D3B; }
.url { position: absolute; left: 96px; right: 96px; bottom: 300px; display: flex; align-items: center; justify-content: space-between;
  padding: 34px 44px; border-radius: 40px; background: #BCEBD9; color: #103D3B; }
.url span { font-size: 30px; font-weight: 500; line-height: 1.3; }
.url strong { font-size: 76px; font-weight: 700; letter-spacing: -0.04em; }
.photo { position: absolute; left: 0; top: 0; width: 1080px; height: 960px; overflow: hidden; }
.photo img { position: absolute; height: 960px; top: 0; }
.photo::after { content: ""; position: absolute; inset: 0;
  background: linear-gradient(to bottom, rgba(16,61,59,.55) 0, rgba(16,61,59,0) 26%, rgba(16,61,59,0) 55%, #103D3B 92%); }
.ki { position: absolute; z-index: 2; left: 96px; top: 340px; font-size: 26px; font-weight: 600; padding: 10px 20px;
  border-radius: 999px; background: rgba(12,32,31,.72); color: #F6F7F4; }
.persona-text { position: absolute; left: 96px; right: 96px; top: 830px; }
.who { font-size: 30px; font-weight: 600; color: #BCEBD9; margin-bottom: 20px; }
.persona-text h2 { font-size: 84px; }
.persona-text .ticks { margin-top: 44px; gap: 20px; }
.persona-text .tick { font-size: 38px; }
.persona-text .tick b { width: 52px; height: 52px; font-size: 28px; }
"""

def wa(body):
    return (f'<!doctype html><html lang="de"><meta charset="utf-8"><style>{WA_CSS}</style><body>'
            f'<div class="slide dark wa">{body}</div></body></html>')

def ticks(*rows):
    return '<div class="ticks">' + "".join(f'<div class="tick"><b>✓</b>{r}</div>' for r in rows) + "</div>"

def persona(name, left, who, headline, *rows):
    # left shifts the 1286 px wide photo so the face stays clear of the KI label.
    return wa(f'<div class="photo"><img src="{PERSONAS}/{name}.webp" style="left:{left}px" alt=""></div>'
              f'<span class="ki">KI-generiertes Bild</span><div class="persona-text"><p class="who">{who}</p>'
              f'<h2>{headline}</h2>' + ticks(*rows) + "</div>" + URL)

URL = '<div class="url"><span>Kostenlos für<br>Apple-Silicon-Macs</span><strong>inlaut.de</strong></div>'

WHATSAPP = {
"status-1-grafik": wa(
    f'<img class="glow" src="{KIT}/inlaut-symbol-mint.svg" alt="">'
    f'<div class="wa-top"><img src="{KIT}/inlaut-logo-mint.svg" alt=""></div>'
    f'<div class="wa-body"><img class="wa-symbol" src="{KIT}/inlaut-symbol-mint.svg" alt="">'
    '<h1>Sprechen<br><em>statt tippen.</em></h1>'
    '<p class="lead">Taste halten, sprechen, loslassen – inlaut schreibt deinen Text direkt in jede App auf dem Mac.</p>'
    + ticks("Läuft lokal, ohne Cloud", "Kostenlos &amp; Open Source", "Auf Deutsch abgestimmt") + "</div>" + URL),
"status-2-valerie": persona("valerie", -200, "Valerie · Vertrieb, viel unterwegs", "Mails am Gate.<br><em>Auch ohne Netz.</em>",
    "Diktieren in jeder App", "Erkennung lokal auf dem Mac", "Funktioniert offline", "Kostenlos, ohne Konto"),
"status-3-hanna": persona("hanna", -110, "Hanna · Biobäuerin mit Hofladen", "Hofladen-Posts.<br><em>Auch im Funkloch.</em>",
    "Texte einfach einsprechen", "Funktioniert ohne Internet", "Erkennung lokal auf dem Mac", "Kostenlos, ohne Konto"),
"status-4-lukas": persona("lukas", 0, "Lukas · Werkstudent im Startup", "Fachbegriffe?<br><em>Immer richtig.</em>",
    "Ersetzungen für Namen und Fachwörter", "Diktieren in jeder App", "Erkennung lokal auf dem Mac", "Kostenlos, ohne Konto"),
}

PROFILE = (f'<!doctype html><html><meta charset="utf-8"><style>html,body{{margin:0;width:1080px;height:1080px;background:#103D3B}}'
           f'body{{display:grid;place-items:center}} img{{width:600px}}</style><body><img src="{KIT}/inlaut-symbol-mint.svg" alt=""></body></html>')

def render(html, name, w=1080, h=1350, out=OUT):
    out.mkdir(exist_ok=True)
    src = out / f".{name}.html"
    src.write_text(html)
    subprocess.run([CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--force-device-scale-factor=1",
                    "--allow-file-access-from-files", f"--window-size={w},{h}", f"--screenshot={out / (name + '.png')}",
                    src.as_uri()], check=True, capture_output=True)
    src.unlink()

if __name__ == "__main__":
    only = sys.argv[1:]
    for post, slides in POSTS.items():
        if only and post not in only:
            continue
        for i, (theme, body, right) in enumerate(slides, 1):
            render(page(theme, i, len(slides), body, right), f"{post}-{i}")
    for name, (theme, body) in STORIES.items():
        if not only or name in only or "stories" in only:
            render(story(theme, body), name, 1080, 1920, HERE / "stories")
    for name, html in WHATSAPP.items():
        if not only or name in only or "whatsapp" in only:
            render(html, name, 1080, 1920, HERE.parent / "whatsapp")
    if not only or "profil" in only:
        render(PROFILE, "profil", 1080, 1080, HERE)
    print("ok")
