// Moniteur de ressources (fenêtre façon Gestionnaire des tâches) : relevé natif appelé toutes les secondes pendant que la
// fenêtre est affichée. Syntaxe C# 5 (compilateur du .NET Framework).
//   ProcMon.Sample : processus (Process.GetProcesses : un seul instantané du noyau pour la mémoire), par processus avec
//     l'accès limité (lisible aussi pour la plupart des processus protégés) : temps processeur (GetProcessTimes), E/S
//     (GetProcessIoCounters, octets lus + écrits), chemin (QueryFullProcessImageName) et description du fichier (cache).
//     Processeur % = écart de temps depuis le relevé précédent / (durée x processeurs logiques).
//     Classement : Windows (processus système, services de %windir% en session 0), Applications (fenêtre visible de
//     premier niveau, non masquée par DWM), Arrière-plan (le reste).
//   NetMon : débit TCP par processus (statistiques étendues des connexions TCP IPv4 / IPv6, GetPerTcpConnectionEStats,
//     collecte activée sur chaque connexion établie) ; UDP non mesuré (pas de statistiques par connexion dans Windows).
//   DiskMon : activité du disque (compteur « % Idle Time » de PhysicalDisk(_Total), nom anglais : indépendant de la langue).
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
namespace _OlivM {
public class ProcRow {
    public int Pid; public string Name; public string Desc; public string Path; public double Cpu; public long WorkingSet;
    public long Private; public double Disk; public double Net; public int Session; public long Created; public int Kind;
}
public static class ProcMon {
    [DllImport("kernel32.dll")] static extern IntPtr OpenProcess(int access, bool inherit, int pid);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
    [DllImport("kernel32.dll")] static extern bool GetProcessTimes(IntPtr h, out long created, out long exited, out long kernel, out long user);
    [DllImport("kernel32.dll")] static extern bool GetProcessIoCounters(IntPtr h, out IoCounters io);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] static extern bool QueryFullProcessImageName(IntPtr h, int flags, StringBuilder name, ref int size);
    [DllImport("kernel32.dll")] static extern bool GetSystemTimes(out long idle, out long kernel, out long user);
    [StructLayout(LayoutKind.Sequential)] struct IoCounters { public ulong ReadOps, WriteOps, OtherOps, ReadBytes, WriteBytes, OtherBytes; }
    delegate bool EnumProc(IntPtr h, IntPtr p);
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc cb, IntPtr p);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] static extern IntPtr GetWindow(IntPtr h, int cmd);
    [DllImport("user32.dll")] static extern int GetWindowTextLength(IntPtr h);
    [DllImport("user32.dll")] static extern int GetWindowThreadProcessId(IntPtr h, out int pid);
    [DllImport("dwmapi.dll")] static extern int DwmGetWindowAttribute(IntPtr h, int attr, out int value, int size);
    const int QUERY_LIMITED = 0x1000;
    static readonly HashSet<string> SysNames = new HashSet<string>(StringComparer.OrdinalIgnoreCase) {
        "System", "Idle", "Registry", "Secure System", "Memory Compression", "smss", "csrss", "wininit", "winlogon", "services",
        "lsass", "LsaIso", "svchost", "fontdrvhost", "dwm", "spoolsv", "WUDFHost", "dasHost", "conhost", "sihost", "ctfmon",
        "RuntimeBroker", "dllhost", "taskhostw", "WmiPrvSE", "SearchIndexer", "MsMpEng", "NisSrv", "SecurityHealthService", "audiodg" };
    static Dictionary<string, long[]> prev = new Dictionary<string, long[]>();
    static Dictionary<string, string> paths = new Dictionary<string, string>();
    static Dictionary<string, string> descs = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
    static long prevStamp; static long[] prevSys;
    public static double SystemCpu;
    static string windir = Environment.GetFolderPath(Environment.SpecialFolder.Windows);
    static HashSet<int> WindowPids() {
        HashSet<int> set = new HashSet<int>();
        EnumWindows(delegate(IntPtr h, IntPtr p) {
            if (!IsWindowVisible(h) || GetWindow(h, 4) != IntPtr.Zero || GetWindowTextLength(h) == 0) return true;
            int cloaked; if (DwmGetWindowAttribute(h, 14, out cloaked, 4) == 0 && cloaked != 0) return true;
            int pid; GetWindowThreadProcessId(h, out pid); set.Add(pid); return true;
        }, IntPtr.Zero);
        return set;
    }
    public static string Describe(string path) {
        if (string.IsNullOrEmpty(path)) return "";
        string d;
        if (descs.TryGetValue(path, out d)) return d;
        try { d = (FileVersionInfo.GetVersionInfo(path).FileDescription ?? "").Trim(); } catch { d = ""; }
        descs[path] = d; return d;
    }
    public static ProcRow[] Sample() {
        long now = DateTime.UtcNow.Ticks;
        double secs = prevStamp > 0 ? (now - prevStamp) / 1e7 : 0;
        double span = secs * 1e7 * Environment.ProcessorCount;
        long si, sk, su;
        if (GetSystemTimes(out si, out sk, out su)) {
            if (prevSys != null) { long di = si - prevSys[0], dt = (sk - prevSys[1]) + (su - prevSys[2]); SystemCpu = dt > 0 ? Math.Max(0, Math.Min(100, 100.0 * (dt - di) / dt)) : 0; }
            prevSys = new long[] { si, sk, su };
        }
        HashSet<int> win = WindowPids();
        Dictionary<string, long[]> cur = new Dictionary<string, long[]>();
        List<ProcRow> rows = new List<ProcRow>();
        foreach (Process p in Process.GetProcesses()) {
            try {
                ProcRow r = new ProcRow();
                r.Pid = p.Id; r.Name = p.ProcessName;
                try { r.WorkingSet = p.WorkingSet64; r.Private = p.PrivateMemorySize64; r.Session = p.SessionId; } catch { }
                long created = 0, ticks = -1, io = -1;
                IntPtr h = r.Pid > 4 ? OpenProcess(QUERY_LIMITED, false, r.Pid) : IntPtr.Zero;
                if (h != IntPtr.Zero) {
                    try {
                        long ex, k, u;
                        if (GetProcessTimes(h, out created, out ex, out k, out u)) ticks = k + u;
                        IoCounters c; if (GetProcessIoCounters(h, out c)) io = (long)(c.ReadBytes + c.WriteBytes);
                        string key0 = r.Pid + "|" + created, path;
                        if (!paths.TryGetValue(key0, out path)) {
                            StringBuilder sb = new StringBuilder(1024); int size = sb.Capacity;
                            path = QueryFullProcessImageName(h, 0, sb, ref size) ? sb.ToString() : "";
                            paths[key0] = path;
                        }
                        r.Path = path;
                    } finally { CloseHandle(h); }
                }
                r.Created = created;
                r.Desc = Describe(r.Path);
                string key = r.Pid + "|" + created;
                cur[key] = new long[] { ticks, io };
                long[] b;
                if (secs > 0 && prev.TryGetValue(key, out b)) {
                    if (ticks >= 0 && b[0] >= 0) r.Cpu = Math.Max(0, Math.Min(100, 100.0 * (ticks - b[0]) / span));
                    if (io >= 0 && b[1] >= 0) r.Disk = Math.Max(0, (io - b[1]) / secs);
                }
                bool sysPath = !string.IsNullOrEmpty(r.Path) && r.Path.StartsWith(windir, StringComparison.OrdinalIgnoreCase);
                if (r.Pid <= 4 || SysNames.Contains(r.Name) || (r.Session == 0 && (sysPath || string.IsNullOrEmpty(r.Path)))) r.Kind = 2;
                else if (win.Contains(r.Pid)) r.Kind = 0;
                else r.Kind = 1;
                rows.Add(r);
            } finally { p.Dispose(); }
        }
        prev = cur; prevStamp = now;
        if (paths.Count > 2 * rows.Count + 64) {
            List<string> dead = new List<string>();
            foreach (string k in paths.Keys) if (!cur.ContainsKey(k)) dead.Add(k);
            foreach (string k in dead) paths.Remove(k);
        }
        // débit réseau par processus
        Dictionary<int, double> net = NetMon.RateByPid();
        foreach (ProcRow r in rows) { double v; if (net.TryGetValue(r.Pid, out v)) r.Net = v; }
        return rows.ToArray();
    }
    public static void Reset() { prev.Clear(); prevStamp = 0; prevSys = null; paths.Clear(); NetMon.Reset(); }
}
public static class NetMon {
    [DllImport("iphlpapi.dll")] static extern int GetExtendedTcpTable(IntPtr table, ref int size, bool sort, int af, int tableClass, int reserved);
    [DllImport("iphlpapi.dll")] static extern int SetPerTcpConnectionEStats(byte[] row, int type, byte[] rw, int rwVer, int rwSize, int offset);
    [DllImport("iphlpapi.dll")] static extern int GetPerTcpConnectionEStats(byte[] row, int type, IntPtr rw, int rwVer, int rwSize, IntPtr ros, int rosVer, int rosSize, byte[] rod, int rodVer, int rodSize);
    [DllImport("iphlpapi.dll")] static extern int SetPerTcp6ConnectionEStats(byte[] row, int type, byte[] rw, int rwVer, int rwSize, int offset);
    [DllImport("iphlpapi.dll")] static extern int GetPerTcp6ConnectionEStats(byte[] row, int type, IntPtr rw, int rwVer, int rwSize, IntPtr ros, int rosVer, int rosSize, byte[] rod, int rodVer, int rodSize);
    const int OWNER_PID_ALL = 5, ESTATS_DATA = 1, ESTABLISHED = 5, ROD_SIZE = 96;   // sizeof(TCP_ESTATS_DATA_ROD_v0)
    // connexion -> octets cumulés (entrants + sortants) au relevé précédent
    static Dictionary<string, ulong> prev = new Dictionary<string, ulong>();
    static long prevStamp;
    public static void Reset() { prev.Clear(); prevStamp = 0; }
    public static Dictionary<int, double> RateByPid() {
        Dictionary<int, double> res = new Dictionary<int, double>();
        long now = DateTime.UtcNow.Ticks; double secs = prevStamp > 0 ? (now - prevStamp) / 1e7 : 0; prevStamp = now;
        Dictionary<string, ulong> cur = new Dictionary<string, ulong>();
        try { Read(2, cur, res, secs); Read(23, cur, res, secs); } catch { }
        prev = cur;
        return res;
    }
    static void Read(int af, Dictionary<string, ulong> cur, Dictionary<int, double> res, double secs) {
        int size = 0;
        GetExtendedTcpTable(IntPtr.Zero, ref size, false, af, OWNER_PID_ALL, 0);
        if (size <= 0) return;
        IntPtr buf = Marshal.AllocHGlobal(size);
        try {
            if (GetExtendedTcpTable(buf, ref size, false, af, OWNER_PID_ALL, 0) != 0) return;
            int n = Marshal.ReadInt32(buf);
            byte[] rod = new byte[ROD_SIZE];
            for (int i = 0; i < n; i++) {
                byte[] row; int pid; string key;
                if (af == 2) {
                    // MIB_TCPROW_OWNER_PID (24 octets) : les 20 premiers forment le MIB_TCPROW attendu par les statistiques
                    IntPtr p = IntPtr.Add(buf, 4 + i * 24);
                    if (Marshal.ReadInt32(p) != ESTABLISHED) continue;
                    row = new byte[20]; Marshal.Copy(p, row, 0, 20); pid = Marshal.ReadInt32(p, 20);
                } else {
                    // MIB_TCP6ROW_OWNER_PID (56 octets) réordonné en MIB_TCP6ROW (état, adresse locale, portée, port,
                    // adresse distante, portée, port : 52 octets)
                    IntPtr p = IntPtr.Add(buf, 4 + i * 56);
                    if (Marshal.ReadInt32(p, 48) != ESTABLISHED) continue;
                    byte[] src = new byte[56]; Marshal.Copy(p, src, 0, 56);
                    row = new byte[52];
                    Buffer.BlockCopy(src, 48, row, 0, 4); Buffer.BlockCopy(src, 0, row, 4, 24); Buffer.BlockCopy(src, 24, row, 28, 24);
                    pid = BitConverter.ToInt32(src, 52);
                }
                key = af + ":" + Convert.ToBase64String(row);
                Array.Clear(rod, 0, ROD_SIZE);
                int rc = af == 2 ? GetPerTcpConnectionEStats(row, ESTATS_DATA, IntPtr.Zero, 0, 0, IntPtr.Zero, 0, 0, rod, 0, ROD_SIZE)
                                 : GetPerTcp6ConnectionEStats(row, ESTATS_DATA, IntPtr.Zero, 0, 0, IntPtr.Zero, 0, 0, rod, 0, ROD_SIZE);
                if (rc != 0 || !prev.ContainsKey(key)) {
                    // collecte activée à la première rencontre de la connexion (TCP_ESTATS_DATA_RW_v0.EnableCollection)
                    byte[] rw = new byte[] { 1 };
                    if (af == 2) SetPerTcpConnectionEStats(row, ESTATS_DATA, rw, 0, 1, 0); else SetPerTcp6ConnectionEStats(row, ESTATS_DATA, rw, 0, 1, 0);
                    if (rc != 0) { cur[key] = ulong.MaxValue; continue; }
                }
                // TCP_ESTATS_DATA_ROD_v0 : DataBytesOut (0), DataSegsOut (8), DataBytesIn (16)
                ulong total = BitConverter.ToUInt64(rod, 0) + BitConverter.ToUInt64(rod, 16);
                ulong before;
                if (secs > 0 && prev.TryGetValue(key, out before) && before != ulong.MaxValue && total >= before) {
                    double v; res.TryGetValue(pid, out v); res[pid] = v + (total - before) / secs;
                }
                cur[key] = total;
            }
        } finally { Marshal.FreeHGlobal(buf); }
    }
}
public static class DiskMon {
    [DllImport("pdh.dll", CharSet = CharSet.Unicode)] static extern int PdhOpenQuery(string src, IntPtr user, out IntPtr query);
    [DllImport("pdh.dll", CharSet = CharSet.Unicode)] static extern int PdhAddEnglishCounter(IntPtr query, string path, IntPtr user, out IntPtr counter);
    [DllImport("pdh.dll")] static extern int PdhCollectQueryData(IntPtr query);
    [DllImport("pdh.dll")] static extern int PdhCloseQuery(IntPtr query);
    [StructLayout(LayoutKind.Sequential)] struct FmtValue { public int Status; public int Pad; public double Value; }
    [DllImport("pdh.dll")] static extern int PdhGetFormattedCounterValue(IntPtr counter, int format, IntPtr type, out FmtValue value);
    static IntPtr q, c;
    // activité des disques en % (100 - % d'inactivité), -1 tant que deux relevés n'ont pas été faits
    public static double Busy() {
        try {
            if (q == IntPtr.Zero) {
                if (PdhOpenQuery(null, IntPtr.Zero, out q) != 0) { q = IntPtr.Zero; return -1; }
                if (PdhAddEnglishCounter(q, "\\PhysicalDisk(_Total)\\% Idle Time", IntPtr.Zero, out c) != 0) { Close(); return -1; }
                PdhCollectQueryData(q); return -1;
            }
            if (PdhCollectQueryData(q) != 0) return -1;
            FmtValue v;
            if (PdhGetFormattedCounterValue(c, 0x00000200 | 0x00008000, IntPtr.Zero, out v) != 0) return -1;
            return Math.Max(0, Math.Min(100, 100 - v.Value));
        } catch { return -1; }
    }
    public static void Close() { if (q != IntPtr.Zero) { PdhCloseQuery(q); q = IntPtr.Zero; c = IntPtr.Zero; } }
}
// Gestionnaire de redémarrage de Windows (Restart Manager, celui des installeurs) : processus qui ont un fichier ouvert
// parmi ceux donnés (fichier ouvert, DLL chargée), quel que soit leur nom.
public static class FileLock {
    [StructLayout(LayoutKind.Sequential)] struct RmUniqueProcess { public int Pid; public System.Runtime.InteropServices.ComTypes.FILETIME Start; }
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)] struct RmProcessInfo {
        public RmUniqueProcess Process;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 256)] public string AppName;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 64)] public string ServiceName;
        public int AppType; public uint AppStatus; public uint Session; [MarshalAs(UnmanagedType.Bool)] public bool Restartable;
    }
    [DllImport("rstrtmgr.dll", CharSet = CharSet.Unicode)] static extern int RmStartSession(out uint h, int flags, StringBuilder key);
    [DllImport("rstrtmgr.dll", CharSet = CharSet.Unicode)] static extern int RmRegisterResources(uint h, uint nFiles, string[] files, uint nApps, IntPtr apps, uint nSvc, string[] svc);
    [DllImport("rstrtmgr.dll")] static extern int RmGetList(uint h, out uint needed, ref uint count, [In, Out] RmProcessInfo[] info, ref uint reasons);
    [DllImport("rstrtmgr.dll")] static extern int RmEndSession(uint h);
    public static int[] Lockers(string[] files) {
        List<int> res = new List<int>();
        if (files == null || files.Length == 0) return res.ToArray();
        uint h; StringBuilder key = new StringBuilder(64);
        if (RmStartSession(out h, 0, key) != 0) return res.ToArray();
        try {
            if (RmRegisterResources(h, (uint)files.Length, files, 0, IntPtr.Zero, 0, null) != 0) return res.ToArray();
            uint needed, count = 0, reasons = 0;
            int rc = RmGetList(h, out needed, ref count, null, ref reasons);
            if (rc == 234 && needed > 0) {
                RmProcessInfo[] info = new RmProcessInfo[needed]; count = needed;
                if (RmGetList(h, out needed, ref count, info, ref reasons) == 0) for (int i = 0; i < count; i++) res.Add(info[i].Process.Pid);
            }
        } finally { RmEndSession(h); }
        return res.ToArray();
    }
}
}
