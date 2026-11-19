// Code natif de Oliv_Maintenance : compilé par build.ps1 dans une seule DLL embarquée dans le script (chargée en mémoire
// au démarrage, aucune compilation sur le poste, aucun fichier DLL écrit). Syntaxe C# 5 (compilateur du .NET Framework).
// Recherche globale : correspondance approchée (accents, fautes de frappe)
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text;
namespace _OlivM {
public static class Fuzzy {
    class Unit { public int Id; public string[] T; public string[] B; public string TN; }
    static List<Unit> units = new List<Unit>();
    static Dictionary<string, string> canon = new Dictionary<string, string>();
    static List<KeyValuePair<string, string>> phrases = new List<KeyValuePair<string, string>>();
    static readonly HashSet<string> stop = new HashSet<string>(new[] { "le","la","les","l","de","des","du","d","un","une","et","ou","a","au","aux","pour","sur","en","dans","par","avec","sans","ce","cette","ces","mon","ma","mes","comment","faire","je","veux","the","of","to" });
    public static string Norm(string s) {
        if (string.IsNullOrEmpty(s)) return "";
        string d = s.ToLowerInvariant().Normalize(NormalizationForm.FormD);
        var sb = new StringBuilder(d.Length);
        foreach (char c in d) {
            var cat = CharUnicodeInfo.GetUnicodeCategory(c);
            if (cat == UnicodeCategory.NonSpacingMark) continue;
            sb.Append(char.IsLetterOrDigit(c) ? c : ' ');
        }
        string r = " " + System.Text.RegularExpressions.Regex.Replace(sb.ToString(), "\\s+", " ").Trim() + " ";
        foreach (var p in phrases) r = r.Replace(" " + p.Key + " ", " " + p.Value + " ");
        return r.Trim();
    }
    static string Stem(string t) {
        if (t.Length > 4 && (t.EndsWith("s") || t.EndsWith("x"))) t = t.Substring(0, t.Length - 1);
        return t;
    }
    static string Canon(string t) { string c; return canon.TryGetValue(t, out c) ? c : null; }
    // jetons d'un texte indexé : mot d'origine (sans pluriel) ET mot de référence de son groupe de synonymes,
    // pour qu'un début de mot (« chkds ») trouve toujours le mot exact même s'il appartient à un groupe
    static string[] Tok(string s) {
        var l = new List<string>();
        foreach (var x in Norm(s).Split(new[] { ' ' }, StringSplitOptions.RemoveEmptyEntries)) {
            if (stop.Contains(x)) continue;
            string t = Stem(x); l.Add(t); string c = Canon(t); if (c != null && c != t) l.Add(c);
        }
        return l.Distinct().ToArray();
    }
    static string[] QTok(string s) { return Norm(s).Split(new[] { ' ' }, StringSplitOptions.RemoveEmptyEntries).Where(x => !stop.Contains(x)).Select(Stem).Distinct().ToArray(); }
    public static void Clear() { units.Clear(); }
    public static void ResetSyn() { canon.Clear(); phrases.Clear(); }
    // phrase normalisée remplacée par un jeton unique (« mise a jour » -> « maj »)
    public static void AddPhrase(string phrase, string token) { phrases.Add(new KeyValuePair<string, string>(Norm(phrase), token)); phrases.Sort((a, b) => b.Key.Length.CompareTo(a.Key.Length)); }
    // groupe de synonymes : tous ramenés au premier
    public static void AddSyn(string csv) {
        var w = csv.Split('|').Select(x => Norm(x).Replace(" ", "")).Where(x => x.Length > 0).ToArray();
        if (w.Length == 0) return;
        string head = w[0]; if (head.Length > 4 && (head.EndsWith("s") || head.EndsWith("x"))) head = head.Substring(0, head.Length - 1);
        foreach (var x in w) { string k = x; if (k.Length > 4 && (k.EndsWith("s") || k.EndsWith("x"))) k = k.Substring(0, k.Length - 1); canon[k] = head; }
    }
    public static void Add(int id, string title, string body) { units.Add(new Unit { Id = id, T = Tok(title), B = Tok(body), TN = Norm(title) }); }
    static int Lev(string a, string b) {
        if (Math.Abs(a.Length - b.Length) > 2) return 9;
        var d = new int[b.Length + 1]; for (int j = 0; j <= b.Length; j++) d[j] = j;
        for (int i = 1; i <= a.Length; i++) {
            int prev = d[0]; d[0] = i;
            for (int j = 1; j <= b.Length; j++) { int t = d[j]; d[j] = Math.Min(Math.Min(d[j] + 1, d[j - 1] + 1), prev + (a[i - 1] == b[j - 1] ? 0 : 1)); prev = t; }
        }
        return d[b.Length];
    }
    static double Match(string q, string[] toks) {
        double best = 0;
        foreach (var t in toks) {
            double s = 0;
            if (t == q) s = 1.0;
            else if (q.Length >= 2 && t.StartsWith(q)) s = 0.85;
            else if (q.Length >= 3 && t.Contains(q)) s = 0.6;
            else if (q.Length >= 4) { int l = Lev(q, t); if (l == 1) s = 0.55; else if (l == 2 && q.Length >= 7) s = 0.4; }
            if (s > best) { best = s; if (best >= 1) break; }
        }
        return best;
    }
    // résultats triés : jetons de la requête cherchés dans le titre (x3) puis le reste (x1), tolérance aux fautes,
    // accents et pluriels ignorés, synonymes ; tous les mots doivent trouver une correspondance (sinon pénalité forte)
    public static int[] Query(string q, int max) {
        var qt = QTok(q); string qn = Norm(q);
        if (qt.Length == 0) return new int[0];
        var res = new List<KeyValuePair<int, double>>();
        foreach (var u in units) {
            double sc = 0; int hit = 0;
            foreach (var t in qt) {
                double a = Match(t, u.T) * 3, b = Match(t, u.B);
                // synonyme : mot de référence du groupe cherché aussi, un peu moins bien noté que le mot lui-même
                string c = Canon(t);
                if (c != null && c != t) { a = Math.Max(a, Match(c, u.T) * 2.7); b = Math.Max(b, Match(c, u.B) * 0.9); }
                double m = Math.Max(a, b); if (m > 0) hit++; sc += m;
            }
            if (hit == 0) continue;
            // mots non trouvés tolérés (« imprimante bloquée », « dark mode ») si au moins la moitié correspond, avec pénalité
            if (hit < qt.Length) { if (hit * 2 >= qt.Length) sc *= 0.35; else continue; }
            if (qn.Length >= 3 && u.TN.Contains(qn)) sc += 2;
            if (u.TN.StartsWith(qn)) sc += 1;
            res.Add(new KeyValuePair<int, double>(u.Id, sc / Math.Sqrt(1 + 0.05 * u.T.Length)));
        }
        return res.OrderByDescending(x => x.Value).Take(max).Select(x => x.Key).ToArray();
    }
}
}
