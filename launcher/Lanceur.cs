// Lanceur Oliv_Maintenance.exe : compilé par build.ps1 (Windows PowerShell 5.1, compilateur C# du .NET Framework 4.x).
// Manifeste requireAdministrator (élévation UAC au lancement). Le script assemblé est embarqué compressé (ressource app.ps1.gz),
// écrit dans C:\ProgramData\Oliv_Maintenance\App après mise en conformité des droits de C:\ProgramData\Oliv_Maintenance (même règle que
// Protect-AppDir dans src\00-entree.ps1), puis exécuté par Windows PowerShell 5.1 64 bits en STA, sans console,
// exactement comme Oliv_Maintenance.cmd. Syntaxe C# 5 uniquement (compilateur du .NET Framework).
// __VERSION__ et __VERSION4__ sont remplacés par build.ps1.
using System;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Security.AccessControl;
using System.Security.Principal;

[assembly: AssemblyTitle("Oliv_Maintenance")]
[assembly: AssemblyDescription("Oliv_Maintenance - maintenance des postes Windows")]
[assembly: AssemblyCompany("Oliv")]
[assembly: AssemblyProduct("Oliv_Maintenance")]
[assembly: AssemblyCopyright("Oliv")]
[assembly: AssemblyVersion("__VERSION4__")]
[assembly: AssemblyFileVersion("__VERSION4__")]
[assembly: AssemblyInformationalVersion("__VERSION__")]

namespace _OlivM
{
    static class Lanceur
    {
        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        static extern int MessageBoxW(IntPtr hWnd, string text, string caption, uint type);

        static readonly SecurityIdentifier Admins = new SecurityIdentifier(WellKnownSidType.BuiltinAdministratorsSid, null);
        static readonly SecurityIdentifier SystemSid = new SecurityIdentifier(WellKnownSidType.LocalSystemSid, null);
        static readonly SecurityIdentifier Users = new SecurityIdentifier(WellKnownSidType.BuiltinUsersSid, null);
        // écriture : données, ajout, attributs étendus, suppression d'enfants, attributs, suppression, droits, propriétaire, GENERIC_ALL, GENERIC_WRITE
        const long WriteMask = 0x500D0156;

        [STAThread]
        static int Main()
        {
            try
            {
                string data = Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData);
                string root = Path.Combine(data, "Oliv_Maintenance");
                string app = Path.Combine(root, "App");
                if (!Protect(root))
                    return Fail("Les droits du dossier " + root + " n'ont pas pu être sécurisés : lancement annulé.\n\nVérifier le propriétaire et les droits du dossier (icacls \"" + root + "\").");

                Directory.CreateDirectory(app);
                foreach (string f in Directory.GetFiles(app)) File.Delete(f);
                foreach (string d in Directory.GetDirectories(app)) Directory.Delete(d, true);
                string ps1 = Path.Combine(app, "Oliv_Maintenance.ps1");
                using (Stream res = Assembly.GetExecutingAssembly().GetManifestResourceStream("app.ps1.gz"))
                using (GZipStream gz = new GZipStream(res, CompressionMode.Decompress))
                using (FileStream fs = new FileStream(ps1, FileMode.CreateNew, FileAccess.Write, FileShare.Read))
                {
                    gz.CopyTo(fs);
                }

                string sys32 = Environment.GetFolderPath(Environment.SpecialFolder.System);
                ProcessStartInfo psi = new ProcessStartInfo(Path.Combine(sys32, @"WindowsPowerShell\v1.0\powershell.exe"));
                psi.Arguments = "-NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -Command \"$global:_OlivMScriptPath=$env:_OLIVM_SELF; Invoke-Expression ([IO.File]::ReadAllText($env:_OLIVM_SELF, [Text.Encoding]::UTF8))\"";
                psi.UseShellExecute = false;
                psi.CreateNoWindow = true;
                psi.WorkingDirectory = app;
                psi.EnvironmentVariables["_OLIVM_SELF"] = ps1;
                psi.EnvironmentVariables["_OLIVM_HIDDEN"] = "1";
                psi.EnvironmentVariables["_OLIVM_EXE"] = Assembly.GetExecutingAssembly().Location;
                Process.Start(psi);
                return 0;
            }
            catch (Exception ex)
            {
                return Fail("Lancement impossible : " + ex.Message);
            }
        }

        static int Fail(string text)
        {
            MessageBoxW(IntPtr.Zero, text, "Oliv_Maintenance __VERSION__", 0x10);
            return 1;
        }

        // même règle que Test-AclSafe (src\00-entree.ps1)
        static bool IsSafe(string path)
        {
            try
            {
                DirectorySecurity acl = Directory.GetAccessControl(path);
                if (!acl.AreAccessRulesProtected) return false;
                SecurityIdentifier owner = (SecurityIdentifier)acl.GetOwner(typeof(SecurityIdentifier));
                if (owner != Admins && owner != SystemSid) return false;
                foreach (FileSystemAccessRule r in acl.GetAccessRules(true, true, typeof(SecurityIdentifier)))
                {
                    if (r.AccessControlType != AccessControlType.Allow) continue;
                    SecurityIdentifier sid = (SecurityIdentifier)r.IdentityReference;
                    if (sid == Admins || sid == SystemSid) continue;
                    if (((long)(int)r.FileSystemRights & WriteMask) != 0) return false;
                }
                return true;
            }
            catch { return false; }
        }

        static void Run(string exe, string args)
        {
            ProcessStartInfo psi = new ProcessStartInfo(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), exe), args);
            psi.UseShellExecute = false;
            psi.CreateNoWindow = true;
            psi.RedirectStandardInput = true;
            psi.RedirectStandardOutput = true;
            psi.RedirectStandardError = true;
            using (Process p = Process.Start(psi))
            {
                p.StandardInput.Close();
                p.StandardOutput.ReadToEnd();
                p.StandardError.ReadToEnd();
                p.WaitForExit();
            }
        }

        static bool Protect(string root)
        {
            Directory.CreateDirectory(root);
            if (IsSafe(root)) return true;
            Run("takeown.exe", "/F \"" + root + "\" /A /R");
            DirectorySecurity sec = new DirectorySecurity();
            sec.SetOwner(Admins);
            sec.SetAccessRuleProtection(true, false);
            InheritanceFlags inh = InheritanceFlags.ContainerInherit | InheritanceFlags.ObjectInherit;
            sec.AddAccessRule(new FileSystemAccessRule(Admins, FileSystemRights.FullControl, inh, PropagationFlags.None, AccessControlType.Allow));
            sec.AddAccessRule(new FileSystemAccessRule(SystemSid, FileSystemRights.FullControl, inh, PropagationFlags.None, AccessControlType.Allow));
            sec.AddAccessRule(new FileSystemAccessRule(Users, FileSystemRights.ReadAndExecute, inh, PropagationFlags.None, AccessControlType.Allow));
            Directory.SetAccessControl(root, sec);
            if (Directory.GetFileSystemEntries(root).Length > 0) Run("icacls.exe", "\"" + Path.Combine(root, "*") + "\" /reset /T /C /Q");
            string cache = Path.Combine(root, @"Maintenance\_etat\cache");
            if (Directory.Exists(cache)) { try { Directory.Delete(cache, true); } catch { } }
            return IsSafe(root);
        }
    }
}
