using System.Reflection;
using System.Runtime.InteropServices;
using Inlaut.App;
using Inlaut.Platform.Windows;

namespace Inlaut.UiSmoke;

internal static class HotkeyCancellationChecks
{
    private const BindingFlags PrivateInstance = BindingFlags.Instance | BindingFlags.NonPublic;
    private static readonly MethodInfo Hook = typeof(KeyTrigger).GetMethod("HookCallback", PrivateInstance)!;
    private static readonly MethodInfo Hold = typeof(KeyTrigger).GetMethod("OnHoldTimerFired", PrivateInstance)!;

    // These events enter the real hook callback but are NOT injected into Windows.
    // Start/stop/cancel use the real dispatcher; audio and text are simulated here.
    public static async Task Run(Form host)
    {
        using (var probe = new Probe(host, "hold"))
        {
            Key(probe.Trigger, 0x11, down: true);
            Hold.Invoke(probe.Trigger, null);
            await Drain();
            Require(probe.Starts == 1 && probe.Recording, "Hold did not start recording.");
            Key(probe.Trigger, 0x41, down: true); // Ctrl+A must continue to the target.
            probe.SelectionAll = true; // Target application's normal Ctrl+A action.
            Key(probe.Trigger, 0x11, down: false);
            await Drain();
            Require(probe.Cancels == 1 && probe.Stops == 0 && !probe.Recording && probe.BufferedSamples == 0,
                "Shortcut finalized or retained the cancelled recording.");
            Require(probe.Transcriptions == 0 && probe.Output == Probe.Original,
                "Ctrl+A cancellation overwrote the target selection.");

            // The cancelled key release must not leave the next hold stuck.
            Key(probe.Trigger, 0x11, down: true);
            Hold.Invoke(probe.Trigger, null);
            await Drain();
            Key(probe.Trigger, 0x11, down: false);
            await Drain();
            Require(probe.Starts == 2 && probe.Stops == 1 && probe.Cancels == 1 && probe.Transcriptions == 1,
                "Normal hold/release did not recover after cancellation.");
        }

        using (var probe = new Probe(host, "hold"))
        {
            Key(probe.Trigger, 0x11, down: true);
            Hold.Invoke(probe.Trigger, null); // BeginInvoke queued; no UI yield yet.
            Key(probe.Trigger, 0x41, down: true);
            probe.SelectionAll = true;
            Key(probe.Trigger, 0x11, down: false);
            await Drain();
            Require(probe.Starts == 0 && probe.Cancels == 1 && probe.Stops == 0 && !probe.Recording,
                "A cancelled queued start began recording later.");
            Require(probe.Output == Probe.Original && probe.Transcriptions == 0,
                "Queued-start cancellation inserted text.");
        }

        using (var probe = new Probe(host, "combined"))
        {
            Key(probe.Trigger, 0x11, down: true);
            Key(probe.Trigger, 0x41, down: true); // Ordinary shortcut before the hold threshold.
            Key(probe.Trigger, 0x11, down: false);
            Hold.Invoke(probe.Trigger, null);
            await Drain();
            Require(probe.Starts == 0 && probe.Stops == 0 && probe.Cancels == 0,
                "A quick Ctrl+A triggered dictation.");
        }

        foreach (string mode in new[] { "toggle", "combined" })
        {
            using var probe = new Probe(host, mode);
            if (mode == "combined")
            {
                Key(probe.Trigger, 0x11, down: true);
                Key(probe.Trigger, 0x11, down: false);
            }
            Key(probe.Trigger, 0x11, down: true);
            Key(probe.Trigger, 0x11, down: true); // Auto-repeat must not toggle again.
            Key(probe.Trigger, 0x11, down: false);
            await Drain();
            Require(probe.Starts == 1 && probe.Recording, mode + " failed to start.");
            Key(probe.Trigger, 0x11, down: true);
            Key(probe.Trigger, 0x11, down: false);
            await Drain();
            Require(probe.Stops == 1 && probe.Cancels == 0 && probe.Transcriptions == 1,
                mode + " no longer finishes normal dictation.");
        }

        using (var probe = new Probe(host, "hold"))
        {
            Key(probe.Trigger, 0x11, down: true, flags: 0x10); // LLKHF_INJECTED.
            Hold.Invoke(probe.Trigger, null);
            Key(probe.Trigger, 0x41, down: true, flags: 0x10);
            await Drain();
            Require(probe.Starts == 0 && probe.Cancels == 0, "Injected input triggered recording.");
            Key(probe.Trigger, 0x11, down: true);
            Hold.Invoke(probe.Trigger, null);
            probe.Trigger.IsSuspended = true;
            await Drain();
            Require(probe.Starts == 0, "Suspension did not invalidate a queued start.");
        }

#if WINDOWS
        await CheckApplicationDiscard(host);
#endif
        Console.WriteLine("PASS: real hook-path Ctrl+A cancellation, queued-start race, shortcut passthrough, hold recovery, toggle/double-tap and injected-input filtering");
    }

