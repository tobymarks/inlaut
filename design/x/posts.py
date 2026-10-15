"""Posts for the X account @inlautapp (English only since 2026-10-12): video, text, AI label, schedule.

`python3 posts.py` checks the lengths (X counts a link as 23, an emoji as 2).
`when` None = posted right away, otherwise the scheduled date (17:00 CEST).
POSTS_DE is the German launch set from 2026-10-11 (removed from X when the account went English).
"""
import json, re, sys

P = "\n\n(KI-generierte Persona. Die App ist echt.)"

POSTS_DE = [
    ("14-animiert-so-gehts", False, None,
     "Hallo X 👋\n\ninlaut ist eine kleine Diktier-App für die Mac-Menüleiste: Taste halten, sprechen, loslassen – der Text steht am Cursor, in jeder App.\n\nAlles läuft lokal auf dem Mac. Kein Konto, keine Cloud, kein Abo. Kostenlos und Open Source.\n\nhttps://inlaut.de"),
    ("01-juna-kurzvorstellung", True, None,
     "Diktieren am Mac: kostenlos, lokal, ohne Cloud. 🎙️\n\nJuna zeigt in 30 Sekunden, worum es bei inlaut geht: Taste halten, sprechen, loslassen, und der Text steht da." + P + "\n\n#macOS #Diktieren"),
    ("15-animiert-wo-landen-deine-worte", False, None,
     "Wenn du diktierst: Wo landen eigentlich deine Worte? 🤔\n\nBei inlaut bleiben sie auf deinem Mac. Die Spracherkennung läuft lokal, nichts wird übertragen, und das Mikrofon ist nur an, solange du diktierst.\n\n#Datenschutz #macOS"),
    ("07-henriette-autorin", True, "2026-10-12",
     "Das nächste Kapitel? Nicht geschrieben, sondern erzählt. 📖\n\nHenriette spricht einfach, und inlaut macht daraus Text. Mit „neuer Absatz“ gleich mit Struktur. Die Erkennung läuft komplett auf dem Mac." + P + "\n\n#Schreiben #macOS"),
    ("06-mehmet-werkstatt", True, "2026-10-13",
     "Den ganzen Tag gehobelt und abends noch drei Angebote tippen? Nee. 🪵\n\nMehmet redet einfach: Taste halten, sprechen, loslassen, und der Text steht in der Mail. Ohne Abo, ohne Cloud." + P + "\n\n#Handwerk #macOS"),
    ("16-animiert-drei-tricks", False, "2026-10-14",
     "Drei Tricks für inlaut:\n\n1. „Neuer Absatz“ sagen, und der Text bekommt Struktur.\n2. Zweimal auf 🌐 tippen und freihändig diktieren.\n3. Ein Wort wird falsch erkannt? Ersetzung anlegen, dann stimmt es jedes Mal.\n\nKostenlos, Link im Profil.\n\n#macOS #Diktieren"),
    ("03-valerie-flughafen", True, "2026-10-15",
     "Boarding in zwanzig Minuten, und die Mail ist trotzdem raus. ✈️\n\nValerie diktiert am Gate. Weil die Spracherkennung lokal auf dem Mac läuft, klappt das auch ohne WLAN: am Flughafen, im Zug, im Flugzeug." + P + "\n\n#Offline #macOS"),
    ("05-tarek-entwickler", True, "2026-10-16",
     "Commit-Message, Ticket, Slack-Antwort? Einfach sprechen. 💻\n\nTarek diktiert beim Entwickeln. Die Erkennung läuft lokal auf dem Mac, ohne Server und ohne Konto. Der Code liegt offen auf GitHub." + P + "\n\n#OpenSource #macOS"),
    ("09-selin-coach", True, "2026-10-17",
     "Die besten Gedanken kommen beim Reden. Nicht beim Tippen. 💬\n\nSelin tippt zweimal auf die fn-Taste und spricht ihre Notizen frei in jede App. Die Erkennung läuft auf dem Mac, sogar ohne Internet." + P + "\n\n#Notizen #macOS"),
    ("17-animiert-startklar", False, "2026-10-18",
     "So ist inlaut startklar:\n\n1. App laden und in „Programme“ ziehen.\n2. Beim ersten Start lädt sie einmal das Sprachmodell und fragt nach Mikrofon und Bedienungshilfen.\n3. Taste halten, sprechen, loslassen.\n\nFür Macs mit Apple Silicon ab macOS 26. Link im Profil."),
    ("10-hanna-funkloch", True, "2026-10-19",
     "Funkloch auf dem Hof? Ganz normal. Die Texte entstehen trotzdem. 🚜\n\nHanna spricht Newsletter und Posts für den Hofladen einfach ein. Einmal eingerichtet, läuft inlaut direkt auf dem Mac, auch ohne Internet." + P + "\n\n#Offline #macOS"),
    ("04-markus-homeoffice", True, "2026-10-20",
     "Zwischen zwei Calls noch schnell eine Mail? Einfach sprechen. 🎧\n\nMarkus diktiert im Homeoffice in Mail, Teams oder Slack. Weil die Erkennung lokal auf dem Mac läuft, bleiben auch vertrauliche Themen bei ihm." + P + "\n\n#Homeoffice #macOS"),
    ("12-albers-zeugnisse", True, "2026-10-21",
     "Sonntagabend, zweiundzwanzig Zeugnisse. Tippen? Nicht mehr. 📝\n\nHerr Albers spricht die Bemerkungen einfach ein. Alles bleibt auf seinem Mac, und das Mikrofon ist nur beim Diktieren an." + P + "\n\n#Lehrer #macOS"),
    ("02-creatorin-taste-halten", True, "2026-10-22",
     "Taste halten, sprechen, loslassen, und der Text steht da. ✨\n\nSo einfach ist Diktieren mit inlaut: in Mail, Notizen, Word, Teams oder im KI-Chat. Keine Cloud, kein Konto, kostenlos und Open Source." + P + "\n\n#Produktivität #macOS"),
    ("11-lukas-ersetzungen", True, "2026-10-23",
     "Fachbegriffe, Kundennamen, der eigene Produktname. Ständig falsch geschrieben?\n\nLukas legt in inlaut eigene Ersetzungen an. Einmal eintragen, fertig. Geht in jeder App, und alles bleibt auf dem Mac." + P + "\n\n#Startup #macOS"),
    ("13-ruth-predigt", True, "2026-10-24",
     "Eine Predigt entsteht beim Sprechen. Warum sie dann tippen? ⛪\n\nRuth diktiert sie direkt in den Entwurf, den Gemeindebrief gleich mit. Namen aus der Gemeinde legt sie als Ersetzung an, dann stimmt jede Schreibweise." + P + "\n\n#Kirche #macOS"),
    ("08-juna-tagebuch-noch-nicht-gepostet", True, "2026-10-25",
     "Abends noch die Gedanken des Tages festhalten, ohne zu tippen. 📓\n\nJuna tippt zweimal auf fn und spricht ihr Tagebuch einfach ein. Die Spracherkennung läuft auf ihrem Mac, nichts wird übertragen." + P + "\n\n#Journaling #macOS"),
]

