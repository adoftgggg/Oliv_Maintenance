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
                // empreinte de l'exe lancé, calculée dès le démarrage : l'application ne recopie l'exe dans ProgramData (exe
                // stable, lancé en administrateur par les raccourcis et l'ouverture de session) que si sa copie a cette empreinte
                string self = Assembly.GetExecutingAssembly().Location;
                string selfSha = Sha256(self);
                string data = Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData);
                string root = Path.Combine(data, "Oliv_Maintenance");
                string app = Path.Combine(root, "App");
                if (!Protect(root))
                    return Fail("Les droits du dossier " + root + " n'ont pas pu être sécurisés : lancement annulé.\n\nVérifier le propriétaire et les droits du dossier (icacls \"" + root + "\").");

                Directory.CreateDirectory(app);
                string ps1 = Path.Combine(app, "Oliv_Maintenance.ps1");
                // script écrit dans un fichier temporaire propre à ce lancement puis substitué d'un coup (File.Replace) : un
                // 2e lancement rapproché (double-clic répété, relance) ne supprime plus le script qu'une instance est en train de lire
                string tmp = Path.Combine(app, "Oliv_Maintenance." + Process.GetCurrentProcess().Id + ".tmp");
                using (Stream res = Assembly.GetExecutingAssembly().GetManifestResourceStream("app.ps1.gz"))
                using (GZipStream gz = new GZipStream(res, CompressionMode.Decompress))
                using (FileStream fs = new FileStream(tmp, FileMode.Create, FileAccess.Write, FileShare.None))
                {
                    gz.CopyTo(fs);
                }
                for (int k = 0; ; k++)
                {
                    try
                    {
                        if (File.Exists(ps1)) File.Replace(tmp, ps1, null); else File.Move(tmp, ps1);
                        break;
                    }
                    catch (IOException) { if (k >= 40) throw; System.Threading.Thread.Sleep(100); }
                    catch (UnauthorizedAccessException) { if (k >= 40) throw; System.Threading.Thread.Sleep(100); }
                }
                // restes (anciens fichiers, sous-dossiers) : supprimés s'ils ne sont pas en cours d'utilisation
                // fichier temporaire d'un autre lancement encore en cours (Oliv_Maintenance.<PID>.tmp, processus vivant) gardé :
                // supprimé avant son File.Replace, il faisait échouer cet autre lancement (« Lancement impossible »)
                foreach (string f in Directory.GetFiles(app)) { if (!string.Equals(f, ps1, StringComparison.OrdinalIgnoreCase) && !IsLiveTmp(f)) { try { File.Delete(f); } catch { } } }
                foreach (string d in Directory.GetDirectories(app)) { try { Directory.Delete(d, true); } catch { } }

                string sys32 = Environment.GetFolderPath(Environment.SpecialFolder.System);
                ProcessStartInfo psi = new ProcessStartInfo(Path.Combine(sys32, @"WindowsPowerShell\v1.0\powershell.exe"));
                psi.Arguments = "-NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -Command \"$global:_OlivMScriptPath=$env:_OLIVM_SELF; Invoke-Expression ([IO.File]::ReadAllText($env:_OLIVM_SELF, [Text.Encoding]::UTF8))\"";
                psi.UseShellExecute = false;
                psi.CreateNoWindow = true;
                psi.WorkingDirectory = app;
                psi.EnvironmentVariables["_OLIVM_SELF"] = ps1;
                psi.EnvironmentVariables["_OLIVM_HIDDEN"] = "1";
                psi.EnvironmentVariables["_OLIVM_EXE"] = self;
                psi.EnvironmentVariables["_OLIVM_EXE_SHA256"] = selfSha;
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

        // fichier temporaire « Oliv_Maintenance.<PID>.tmp » d'un processus encore en cours
        static bool IsLiveTmp(string file)
        {
            string n = Path.GetFileName(file);
            if (!n.StartsWith("Oliv_Maintenance.", StringComparison.OrdinalIgnoreCase) || !n.EndsWith(".tmp", StringComparison.OrdinalIgnoreCase)) return false;
            int pid;
            if (!int.TryParse(n.Substring(17, n.Length - 21), out pid) || pid == Process.GetCurrentProcess().Id) return false;
            try { using (Process p = Process.GetProcessById(pid)) { return !p.HasExited; } } catch { return false; }
        }

        // sorties non redirigées (console masquée du programme) : avant, stdout lu jusqu'au bout avant stderr ; plus de 4 Ko
        // d'erreurs (takeown /R, icacls /T sur beaucoup de fichiers) bloquaient le programme et le lanceur indéfiniment.
        // Entrée fermée : aucune question (takeown) ne peut attendre une réponse.
        static void Run(string exe, string args)
        {
            ProcessStartInfo psi = new ProcessStartInfo(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), exe), args);
            psi.UseShellExecute = false;
            psi.CreateNoWindow = true;
            psi.RedirectStandardInput = true;
            using (Process p = Process.Start(psi))
            {
                p.StandardInput.Close();
                p.WaitForExit();
            }
        }

        // lien (jonction, lien symbolique) : attributs du lien lui-même (GetAttributes ne suit pas la cible)
        static bool IsLink(string path)
        {
            try { return (File.GetAttributes(path) & FileAttributes.ReparsePoint) != 0; }
            catch (FileNotFoundException) { return false; }
            catch (DirectoryNotFoundException) { return false; }
        }

        // lien supprimé sans toucher à sa cible (RemoveDirectory sur une jonction : seul le lien disparaît)
        static void DeleteLink(string path)
        {
            if ((File.GetAttributes(path) & FileAttributes.Directory) != 0) Directory.Delete(path, false); else File.Delete(path);
        }

        // liens du dossier supprimés sans suivre leur cible : à toute profondeur (Deep) ou au premier niveau seulement
        static void RemoveLinks(string dir, bool deep)
        {
            foreach (string e in Directory.GetFileSystemEntries(dir))
            {
                FileAttributes a = File.GetAttributes(e);
                if ((a & FileAttributes.ReparsePoint) != 0) DeleteLink(e);
                else if (deep && (a & FileAttributes.Directory) != 0) RemoveLinks(e, true);
            }
        }

        // empreinte SHA-256 (hexadécimal majuscule, comme Get-FileHash) ; vide si le fichier est illisible
        static string Sha256(string path)
        {
            try
            {
                using (FileStream fs = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
                using (System.Security.Cryptography.SHA256 h = System.Security.Cryptography.SHA256.Create())
                {
                    return BitConverter.ToString(h.ComputeHash(fs)).Replace("-", "");
                }
            }
            catch { return ""; }
        }

        // Jonction ou lien posé à la place du dossier par un utilisateur standard (création libre dans ProgramData) : suivi,
        // il faisait appliquer takeown / icacls à sa cible (C:\Windows...) puis écrire le script dans un dossier contrôlé par
        // cet utilisateur. Lien supprimé et vrai dossier recréé ; droits non conformes : liens supprimés à toute profondeur
        // avant takeown / icacls ; droits conformes : premier niveau contrôlé (liens antérieurs à la mise en conformité).
        static bool Protect(string root)
        {
            if (IsLink(root)) DeleteLink(root);
            Directory.CreateDirectory(root);
            if (IsSafe(root)) { RemoveLinks(root, false); return true; }
            RemoveLinks(root, true);
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
            return IsSafe(root) && !IsLink(root);
        }
    }
}