    private static Task Drain() => Task.Delay(30);
    private static void Require(bool condition, string message)
    {
        if (!condition) throw new Exception(message);
    }

    private static void Key(KeyTrigger trigger, uint code, bool down, uint flags = 0)
    {
        var data = new NativeMethods.KBDLLHOOKSTRUCT { vkCode = code, flags = flags };
        IntPtr memory = Marshal.AllocHGlobal(Marshal.SizeOf<NativeMethods.KBDLLHOOKSTRUCT>());
        try
        {
            Marshal.StructureToPtr(data, memory, false);
            var message = new IntPtr(down ? NativeMethods.WM_KEYDOWN : NativeMethods.WM_KEYUP);
            // No hook was installed. Compare with the native next-hook result to
            // prove normal shortcut keys are forwarded instead of consumed (1).
            IntPtr forwarded = NativeMethods.CallNextHookEx(IntPtr.Zero, 0, message, memory);
            IntPtr actual = (IntPtr)Hook.Invoke(trigger, [0, message, memory])!;
            Require(actual == forwarded, "Hook consumed a normal shortcut key.");
        }
        finally { Marshal.FreeHGlobal(memory); }
    }

    private sealed class Probe : IDisposable
    {
        public const string Original = "Existing document selected by Ctrl+A";
        public readonly KeyTrigger Trigger;
        public int Starts, Stops, Cancels, Transcriptions, BufferedSamples;
        public bool Recording, SelectionAll;
        public string Output = Original;

        public Probe(Form host, string mode)
        {
            Trigger = new KeyTrigger(host) { Mode = mode };
            Trigger.OnStart = () => { Starts++; Recording = true; BufferedSamples = 16000; };
            Trigger.OnStop = () =>
            {
                Stops++;
                if (!Recording) return;
                Transcriptions++;
                Output = (SelectionAll ? "" : Output) + "recognised speech";
                Recording = false;
                BufferedSamples = 0;
            };
            Trigger.OnCancel = () => { Cancels++; Recording = false; BufferedSamples = 0; };
        }

        public void Dispose() => Trigger.Dispose();
    }

#if WINDOWS
    private static async Task CheckApplicationDiscard(Form host)
    {
        // Exercise the real application cancellation without opening a microphone,
        // model, system hook or visible tray icon. Constructor startup is bypassed.
        using var trigger = new KeyTrigger(host) { Mode = "hold" };
        using var recorder = new AudioRecorder();
        using var indicator = new RecordingIndicatorForm();
        using var icon = new NotifyIcon();
        var app = (InlautTrayApplicationContext)System.Runtime.CompilerServices.RuntimeHelpers.GetUninitializedObject(typeof(InlautTrayApplicationContext));
        void Set(string name, object? value) => typeof(InlautTrayApplicationContext).GetField(name, PrivateInstance)!.SetValue(app, value);
        object? Get(string name) => typeof(InlautTrayApplicationContext).GetField(name, PrivateInstance)!.GetValue(app);
        Set("_recorder", recorder); Set("_indicator", indicator); Set("_notifyIcon", icon);
        Set("_keyTrigger", trigger); Set("_defaultIcon", System.Drawing.SystemIcons.Application);
        Set("_settings", new AppSettings()); Set("_pipeline", new Inlaut.Core.TextPipeline());
        Set("_activeSpeechLanguage", "de"); Set("_isModelReady", true);
        Set("_captureRemaining", 3); Set("_lastDictation", "previous completed dictation");
        Set("_dictationTarget", new DirectTextInserter.InputTarget(new IntPtr(1), new IntPtr(2)));
        using var audio = new MemoryStream(new byte[32000]);
        trigger.OnStart = () =>
        {
            typeof(AudioRecorder).GetField("_buffer", PrivateInstance)!.SetValue(recorder, audio);
            typeof(AudioRecorder).GetProperty(nameof(AudioRecorder.IsRecording))!.SetValue(recorder, true);
        };
        int normalStops = 0;
        trigger.OnStop = () => normalStops++;
        trigger.OnCancel = () => typeof(InlautTrayApplicationContext).GetMethod("CancelDictation", PrivateInstance)!.Invoke(app, null);
        Key(trigger, 0x11, down: true);
        Hold.Invoke(trigger, null);
        await Drain();
        Require(recorder.IsRecording, "Application discard fixture did not record.");
        Key(trigger, 0x41, down: true);
        Key(trigger, 0x11, down: false);
        await Drain();
        Require(normalStops == 0 && !recorder.IsRecording && !audio.CanRead && Get("_dictationTarget") == null,
            "Application cancellation did not dispose audio and clear its target.");
        Require((int)Get("_captureRemaining")! == 3 && (string)Get("_lastDictation")! == "previous completed dictation" && !(bool)Get("_isTranscribing")!,
            "Application cancellation entered transcription or changed saved dictation state.");
        Console.WriteLine("PASS: application cancellation discards the real recorder buffer without decoding, capture saving or insertion");
    }
#endif
}
