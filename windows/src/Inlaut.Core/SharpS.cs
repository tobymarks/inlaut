using System.Text;

namespace Inlaut.Core;

/// Restores ß where the recogniser writes ss. Mirrors Sources/SharpS.swift:
/// keep the rule list, anchors and exceptions identical on both platforms
/// (TestData/text-pipeline.json runs shared cases from both test runners).
///
/// Only word parts whose ss spelling is never correct in standard German are
/// listed. They also match inside compounds ("Hauptstrasse", "regelmässig"),
/// so each part is anchored as tightly as needed to stay clear of compound
/// joints such as "Hinweis|schild" or "aus|senden". Pairs where both spellings
/// are words (Masse/Maße, Busse/Buße, floss/Floß) are left alone.
public static class SharpS
{
    private enum Anchor { Anywhere, Start, StartOrEnd, Word }

    private sealed class Rule
    {
        public string Key { get; }          // lowercase, as recognised
        public int SharpSIndex { get; }     // offset of the ss in Key
        public Anchor AnchorType { get; }
        public string[] Unless { get; }     // words containing one of these stay as they are

        public Rule(string spelled, Anchor anchor = Anchor.Anywhere, string[]? unless = null)
        {
            SharpSIndex = spelled.IndexOf('ß');
            Key = spelled.Replace("ß", "ss");
            AnchorType = anchor;
            Unless = unless ?? Array.Empty<string>();
        }
    }

    private static readonly Rule[] Rules =
    [
        // Adjectives and adverbs
        new("groß", unless: ["grossist"]),  // großartig, Großstadt, riesengroß
        new("größ"),                        // größer, Größe, größtenteils
        new("bloß", unless: ["blossom"]),
        new("heiß"),                        // heißen, heißt, verheißen, Scheiße
        new("süß"),                         // Süßigkeiten, Süßwasser
        new("fleiß"),
        new("gemäß"),                       // zeitgemäß, ordnungsgemäß
        new("mäßig"),                       // regelmäßig, mäßigen
        new("weiß", Anchor.StartOrEnd, unless: ["weissag"]),  // weißt, Weißwein, Eiweiß – not Hinweis|schild
        new("schweiß"),                     // schweißen
        new("außen", Anchor.Start, unless: ["aussende", "aussendung", "aussenk"]),  // not aus|senden
        new("außer", Anchor.Start),         // außerdem, außerhalb
        new("draußen", Anchor.Word),
        new("äuß"),                         // äußern, äußerst, Äußerung
        // Nouns
        new("straße", unless: ["gleistrass", "keitstrass"]),  // Hauptstraße – not Gleis|trasse
        new("fuß", unless: ["fussel"]),     // Fußball, barfuß
        new("füße", Anchor.Word),           // not the town Füssen
        new("gruß"),
        new("grüß", unless: ["rüssel"]),    // grüßen, Grüße – not Saug|rüssel
        new("spaß", Anchor.Start),          // spaßig, Spaßvogel – not Gesundheits|pass, Einkaufs|passage
        new("späß", Anchor.Start),
        new("riesenspaß"),                  // X|spaß and Xs|pass look alike, so only the usual compounds
        new("heidenspaß"),
        new("mordsspaß"),
        new("fahrspaß"),
        new("spielspaß"),
        new("badespaß"),
        new("ferienspaß"),
        new("maßnahm"),
        new("maßstab"),
        new("maßgeb"),                      // maßgeblich, maßgebend
        new("maßgeschneider"),
        new("maßeinheit"),
        new("ausmaß"),
        new("übermaß"),
        new("gefäß"),
        new("spieß"),                       // spießig
        new("soße"),
        new("stoß"),                        // anstoßen, Zusammenstoß
        new("stöß"),
        new("reißverschluss"),              // reiß alone would hit Preis|senkung
        // Verbs with a long vowel before the ß
        new("ließ", unless: ["vliess"]),    // ließ, schließen, fließend, verließ – not Vlies|stoff
        new("hieß"),                        // hieß, schießen
        new("gieß"),
        new("genieß"),
        new("beiß"),
    ];

    public static string Apply(string text)
    {
        if (string.IsNullOrEmpty(text)) return text;

        // Apply word anchors to letters, not punctuation or the line breaks
        // already produced by voice commands. Keep every separator unchanged.
        // Words are runs of letters counted in Unicode scalars, as \p{L}+ does
        // on the Mac: a combining mark ends a word, a letter outside the BMP does not.
        var result = new StringBuilder(text.Length);
        int index = 0;
        while (index < text.Length)
        {
            int start = index;
            bool letters = IsLetterAt(text, index, out int length);
            while (index < text.Length && IsLetterAt(text, index, out length) == letters) index += length;
            var piece = text[start..index];
            result.Append(letters ? Correct(piece) : piece);
        }
        return result.ToString();
    }

    private static bool IsLetterAt(string text, int index, out int length)
    {
        // An unpaired surrogate decodes as a one-unit replacement character, not a letter.
        Rune.DecodeFromUtf16(text.AsSpan(index), out var rune, out length);
        return Rune.IsLetter(rune);
    }

    private static string Correct(string word)
    {
        var lower = word.ToLowerInvariant();
        // Lowercasing may change the length (rare ligatures); leave such words alone.
        if (lower.Length != word.Length || lower.Length < 4) return word;

        // Every rule and every occurrence counts ("Grossstrasse" has two),
        // not only the first match.
        var sharp = new HashSet<int>();  // index of the first s of each ss to replace
        foreach (var rule in Rules)
        {
            if (rule.Unless.Any(u => lower.Contains(u, StringComparison.Ordinal))) continue;
            for (int start = lower.IndexOf(rule.Key, StringComparison.Ordinal); start >= 0;
                 start = lower.IndexOf(rule.Key, start + 1, StringComparison.Ordinal))
            {
                if (Fits(rule.AnchorType, start, rule.Key.Length, lower.Length))
                    sharp.Add(start + rule.SharpSIndex);
            }
        }
        if (sharp.Count == 0) return word;

        var result = new System.Text.StringBuilder(word.Length);
        for (int index = 0; index < word.Length; index++)
        {
            // Capitals keep SS, the usual spelling of ß in uppercase text.
            if (sharp.Contains(index) && index + 1 < word.Length && word[index] == 's' && word[index + 1] == 's')
            {
                result.Append('ß');
                index++;
            }
            else
            {
                result.Append(word[index]);
            }
        }
        return result.ToString();
    }

    private static bool Fits(Anchor anchor, int start, int length, int total) => anchor switch
    {
        Anchor.Anywhere => true,
        Anchor.Start => start == 0,
        Anchor.StartOrEnd => start == 0 || start + length == total,
        Anchor.Word => start == 0 && length == total,
        _ => true
    };
}
