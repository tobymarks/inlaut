using Inlaut.Core;
using Inlaut.Platform.Windows;
using System.Text.Json;

namespace Inlaut.UiSmoke;

internal static class TransitionChecks
{
    // Native editor integration probes. Desired formatting is deliberately recorded
    // separately from transport preservation: issue #20 is not silently marked fixed.
    public static async Task Run(Form host)
    {
        using var editor = new RichTextBox { Dock = DockStyle.Fill }; host.Controls.Add(editor); host.Show(); host.Activate();
        var pipeline = new TextPipeline(); var results = new List<object>(); int gaps = 0;
        var cases = new (string Name, string Before, string Next, string Desired)[]
        {
            ("sentence-no-space", "Das ist fertig.", "morgen geht es weiter.", "Das ist fertig. Morgen geht es weiter."),
            ("sentence-with-space", "Das ist fertig. ", "morgen geht es weiter.", "Das ist fertig. Morgen geht es weiter."),
            ("continuation", "Ich freue mich", "auf morgen.", "Ich freue mich auf morgen."),
            ("already-spaced", "Ich freue mich ", "auf morgen.", "Ich freue mich auf morgen."),
            ("line-command", "Erster Absatz.", "neue Zeile Zweite Zeile.", "Erster Absatz.\nZweite Zeile."),
            ("paragraph-command", "Erster Absatz.", "neuer Absatz Zweiter Absatz.", "Erster Absatz.\n\nZweiter Absatz."),
            ("standalone-line", "Erster Absatz.", "neue Zeile", "Erster Absatz.\n"),
            ("standalone-paragraph", "Erster Absatz.", "neuer Absatz", "Erster Absatz.\n\n"),
            ("trailing-paragraph", "Start: ", "Absatz Ende neuer Absatz", "Start: Absatz Ende\n\n"),
            ("existing-newline", "Erste Zeile.\n", "zweite Zeile.", "Erste Zeile.\nZweite Zeile."),
            ("decimal", "Der Wert ist ", "3,14 Euro.", "Der Wert ist 3,14 Euro."),
            ("domain", "Die Adresse ist ", "inlaut.de.", "Die Adresse ist inlaut.de."),
            ("abbreviation", "Termin bei Dr. ", "Müller.", "Termin bei Dr. Müller."),
            ("punctuation", "Wirklich? ", "Ja!", "Wirklich? Ja!"),
            ("unicode", "Grüße an ", "Jörg und Zoë 😊", "Grüße an Jörg und Zoë 😊")
        };
        foreach (var test in cases)
        {
            editor.Clear(); editor.Focus(); await Task.Delay(40); var target = DirectTextInserter.CaptureTarget();
            await DirectTextInserter.InsertAsync(test.Before, expectedTarget: target);
            string next = pipeline.ProcessDictation(test.Next); await DirectTextInserter.InsertAsync(next, expectedTarget: target);
            string actual = editor.Text.ReplaceLineEndings("\n"), preserved = (test.Before + next).ReplaceLineEndings("\n");
            if (actual != preserved) throw new Exception("Transition transport corruption: " + test.Name);
            bool desired = actual == test.Desired; if (!desired) gaps++;
            results.Add(new { test.Name, actual, expected = test.Desired, desiredFormatting = desired });
        }
        editor.Text = "Hallo falsches Wort Ende"; editor.Select(6, 13); editor.Focus();
        await DirectTextInserter.InsertAsync("richtig", expectedTarget: DirectTextInserter.CaptureTarget());
        if (editor.Text != "Hallo richtig Ende") throw new Exception("Selection replacement differs");
        editor.Text = "Links rechts"; editor.Select(6, 0); editor.Focus();
        await DirectTextInserter.InsertAsync("Mitte ", expectedTarget: DirectTextInserter.CaptureTarget());
        if (editor.Text != "Links Mitte rechts") throw new Exception("Moved cursor differs");
        File.WriteAllText(Path.Combine(AppContext.BaseDirectory, "transition-results.json"), JsonSerializer.Serialize(new { cases = results, gaps, selectionAndCursor = "passed" }, new JsonSerializerOptions { WriteIndented = true }));
        Console.WriteLine($"PASS: {cases.Length} real native two-insertion cases preserve content; selection replacement and cursor movement pass. {gaps} formatting gaps remain tracked in #20.");
        host.Controls.Remove(editor);
    }
}
