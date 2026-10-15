using System.Diagnostics;
using System.Text.Json;
using Inlaut.Core;
using Inlaut.Platform.Windows;

namespace Inlaut.App;

internal sealed class UpdateForm : FluentForm
{
    private readonly Label _status = new() { AutoSize = true, MaximumSize = new Size(490, 0) };
    private readonly Button _install = new() { Text = UiText.Get("Herunterladen und installieren"), AutoSize = true, AutoSizeMode = AutoSizeMode.GrowAndShrink, Enabled = false };
    private readonly ProgressBar _progress = new() { Width = 450 };
    private readonly CancellationTokenSource _cancel = new();
    private readonly Action _exit;
    private readonly Func<bool> _canInstall;
    private readonly bool _beta;
    private bool _working;
    private UpdateManifest? _manifest;
    internal static string CacheRoot => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "inlaut", "updates");
    public UpdateForm(bool beta, Func<bool> canInstall, Action exit, UpdateManifest? available = null)
    {
        _beta = beta; _canInstall = canInstall; _exit = exit; _manifest = available;
        SuspendLayout(); AutoScaleDimensions = new SizeF(96, 96); AutoScaleMode = AutoScaleMode.Dpi;
        Text = "inlaut — Updates"; Font = WindowsTheme.Font(); ClientSize = new Size(540, 330); MinimumSize = new Size(540, 330); StartPosition = FormStartPosition.CenterScreen;
        var body = new FlowLayoutPanel { Dock = DockStyle.Fill, Padding = new Padding(20), FlowDirection = FlowDirection.TopDown, WrapContents = false, AutoScroll = true };
        body.Controls.Add(new Label { Text = UiText.Get("Installiert: ") + LocalDiagnostics.Version.Split('+')[0], AutoSize = true });
        body.Controls.Add(_status); body.Controls.Add(_progress); body.Controls.Add(_install);
        body.Controls.Add(new Label { AutoSize = true, MaximumSize = new Size(490, 0), Text = UiText.Get("Die Suche verbindet sich mit inlaut.de. Ein Download erfolgt von GitHub. Dabei fallen Verbindungsdaten an, keine Diktate. Installation erst nach deinem Klick; inlaut startet anschließend neu. Einstellungen bleiben erhalten.") });
        var close = new Button { Text = UiText.Get("Schließen / Abbrechen"), AutoSize = true, AutoSizeMode = AutoSizeMode.GrowAndShrink }; close.Click += (_, _) => Close(); body.Controls.Add(close); Controls.Add(body);
        _install.Click += async (_, _) => await Install();
        Shown += async (_, _) => { if (_manifest != null) ShowAvailable(); else await Check(); };
        FormClosed += (_, _) => _cancel.Cancel();
        ResumeLayout(true);
    }
    private void ShowAvailable()
    {
        _status.Text = "Version " + _manifest!.Version + UiText.Get(" verfügbar · ") + (_manifest.Size / 1048576d).ToString("F0") + " MB";
        _install.Enabled = true;
    }
    private async Task Check()
    {
        _status.Text = UiText.Get("Suche nach Updates…");
        try
        {
            using var client = new UpdateClient(); _manifest = await client.Check(_beta, _cancel.Token);
            if (IsDisposed) return;
            if (_manifest == null) _status.Text = UiText.Get("Für diesen Kanal ist noch kein Windows-Update veröffentlicht.");
            else if (!_manifest.IsNewer(LocalDiagnostics.Version.Split('+')[0], _beta)) _status.Text = UiText.Get("Du verwendest die aktuelle Version dieses Kanals.");
            else ShowAvailable();
        }
        catch (Exception ex) { if (!IsDisposed) _status.Text = UiText.Get("Update-Suche nicht möglich: ") + UiText.Get(ex.Message); }
    }
    private async Task Install()
    {
        if (_working || _manifest == null) return;
        if (!_canInstall()) { _status.Text = UiText.Get("Bitte Diktat beenden und Einstellungen schließen, dann erneut versuchen."); return; }
        _working = true; _install.Enabled = false; string? folder = null; bool handedOff = false;
        try
        {
            // An unsigned development build must never bootstrap a trusted update.
            try { await Task.Run(() => UpdateSecurity.TrustedCertificate(Application.ExecutablePath), _cancel.Token); }
            catch (InvalidOperationException) { throw new InvalidOperationException(UiText.Get("Diese Installation hat noch keine bestätigte Windows-Signatur. Der sichere Updateweg beginnt mit der ersten signierten inlaut-Version. Es wurde nichts heruntergeladen.")); }
            folder = Path.Combine(CacheRoot, "pending-" + Guid.NewGuid().ToString("N")); Directory.CreateDirectory(folder);
            string installer = Path.Combine(folder, "update.exe"); _status.Text = UiText.Get("Update wird geladen…");
            using var client = new UpdateClient();
            await client.Download(_manifest, installer, new Progress<int>(p => { if (!IsDisposed) _progress.Value = p; }), _cancel.Token);
            _status.Text = UiText.Get("Windows-Signatur und Prüfsumme werden geprüft…");
            await Task.Run(() => UpdateSecurity.VerifyPackage(installer, _manifest, Application.ExecutablePath), _cancel.Token);
            _cancel.Token.ThrowIfCancellationRequested();
            if (!_canInstall()) throw new InvalidOperationException(UiText.Get("Diktat oder Einstellungen sind aktiv. Bitte anschließend erneut versuchen."));
            string helper = Path.Combine(folder, "Inlaut.UpdateHost.exe");
            File.Copy(Path.Combine(AppContext.BaseDirectory, "Inlaut.UpdateHost.exe"), helper);
            if (await Task.Run(() => UpdateSecurity.TrustedCertificate(helper), _cancel.Token) != await Task.Run(() => UpdateSecurity.TrustedCertificate(Application.ExecutablePath), _cancel.Token)) throw new InvalidOperationException(UiText.Get("Update-Helfer ist nicht vertrauenswürdig signiert."));
            string request = Path.Combine(folder, "request.json");
            File.WriteAllText(request, JsonSerializer.Serialize(new UpdateRequest(Environment.ProcessId, Process.GetCurrentProcess().StartTime.ToUniversalTime().Ticks, Application.ExecutablePath, LocalDiagnostics.Version.Split('+')[0], _manifest, UiText.Language)));
            // Final UI-thread gate: no dictation can begin between this check and Exit.
            _cancel.Token.ThrowIfCancellationRequested();
            if (!_canInstall()) throw new InvalidOperationException(UiText.Get("inlaut ist gerade beschäftigt."));
            var start = new ProcessStartInfo(helper) { UseShellExecute = false, CreateNoWindow = true }; start.ArgumentList.Add(request);
            using var child = Process.Start(start) ?? throw new IOException(UiText.Get("Update-Helfer konnte nicht gestartet werden."));
            handedOff = true; _exit(); Close();
        }
        catch (OperationCanceledException) { }
        catch (Exception ex) { if (!IsDisposed) _status.Text = UiText.Get(ex.Message); }
        finally
        {
            if (!handedOff && folder != null) { try { Directory.Delete(folder, true); } catch { } }
            _working = false; if (!IsDisposed) _install.Enabled = true;
        }
    }
}
