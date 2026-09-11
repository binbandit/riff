using System.Net;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using System.Text;

namespace Riff.Companion;

public sealed class PairingIdentity : IDisposable
{
    public const int Port = 49321;
    readonly string folder;
    public X509Certificate2 Certificate { get; }
    public string Token { get; private set; }
    public PairingIdentity(string folder)
    {
        this.folder = folder;
        var path = Path.Combine(folder, "identity.bin");
        if (File.Exists(path))
            Certificate = X509CertificateLoader.LoadPkcs12(ProtectedData.Unprotect(File.ReadAllBytes(path), null, DataProtectionScope.CurrentUser), null);
        else
        {
            using var key = RSA.Create(3072);
            var request = new CertificateRequest("CN=Riff Companion", key, HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1);
            request.CertificateExtensions.Add(new X509BasicConstraintsExtension(false, false, 0, true));
            request.CertificateExtensions.Add(new X509KeyUsageExtension(X509KeyUsageFlags.DigitalSignature, true));
            var usages = new OidCollection { new("1.3.6.1.5.5.7.3.1") };
            request.CertificateExtensions.Add(new X509EnhancedKeyUsageExtension(usages, false));
            using var certificate = request.CreateSelfSigned(DateTimeOffset.UtcNow.AddDays(-1), DateTimeOffset.UtcNow.AddYears(10));
            var pfx = certificate.Export(X509ContentType.Pfx);
            File.WriteAllBytes(path, ProtectedData.Protect(pfx, null, DataProtectionScope.CurrentUser));
            Certificate = X509CertificateLoader.LoadPkcs12(pfx, null);
        }
        var tokenPath = Path.Combine(folder, "pairing.bin");
        if (File.Exists(tokenPath)) Token = Encoding.UTF8.GetString(ProtectedData.Unprotect(File.ReadAllBytes(tokenPath), null, DataProtectionScope.CurrentUser));
        else { Token = ""; RotateToken(); }
    }
    public void RotateToken()
    {
        var token = Convert.ToHexString(RandomNumberGenerator.GetBytes(32)).ToLowerInvariant();
        File.WriteAllBytes(Path.Combine(folder, "pairing.bin"), ProtectedData.Protect(Encoding.UTF8.GetBytes(token), null, DataProtectionScope.CurrentUser));
        Token = token;
    }
    public bool Authorize(string header)
    {
        var expected = Encoding.UTF8.GetBytes("Bearer " + Token);
        var supplied = Encoding.UTF8.GetBytes(header);
        return CryptographicOperations.FixedTimeEquals(expected, supplied);
    }
    public string Link(string address) => $"riff://connect?host={Uri.EscapeDataString(address)}&port={Port}&token={Token}&fp={Convert.ToHexString(SHA256.HashData(Certificate.RawData)).ToLowerInvariant()}";
    public static List<string> Addresses() => NetworkInterface.GetAllNetworkInterfaces()
        .Where(n => n.OperationalStatus == OperationalStatus.Up && n.NetworkInterfaceType != NetworkInterfaceType.Loopback)
        .SelectMany(n => n.GetIPProperties().UnicastAddresses)
        .Where(a => a.Address.AddressFamily == AddressFamily.InterNetwork && !IPAddress.IsLoopback(a.Address))
        .Select(a => a.Address.ToString()).Distinct().ToList();
    public void Dispose() => Certificate.Dispose();
}
