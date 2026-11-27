// Code natif de Oliv_Maintenance : compilé par build.ps1 dans une seule DLL embarquée dans le script (chargée en mémoire
// au démarrage, aucune compilation sur le poste, aucun fichier DLL écrit). Syntaxe C# 5 (compilateur du .NET Framework).
// Shell : AppUserModelID ; Perf : processeur et mémoire (moniteur d'activité) ; Pwr : capacités d'alimentation ; WinPlace : position des fenêtres
using System;
using System.Runtime.InteropServices;
using System.Text;
namespace _OlivM {
public static class Shell {
    [DllImport("shell32.dll", CharSet = CharSet.Unicode)] public static extern int SetCurrentProcessExplicitAppUserModelID(string AppID);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern IntPtr SendMessageTimeout(IntPtr h, int msg, IntPtr wp, string lp, int flags, int timeout, out IntPtr result);
    // WM_SETTINGCHANGE diffusé à toutes les fenêtres (section de win.ini modifiée, ex. « windows » pour l'imprimante par
    // défaut) ; SMTO_ABORTIFHUNG, 1 s au plus par fenêtre
    public static bool NotifySettingChange(string section) { IntPtr r; return SendMessageTimeout(new IntPtr(0xFFFF), 0x001A, IntPtr.Zero, section, 2, 1000, out r) != IntPtr.Zero; }
    // chaîne indirecte « @%SystemRoot%\system32\input.dll,-5000 » (noms traduits des claviers) ; null si introuvable
    [DllImport("shlwapi.dll", CharSet = CharSet.Unicode)] static extern int SHLoadIndirectString(string src, StringBuilder buf, int cch, IntPtr res);
    public static string Indirect(string s) { StringBuilder b = new StringBuilder(512); return SHLoadIndirectString(s, b, 512, IntPtr.Zero) == 0 ? b.ToString() : null; }
    // Propriétés de relance de la fenêtre (épinglage à la barre des tâches) : sans elles, Windows épingle l'exe lancé
    // (copie du dossier Téléchargements, renommée ou supprimée à la mise à jour : épingle périmée). Avec elles, l'épingle
    // ouvre la copie fixe de ProgramData, tenue à jour à chaque lancement. PKEY_AppUserModel_* {9F4C2855-...} : 5 ID,
    // 2 RelaunchCommand, 3 RelaunchIconResource, 4 RelaunchDisplayNameResource (chaînes VT_LPWSTR).
    [StructLayout(LayoutKind.Sequential, Pack = 4)] struct PKey { public Guid F; public uint P; public PKey(uint p) { F = new Guid("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3"); P = p; } }
    [StructLayout(LayoutKind.Sequential)] struct PVar { public ushort Vt; public ushort R1, R2, R3; public IntPtr P; public IntPtr P2; }
    [ComImport, Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IPropStore { int GetCount(out uint c); int GetAt(uint i, out PKey k); int GetValue(ref PKey k, out PVar v); int SetValue(ref PKey k, ref PVar v); int Commit(); }
    [DllImport("shell32.dll")] static extern int SHGetPropertyStoreForWindow(IntPtr hwnd, ref Guid riid, out IPropStore store);
    [DllImport("ole32.dll")] static extern int PropVariantClear(ref PVar v);
    static void SetStr(IPropStore s, uint pid, string val) {
        PKey k = new PKey(pid); PVar v = new PVar(); v.Vt = 31; v.P = Marshal.StringToCoTaskMemUni(val);
        try { s.SetValue(ref k, ref v); } finally { PropVariantClear(ref v); }
    }
    public static bool SetRelaunch(IntPtr hwnd, string appId, string command, string name, string icon) {
        Guid g = typeof(IPropStore).GUID; IPropStore s;
        if (SHGetPropertyStoreForWindow(hwnd, ref g, out s) != 0 || s == null) return false;
        try { SetStr(s, 5, appId); SetStr(s, 2, command); SetStr(s, 4, name); SetStr(s, 3, icon); s.Commit(); return true; }
        finally { Marshal.ReleaseComObject(s); }
    }
}
public static class Perf {
    [DllImport("kernel32.dll")] static extern bool GetSystemTimes(out long idle, out long kernel, out long user);
    [StructLayout(LayoutKind.Sequential)] class MS { public uint Len; public uint Load; public ulong TotalPhys, AvailPhys, TotalPage, AvailPage, TotalVirt, AvailVirt, AvailExt; public MS() { Len = (uint)Marshal.SizeOf(typeof(MS)); } }
    [DllImport("kernel32.dll")] static extern bool GlobalMemoryStatusEx([In, Out] MS m);
    public static long[] Times() { long i, k, u; if (!GetSystemTimes(out i, out k, out u)) return null; return new long[] { i, k, u }; }
    public static ulong[] Mem() { MS m = new MS(); if (!GlobalMemoryStatusEx(m)) return null; return new ulong[] { m.TotalPhys, m.AvailPhys, m.TotalPage, m.AvailPage }; }
}
public static class Pwr {
    [DllImport("powrprof.dll")] public static extern byte GetPwrCapabilities(IntPtr caps);
}
// Planification GPU accélérée par le matériel (HAGS) : capacités WDDM 2.7 de chaque carte (D3DKMTQueryAdapterInfo,
// KMTQAITYPE_WDDM_2_7_CAPS = 70). Bits : 1 pris en charge, 2 actif, 4 actif par défaut. Cumul de toutes les cartes ;
// -1 si l'interface est absente ou en erreur.
public static class Gpu {
    [StructLayout(LayoutKind.Sequential)] struct ENUM2 { public uint Num; public IntPtr Adapters; }
    [StructLayout(LayoutKind.Sequential)] struct INFO { public uint Handle; public uint LuidLow; public int LuidHigh; public uint Sources; public int Precise; }
    [StructLayout(LayoutKind.Sequential)] struct QUERY { public uint Handle; public int Type; public IntPtr Data; public uint Size; }
    [DllImport("gdi32.dll")] static extern int D3DKMTEnumAdapters2(ref ENUM2 e);
    [DllImport("gdi32.dll")] static extern int D3DKMTQueryAdapterInfo(ref QUERY q);
    [DllImport("gdi32.dll")] static extern int D3DKMTCloseAdapter(ref uint h);
    public static int HwSch() {
        try {
            ENUM2 e = new ENUM2();
            if (D3DKMTEnumAdapters2(ref e) != 0 || e.Num == 0) return -1;
            int sz = Marshal.SizeOf(typeof(INFO));
            e.Adapters = Marshal.AllocHGlobal(sz * (int)e.Num);
            IntPtr cap = Marshal.AllocHGlobal(4);
            int res = 0;
            try {
                if (D3DKMTEnumAdapters2(ref e) != 0) return -1;
                for (int i = 0; i < e.Num; i++) {
                    INFO a = (INFO)Marshal.PtrToStructure(new IntPtr(e.Adapters.ToInt64() + i * sz), typeof(INFO));
                    Marshal.WriteInt32(cap, 0);
                    QUERY q = new QUERY(); q.Handle = a.Handle; q.Type = 70; q.Data = cap; q.Size = 4;
                    if (D3DKMTQueryAdapterInfo(ref q) == 0) res |= Marshal.ReadInt32(cap) & 7;
                    uint h = a.Handle; D3DKMTCloseAdapter(ref h);
                }
            } finally { Marshal.FreeHGlobal(e.Adapters); Marshal.FreeHGlobal(cap); }
            return res;
        } catch { return -1; }
    }
}
// Paramètres de la souris appliqués à la session sans déconnexion (SPI_SETMOUSE : seuil 1, seuil 2, accélération),
// SPIF_SENDCHANGE seul : le registre est écrit à part (compte de l'utilisateur ciblé, pas celui qui exécute l'application)
public static class Mouse {
    [DllImport("user32.dll")] static extern bool SystemParametersInfo(uint action, uint p, int[] v, uint flags);
    public static bool Apply(int t1, int t2, int speed) { return SystemParametersInfo(4, 0, new int[] { t1, t2, speed }, 2); }
}
public static class WinPlace {
    [StructLayout(LayoutKind.Sequential)] struct PT { public int X, Y; }
    [StructLayout(LayoutKind.Sequential)] struct RC { public int L, T, R, B; }
    [StructLayout(LayoutKind.Sequential)] struct WP { public int Length, Flags, ShowCmd; public PT Min, Max; public RC Normal; }
    [DllImport("user32.dll")] static extern bool GetWindowPlacement(IntPtr h, ref WP p);
    [DllImport("user32.dll")] static extern bool SetWindowPlacement(IntPtr h, ref WP p);
    public static int[] Get(IntPtr h) {
        WP p = new WP(); p.Length = Marshal.SizeOf(typeof(WP));
        if (!GetWindowPlacement(h, ref p)) return null;
        return new int[] { p.Normal.L, p.Normal.T, p.Normal.R, p.Normal.B, p.ShowCmd };
    }
    public static bool Set(IntPtr h, int l, int t, int r, int b) {
        WP p = new WP(); p.Length = Marshal.SizeOf(typeof(WP)); p.ShowCmd = 1;
        p.Normal.L = l; p.Normal.T = t; p.Normal.R = r; p.Normal.B = b;
        return SetWindowPlacement(h, ref p);
    }
    // fenêtre agrandie sans cadre Windows (WindowChrome) : débord réel de la fenêtre au-delà de la zone de travail de son
    // écran (gauche, haut, droite, bas), en pixels, lu par Win32 (même référentiel que la fenêtre : pas d'arrondi DPI)
    [StructLayout(LayoutKind.Sequential)] struct MI { public int Size; public RC Mon, Work; public int Flags; }
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h, out RC r);
    [DllImport("user32.dll")] static extern IntPtr MonitorFromWindow(IntPtr h, int f);
    [DllImport("user32.dll")] static extern bool GetMonitorInfo(IntPtr m, ref MI i);
    // WM_GETMINMAXINFO de la fenêtre principale (crochet HwndSource) : agrandie, elle occupe exactement la zone de travail
    // de son écran, sans le débord de cadre que Windows applique d'habitude (avec WindowChrome, ce débord laissait une ligne
    // de pixels de l'écran non couverte, cliquable vers la fenêtre de dessous). Ne marque pas le message comme traité :
    // WPF y ajoute ensuite les tailles minimale et maximale de la fenêtre.
    [StructLayout(LayoutKind.Sequential)] struct MMI { public PT Reserved, MaxSize, MaxPosition, MinTrack, MaxTrack; }
    [DllImport("user32.dll")] static extern bool IsZoomed(IntPtr h);
    [DllImport("user32.dll")] static extern bool PostMessage(IntPtr h, int msg, IntPtr wp, IntPtr lp);
    [DllImport("user32.dll")] static extern int SetWindowRgn(IntPtr h, IntPtr rgn, bool redraw);
    [DllImport("user32.dll")] static extern int GetWindowRgnBox(IntPtr h, out RC r);
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)] struct MIX { public int Size; public RC Mon, Work; public int Flags; [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string Device; }
    [DllImport("user32.dll", CharSet = CharSet.Unicode, EntryPoint = "GetMonitorInfoW")] static extern bool GetMonitorInfoX(IntPtr m, ref MIX i);
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)] struct DM {
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string DeviceName;
        public short SpecVersion, DriverVersion, Size, DriverExtra; public int Fields;
        public int PositionX, PositionY, Orientation, FixedOutput;
        public short Color, Duplex, YResolution, TTOption, Collate;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string FormName;
        public short LogPixels; public int BitsPerPel, PelsWidth, PelsHeight, DisplayFlags, DisplayFrequency, ICMMethod, ICMIntent, MediaType, DitherType, Reserved1, Reserved2, PanningWidth, PanningHeight;
    }
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern bool EnumDisplaySettings(string dev, int mode, ref DM dm);
    const int WM_APP_NOREGION = 0x8000 + 0x47;
    // coordonnées de l'écran converties par Windows (processus non « par écran » sur un écran à une autre échelle que celle
    // du système : largeur vue par la fenêtre différente de la largeur réelle en pixels) : la conversion arrondit, 1 pixel
    // de marge de chaque côté pour ne laisser aucune ligne de l'écran non couverte
    static int Bleed(IntPtr mon) {
        try {
            MIX i = new MIX(); i.Size = Marshal.SizeOf(typeof(MIX)); if (!GetMonitorInfoX(mon, ref i)) return 0;
            DM d = new DM(); d.Size = (short)Marshal.SizeOf(typeof(DM)); if (!EnumDisplaySettings(i.Device, -1, ref d)) return 0;
            return (d.PelsWidth != i.Mon.R - i.Mon.L || d.PelsHeight != i.Mon.B - i.Mon.T) ? 1 : 0;
        } catch { return 0; }
    }
    public static IntPtr MaxHook(IntPtr h, int msg, IntPtr wp, IntPtr lp, ref bool handled) {
        if (msg == 0x0024) {
            IntPtr mon = MonitorFromWindow(h, 2); if (mon == IntPtr.Zero) return IntPtr.Zero;
            MI i = new MI(); i.Size = Marshal.SizeOf(typeof(MI));
            if (!GetMonitorInfo(mon, ref i)) return IntPtr.Zero;
            int e = Bleed(mon);
            MMI m = (MMI)Marshal.PtrToStructure(lp, typeof(MMI));
            m.MaxPosition.X = i.Work.L - i.Mon.L - e; m.MaxPosition.Y = i.Work.T - i.Mon.T - e;
            m.MaxSize.X = i.Work.R - i.Work.L + 2 * e; m.MaxSize.Y = i.Work.B - i.Work.T + 2 * e;
            if (m.MaxTrack.X < m.MaxSize.X) m.MaxTrack.X = m.MaxSize.X;
            if (m.MaxTrack.Y < m.MaxSize.Y) m.MaxTrack.Y = m.MaxSize.Y;
            Marshal.StructureToPtr(m, lp, false);
        } else if (msg == 0x0047) {
            // WindowChrome découpe la fenêtre agrandie à la zone de travail (SetWindowRgn) à chaque déplacement ; ce découpage,
            // recalculé dans d'autres coordonnées, pouvait retirer une ligne de pixels. Fenêtre agrandie déjà calée sur la zone
            // de travail : découpage retiré, une fois le traitement de WindowChrome terminé (message posté).
            // Garde-fous contre la boucle (0.108.6 figeait l'application : SetWindowRgn renvoie lui-même WM_WINDOWPOSCHANGED,
            // qui reposait le message à l'infini) : seulement quand la taille change (SWP_NOSIZE absent, même règle que
            // WindowChrome), et retrait seulement si un découpage existe encore.
            int flags = Marshal.ReadInt32(lp, 2 * IntPtr.Size + 16);
            // Aussi sur SWP_FRAMECHANGED : WindowChrome remet son découpage quand ses réglages changent (hauteur de la barre de
            // titre modifiée par le zoom de l'interface), sans changement de taille ; la ligne de pixels revenait après un zoom.
            // fenêtre restaurée aussi : le découpage rectangulaire de WindowChrome empêchait Windows 11 d'arrondir les coins
            if ((flags & 0x0001) == 0 || (flags & 0x0020) != 0) PostMessage(h, WM_APP_NOREGION, IntPtr.Zero, IntPtr.Zero);
        } else if (msg == WM_APP_NOREGION) {
            RC g; if (GetWindowRgnBox(h, out g) > 1) SetWindowRgn(h, IntPtr.Zero, true);
            handled = true;
        }
        return IntPtr.Zero;
    }
    public static void NoRegion(IntPtr h) { RC g; if (GetWindowRgnBox(h, out g) > 1) SetWindowRgn(h, IntPtr.Zero, true); }
    // coins arrondis de Windows 11 (DWMWA_WINDOW_CORNER_PREFERENCE = 33, DWMWCP_ROUND = 2) pour les fenêtres sans cadre
    // Windows (WindowChrome) ; sans effet avant Windows 11 (attribut inconnu : code d'erreur renvoyé, ignoré)
    [DllImport("dwmapi.dll")] static extern int DwmSetWindowAttribute(IntPtr h, int attr, ref int value, int size);
    public static bool RoundCorners(IntPtr h) { int v = 2; return DwmSetWindowAttribute(h, 33, ref v, 4) == 0; }
    public static int[] Overhang(IntPtr h) {
        RC w; if (!GetWindowRect(h, out w)) return null;
        MI i = new MI(); i.Size = Marshal.SizeOf(typeof(MI));
        if (!GetMonitorInfo(MonitorFromWindow(h, 2), ref i)) return null;
        return new int[] { Math.Max(0, i.Work.L - w.L), Math.Max(0, i.Work.T - w.T), Math.Max(0, w.R - i.Work.R), Math.Max(0, w.B - i.Work.B) };
    }
}
// Volumes de l'Accueil : fil .NET en arrière-plan (priorité basse) au lieu d'un runspace PowerShell permanent.
// Lecture des lecteurs fixes et amovibles prêts toutes les IntervalMs (5 s Accueil affiché, 30 s sinon), ou tout de suite
// sur Refresh(). Résultat : Vols (instantané immuable), Sig (lettres et tailles : changement = santé des disques à relire),
// Stamp (incrémenté à chaque lecture).
public class VolInfo { public string Name, Label, Fs; public bool Rem; public double Total, Free; }
public static class VolWatch {
    static System.Threading.Thread t;
    static readonly System.Threading.AutoResetEvent wake = new System.Threading.AutoResetEvent(false);
    public static volatile int IntervalMs = 5000;
    public static volatile VolInfo[] Vols;
    public static volatile string Sig = "";
    static long stamp;
    public static long Stamp { get { return System.Threading.Interlocked.Read(ref stamp); } }
    public static void Start() {
        lock (wake) { if (t != null) return; t = new System.Threading.Thread(Loop); t.IsBackground = true; t.Priority = System.Threading.ThreadPriority.BelowNormal; t.Name = "Oliv_Maintenance volumes"; t.Start(); }
    }
    public static void Refresh() { wake.Set(); }
    static void Loop() { while (true) { try { Read(); } catch { } wake.WaitOne(IntervalMs); } }
    static void Read() {
        var l = new System.Collections.Generic.List<VolInfo>(); var sig = new System.Text.StringBuilder();
        foreach (System.IO.DriveInfo d in System.IO.DriveInfo.GetDrives()) {
            try {
                if ((d.DriveType != System.IO.DriveType.Fixed && d.DriveType != System.IO.DriveType.Removable) || !d.IsReady) continue;
                VolInfo v = new VolInfo(); v.Name = d.Name; v.Label = d.VolumeLabel; v.Fs = d.DriveFormat; v.Rem = d.DriveType == System.IO.DriveType.Removable;
                v.Total = d.TotalSize; v.Free = d.TotalFreeSpace; l.Add(v); sig.Append(v.Name).Append('|').Append(v.Total).Append(',');
            } catch { }
        }
        Vols = l.ToArray(); Sig = sig.ToString(); System.Threading.Interlocked.Increment(ref stamp);
    }
}
}
