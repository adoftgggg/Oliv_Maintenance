// Code natif de Oliv_Maintenance : compilé par build.ps1 dans une seule DLL embarquée dans le script (chargée en mémoire
// au démarrage, aucune compilation sur le poste, aucun fichier DLL écrit). Syntaxe C# 5 (compilateur du .NET Framework).
// Tâches longues (runspace worker) : lecture de la console des outils (SFC, DISM), santé NVMe, bit dirty du volume ;
// vérification d'un compte administrateur (élévation)
using System;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
namespace _OlivM {
public static class Con2 {
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern IntPtr CreateFileW(string lpFileName, uint dwDesiredAccess, uint dwShareMode, IntPtr lpSecurityAttributes, uint dwCreationDisposition, uint dwFlagsAndAttributes, IntPtr hTemplateFile);
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern bool ReadConsoleOutputCharacterW(IntPtr hConsoleOutput, [Out] char[] lpCharacter, uint nLength, uint dwReadCoord, out uint lpNumberOfCharsRead);
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool CloseHandle(IntPtr hObject);
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool GetConsoleScreenBufferInfo(IntPtr hConsoleOutput, [Out] byte[] lpConsoleScreenBufferInfo);
}
public static class Nvme {
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern SafeFileHandle CreateFileW(string n, uint a, uint s, IntPtr sa, uint c, uint f, IntPtr t);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool DeviceIoControl(SafeFileHandle h, uint code, byte[] inBuf, int inLen, byte[] outBuf, int outLen, out int ret, IntPtr ov);
    public static byte[] HealthLog(int disk) {
        using (SafeFileHandle h = CreateFileW(@"\\.\PhysicalDrive" + disk, 0xC0000000, 3, IntPtr.Zero, 3, 0, IntPtr.Zero)) {
            if (h.IsInvalid) return null;
            byte[] b = new byte[8 + 40 + 512];
            BitConverter.GetBytes(50).CopyTo(b, 0);   // StorageDeviceProtocolSpecificProperty ; QueryType 0 = PropertyStandardQuery
            BitConverter.GetBytes(3).CopyTo(b, 8);    // ProtocolTypeNvme
            BitConverter.GetBytes(2).CopyTo(b, 12);   // NVMeDataTypeLogPage
            BitConverter.GetBytes(2).CopyTo(b, 16);   // NVME_LOG_PAGE_HEALTH_INFO
            BitConverter.GetBytes(40).CopyTo(b, 24);  // ProtocolDataOffset = sizeof(STORAGE_PROTOCOL_SPECIFIC_DATA)
            BitConverter.GetBytes(512).CopyTo(b, 28); // ProtocolDataLength
            int ret;
            if (!DeviceIoControl(h, 0x002D1400, b, b.Length, b, b.Length, out ret, IntPtr.Zero) || ret < 48) return null;
            int off = BitConverter.ToInt32(b, 24), len = BitConverter.ToInt32(b, 28);
            if (off < 40 || len < 512 || 8 + off + 512 > b.Length) return null;
            byte[] r = new byte[512];
            Array.Copy(b, 8 + off, r, 0, 512);
            return r;
        }
    }
}
public static class VolDirty {
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern SafeFileHandle CreateFile(string n, uint a, uint s, IntPtr sa, uint c, uint f, IntPtr t);
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool DeviceIoControl(SafeFileHandle h, uint code, IntPtr i, uint il, out uint o, uint ol, out uint r, IntPtr ov);
}
public static class Auth {
    [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern bool LogonUserW(string user, string domain, string pass, int type, int provider, out IntPtr token);
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool CloseHandle(IntPtr h);
}
}
