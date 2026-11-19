// Code natif de Oliv_Maintenance : compilé par build.ps1 dans une seule DLL embarquée dans le script (chargée en mémoire
// au démarrage, aucune compilation sur le poste, aucun fichier DLL écrit). Syntaxe C# 5 (compilateur du .NET Framework).
// Analyse d'espace disque : arbre des dossiers (FindFirstFileEx, parallèle sur SSD), suppression
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Threading;
using System.Threading.Tasks;
namespace _OlivM {
public class DirNode {
    public string Name; public DirNode Parent; public string Root; public bool IsDir; public bool Denied; public bool Other;
    public long Size; public long Files; public List<DirNode> Children;
    public string Path { get { if (Root != null) return Root; if (Other) return Parent.Path; string p = Parent.Path; return p.EndsWith("\\") ? p + Name : p + "\\" + Name; } }
}
public static class DirScan {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct FindData {
        public uint Attr; public uint C1; public uint C2; public uint A1; public uint A2; public uint W1; public uint W2; public uint SizeHigh; public uint SizeLow; public uint R0; public uint R1;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 260)] public string Name;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 14)] public string Alt;
    }
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern IntPtr FindFirstFileExW(string p, int level, out FindData d, int op, IntPtr f, int flags);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern bool FindNextFileW(IntPtr h, out FindData d);
    [DllImport("kernel32.dll")]
    static extern bool FindClose(IntPtr h);
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct FileOp { public IntPtr Hwnd; public uint Func; public string From; public string To; public ushort Flags; [MarshalAs(UnmanagedType.Bool)] public bool Aborted; public IntPtr Mappings; public string Title; }
    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    static extern int SHFileOperation(ref FileOp op);
    // FO_DELETE, FOF_NOCONFIRMATION | FOF_NOERRORUI | FOF_SILENT (+ FOF_ALLOWUNDO pour la corbeille) ; 0 = succès
    public static int Delete(string path, bool recycle) {
        FileOp op = new FileOp(); op.Func = 3; op.From = path + "\0\0";
        op.Flags = (ushort)(0x0010 | 0x0400 | 0x0004 | (recycle ? 0x0040 : 0));
        return SHFileOperation(ref op);
    }
    public static long Scanned; public static long Bytes; public static long Denied; public static long Cloud;
    // avancement : dossiers de 1er niveau terminés / total (analyse d'un dossier) ; octets lus (analyse d'un lecteur)
    public static int TopTotal; public static int TopDone;
    public static volatile string Current; public static volatile bool Cancel;
    const int KeepFiles = 200;
    static int Degree = 1;
    // degree : nombre de dossiers parcourus en parallèle sur les 2 premiers niveaux (1 = séquentiel, conseillé sur disque dur)
    public static DirNode Scan(string root, int degree) {
        Scanned = 0; Bytes = 0; Denied = 0; Cloud = 0; Cancel = false; Degree = Math.Max(1, degree); TopTotal = 0; TopDone = 0;
        DirNode n = new DirNode(); n.Root = root; n.Name = root; n.IsDir = true;
        Walk(n, 0);
        return n;
    }
    static void Walk(DirNode node, int depth) {
        try { WalkCore(node, depth); } finally { if (depth == 1) Interlocked.Increment(ref TopDone); }
    }
    static void WalkCore(DirNode node, int depth) {
        node.Children = new List<DirNode>();
        if (Cancel) return;
        string basePath = node.Path; if (!basePath.EndsWith("\\")) basePath += "\\";
        Current = basePath;
        FindData d;
        IntPtr h = FindFirstFileExW("\\\\?\\" + basePath + "*", 1, out d, 0, IntPtr.Zero, 2);
        if (h == new IntPtr(-1)) { node.Denied = true; Interlocked.Increment(ref Denied); return; }
        List<DirNode> files = new List<DirNode>();
        long fb = 0, fc = 0, cl = 0;
        try {
            do {
                string name = d.Name;
                if (name == "." || name == "..") continue;
                if ((d.Attr & 0x10) != 0) {
                    if ((d.Attr & 0x400) != 0) continue;
                    DirNode c = new DirNode(); c.Name = name; c.Parent = node; c.IsDir = true;
                    node.Children.Add(c);
                } else {
                    long sz = ((long)d.SizeHigh << 32) | d.SizeLow;
                    if ((d.Attr & 0x400000) != 0 || (d.Attr & 0x1000) != 0) { cl++; sz = 0; }
                    DirNode f = new DirNode(); f.Name = name; f.Parent = node; f.Size = sz; f.Files = 1;
                    files.Add(f); fc++; fb += sz;
                }
            } while (!Cancel && FindNextFileW(h, out d));
        } finally { FindClose(h); }
        Interlocked.Add(ref Scanned, fc); Interlocked.Add(ref Bytes, fb); if (cl > 0) Interlocked.Add(ref Cloud, cl);
        DirNode[] subs = node.Children.ToArray();
        if (depth == 0) TopTotal = subs.Length;
        if (Degree > 1 && depth < 2 && subs.Length > 1) {
            ParallelOptions po = new ParallelOptions(); po.MaxDegreeOfParallelism = Degree;
            Parallel.ForEach(subs, po, delegate(DirNode c) { Walk(c, depth + 1); });
        } else {
            foreach (DirNode c in subs) Walk(c, depth + 1);
        }
        foreach (DirNode c in subs) { node.Size += c.Size; node.Files += c.Files; }
        files.Sort(delegate(DirNode x, DirNode y) { return y.Size.CompareTo(x.Size); });
        long rest = 0; int restN = 0;
        for (int i = 0; i < files.Count; i++) {
            node.Size += files[i].Size; node.Files++;
            if (i < KeepFiles) node.Children.Add(files[i]); else { rest += files[i].Size; restN++; }
        }
        if (restN > 0) { DirNode o = new DirNode(); o.Name = restN + (restN > 1 ? " autres fichiers" : " autre fichier"); o.Parent = node; o.Size = rest; o.Files = restN; o.Other = true; node.Children.Add(o); }
        node.Children.Sort(delegate(DirNode x, DirNode y) { return y.Size.CompareTo(x.Size); });
    }
}
}