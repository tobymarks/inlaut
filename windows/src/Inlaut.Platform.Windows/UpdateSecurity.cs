using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using Inlaut.Core;

namespace Inlaut.Platform.Windows;

public static class UpdateSecurity
{
    // Trust the signed installed application, never a publisher supplied by the feed.
    // Exact certificate pinning also avoids trusting another project sharing a CA.
    public static string TrustedCertificate(string path)
    {
        var file = new TrustFile { Size = (uint)Marshal.SizeOf<TrustFile>(), Path = path };
        IntPtr pointer = Marshal.AllocHGlobal(Marshal.SizeOf<TrustFile>());
        Marshal.StructureToPtr(file, pointer, false);
        var data = new TrustData { Size = (uint)Marshal.SizeOf<TrustData>(), UiChoice = 2, RevocationChecks = 1, UnionChoice = 1, File = pointer, StateAction = 1, ProviderFlags = 0x80 };
        var action = new Guid("00AAC56B-CD44-11d0-8CC2-00C04FC295EE");
        try
        {
            int result = WinVerifyTrust(new IntPtr(-1), ref action, ref data);
            if (result != 0) throw new InvalidOperationException("Die Windows-Signatur konnte nicht bestätigt werden. Installation abgebrochen.");
            using var certificate = new X509Certificate2(X509Certificate.CreateFromSignedFile(path));
            return certificate.GetCertHashString(HashAlgorithmName.SHA256);
        }
        finally
        {
            data.StateAction = 2; WinVerifyTrust(new IntPtr(-1), ref action, ref data);
            Marshal.DestroyStructure<TrustFile>(pointer); Marshal.FreeHGlobal(pointer);
        }
    }
    public static void VerifyPackage(string path, UpdateManifest manifest, string trustedApplication)
    {
        manifest.Validate();
        using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read);
        if (stream.Length != manifest.Size || !Convert.ToHexString(SHA256.HashData(stream)).Equals(manifest.Sha256, StringComparison.OrdinalIgnoreCase)) throw new InvalidOperationException("Die Update-Prüfsumme stimmt nicht. Bitte erneut laden.");
        if (TrustedCertificate(path) != TrustedCertificate(trustedApplication)) throw new InvalidOperationException("Das Update wurde nicht mit dem vertrauten inlaut-Zertifikat signiert.");
        var version = System.Diagnostics.FileVersionInfo.GetVersionInfo(path);
        if (version.ProductName is not ("inlaut" or "inlaut Beta") || version.ProductVersion != manifest.Version) throw new InvalidOperationException("Das signierte Paket passt nicht zur angebotenen Version.");
    }
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct TrustFile { public uint Size; [MarshalAs(UnmanagedType.LPWStr)] public string Path; public IntPtr Handle, Subject; }
    [StructLayout(LayoutKind.Sequential)]
    private struct TrustData
    {
        public uint Size; public IntPtr Policy, Sip; public uint UiChoice, RevocationChecks, UnionChoice;
        public IntPtr File; public uint StateAction; public IntPtr State, Url; public uint ProviderFlags, UiContext; public IntPtr SignatureSettings;
    }
    [DllImport("wintrust.dll", ExactSpelling = true, PreserveSig = true)]
    private static extern int WinVerifyTrust(IntPtr hwnd, ref Guid action, ref TrustData data);
}
