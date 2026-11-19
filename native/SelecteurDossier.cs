// Code natif de Oliv_Maintenance : compilé par build.ps1 dans une seule DLL embarquée dans le script (chargée en mémoire
// au démarrage, aucune compilation sur le poste, aucun fichier DLL écrit). Syntaxe C# 5 (compilateur du .NET Framework).
// Sélecteur de dossier moderne (IFileOpenDialog, FOS_PICKFOLDERS) de l'analyse d'espace disque
using System;
using System.Runtime.InteropServices;
namespace _OlivM {
public static class FolderPick {
    [ComImport, Guid("DC1C5A9C-E88A-4DDE-A5A1-60F82A20AEF7")] class FileOpenDialogRCW { }
    [ComImport, Guid("42F85136-DB7E-439C-85F1-E4075D135FC8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IFileOpenDialog {
        [PreserveSig] int Show(IntPtr hwnd);
        void SetFileTypes(uint c, IntPtr f); void SetFileTypeIndex(uint i); void GetFileTypeIndex(out uint i);
        void Advise(IntPtr e, out uint c); void Unadvise(uint c);
        void SetOptions(uint fos); void GetOptions(out uint fos);
        void SetDefaultFolder(IShellItem si); void SetFolder(IShellItem si);
        void GetFolder(out IShellItem si); void GetCurrentSelection(out IShellItem si);
        void SetFileName([MarshalAs(UnmanagedType.LPWStr)] string n); void GetFileName([MarshalAs(UnmanagedType.LPWStr)] out string n);
        void SetTitle([MarshalAs(UnmanagedType.LPWStr)] string t); void SetOkButtonLabel([MarshalAs(UnmanagedType.LPWStr)] string t);
        void SetFileNameLabel([MarshalAs(UnmanagedType.LPWStr)] string t);
        void GetResult(out IShellItem si);
    }
    [ComImport, Guid("43826D1E-E718-42EE-BC55-A1E261C37BFE"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IShellItem {
        void BindToHandler(IntPtr pbc, ref Guid bhid, ref Guid riid, out IntPtr ppv); void GetParent(out IShellItem si);
        void GetDisplayName(uint sigdn, [MarshalAs(UnmanagedType.LPWStr)] out string name);
        void GetAttributes(uint mask, out uint attr); void Compare(IShellItem si, uint hint, out int order);
    }
    [DllImport("shell32.dll", CharSet = CharSet.Unicode, PreserveSig = false)]
    static extern void SHCreateItemFromParsingName(string path, IntPtr pbc, ref Guid riid, out IShellItem si);
    public static string Pick(IntPtr owner, string title, string start) {
        IFileOpenDialog d = (IFileOpenDialog)new FileOpenDialogRCW();
        uint o; d.GetOptions(out o); d.SetOptions(o | 0x20 | 0x40 | 0x800);   // PICKFOLDERS | FORCEFILESYSTEM | PATHMUSTEXIST
        if (!string.IsNullOrEmpty(title)) d.SetTitle(title);
        if (!string.IsNullOrEmpty(start)) { try { Guid g = typeof(IShellItem).GUID; IShellItem si; SHCreateItemFromParsingName(start, IntPtr.Zero, ref g, out si); d.SetFolder(si); } catch { } }
        if (d.Show(owner) != 0) return null;
        IShellItem r; d.GetResult(out r); string p; r.GetDisplayName(0x80058000, out p); return p;   // SIGDN_FILESYSPATH
    }
}
}