# Videos live in ~/Movies/inlaut-promo/finale-videos/en/.
POSTS = [
    ("en/14-animated-how-it-works", False, None,
     "Meet inlaut 👋\n\nA small dictation app for the Mac menu bar: hold a key, speak, let go – your text lands at the cursor, in any app.\n\nEverything runs locally on your Mac. No account, no cloud, no subscription. Free and open source.\n\nhttps://inlaut.de/en"),
    ("en/15-animated-where-do-your-words-go", False, None,
     "When you dictate, where do your words actually go? 🤔\n\nWith inlaut they stay on your Mac. Speech recognition runs locally, nothing is uploaded, and the microphone is only on while you dictate.\n\n#macOS #privacy"),
    ("en/16-animated-three-tricks", False, "2026-10-13",
     "Three tricks for inlaut:\n\n1. Say “new paragraph” and your text gets structure.\n2. Double-tap 🌐 and dictate hands-free.\n3. A word keeps coming out wrong? Add a replacement and it's right every time.\n\nFree, link in bio.\n\n#macOS #dictation"),
    ("en/17-animated-getting-started", False, "2026-10-14",
     "Getting started with inlaut:\n\n1. Download the app and drag it into Applications.\n2. On first launch it downloads the speech model once and asks for microphone and accessibility access.\n3. Hold a key, speak, let go.\n\nFor Macs with Apple silicon on macOS 26 or later. Link in bio."),
]

def weight(t):
    t = re.sub(r"https?://\S+", "x" * 23, t)
    return sum(2 if ord(c) > 0x2000 and c not in "–„“”" else 1 for c in t)

if __name__ == "__main__":
    if len(sys.argv) > 1:
        print(json.dumps([p for p in POSTS if sys.argv[1] in p[0]][0][3]))
    else:
        for v, ai, when, t in POSTS:
            print(f"{weight(t) if t else '--':>4} {when or 'now':10} {'AI' if ai else '  '} {v}")
