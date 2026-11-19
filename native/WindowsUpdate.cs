// Code natif de Oliv_Maintenance : compilé par build.ps1 dans une seule DLL embarquée dans le script (chargée en mémoire
// au démarrage, aucune compilation sur le poste, aucun fichier DLL écrit). Syntaxe C# 5 (compilateur du .NET Framework).
// Recherche WUA interruptible : BeginSearch exige un objet de rappel (ISearchCompletedCallback), classe COM vide
using System;
using System.Runtime.InteropServices;
namespace _OlivM {
[ComImport, Guid("88AEE058-D4B0-4725-A2F1-814A67AE964C"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface ISearchCompletedCallback { void Invoke([MarshalAs(UnmanagedType.IUnknown)] object searchJob, [MarshalAs(UnmanagedType.IUnknown)] object callbackArgs); }
[ComVisible(true), ClassInterface(ClassInterfaceType.None)]
public class WuSearchCb : ISearchCompletedCallback { public void Invoke(object searchJob, object callbackArgs) { } }
}
