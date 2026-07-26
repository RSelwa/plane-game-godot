using Godot;
using System;
using System.Collections.Generic;
using System.Text.Json;

namespace CockpitChaos;

/// <summary>
/// Authoritative cockpit state + the KTANE puzzle brain. Owns each control's current and
/// required state, the flight FACTS (edgework the pilot reads), the MANUAL (per-module
/// ordered decision lists), and landing validation. Pure C# so the test harness can drive
/// it via reflection (see <see cref="SelfTest"/>). Presentation lives in GDScript.
///
/// Everything is generated from ONE seed (<see cref="GenerateFlight"/>): the facts are
/// rolled, then each module's required state is DERIVED by walking its decision list
/// top-to-bottom (first matching branch wins; a final "else" is the default). The required
/// config is never stored as data — it only exists as the consequence of facts + rules.
/// </summary>
[GlobalClass]
public partial class CockpitBrain : Node
{
	[Signal]
	public delegate void StateChangedEventHandler(string id, int state);

	private const string Vowels = "AEIOUY"; // Y counts as a vowel

	// --- Controls -----------------------------------------------------------------
	private readonly Dictionary<string, string[]> _labels = new();
	private readonly List<string> _controlOrder = new();
	private readonly Dictionary<string, int> _state = new();
	private readonly Dictionary<string, int> _required = new();

	public void RegisterControl(string id, string[] stateLabels)
	{
		if (string.IsNullOrEmpty(id)) { GD.PushError("CockpitBrain: empty control id ignored."); return; }
		if (_labels.ContainsKey(id)) { GD.PushError($"CockpitBrain: duplicate control id '{id}' ignored."); return; }
		int n = (stateLabels == null || stateLabels.Length < 1) ? 1 : stateLabels.Length;
		var labels = new string[n];
		for (int i = 0; i < n; i++)
			labels[i] = (stateLabels != null && i < stateLabels.Length) ? stateLabels[i] : i.ToString();
		_labels[id] = labels;
		_controlOrder.Add(id);
		_state[id] = 0;
	}

	public int NumStates(string id) => _labels.TryGetValue(id, out var l) ? l.Length : 0;
	public int GetState(string id) => _state.TryGetValue(id, out var s) ? s : -1;
	public string StateLabel(string id, int state) =>
		_labels.TryGetValue(id, out var l) && state >= 0 && state < l.Length ? l[state] : "?";

	public int LabelIndex(string id, string label)
	{
		if (!_labels.TryGetValue(id, out var l)) return -1;
		for (int i = 0; i < l.Length; i++)
			if (string.Equals(l[i], label, StringComparison.Ordinal)) return i;
		return -1;
	}

	public int RequestCycle(string id)
	{
		if (!_state.ContainsKey(id)) { GD.PushError($"CockpitBrain: cycle unknown control '{id}'."); return -1; }
		int n = _labels[id].Length;
		int s = (_state[id] + 1) % n;
		_state[id] = s;
		EmitSignal(SignalName.StateChanged, id, s);
		return s;
	}

	public void SetState(string id, int state)
	{
		if (!_state.ContainsKey(id)) return;
		int n = _labels[id].Length;
		_state[id] = ((state % n) + n) % n;
		EmitSignal(SignalName.StateChanged, id, _state[id]);
	}

	public void SetRequired(string id, int state) => _required[id] = state;
	public void ClearRequired() => _required.Clear();
	public bool HasRequired(string id) => _required.ContainsKey(id);
	public int RequiredState(string id) => _required.TryGetValue(id, out var r) ? r : -1;

	public bool IsValid()
	{
		foreach (var kv in _required)
		{
			if (!_state.TryGetValue(kv.Key, out var s)) return false;
			if (s != kv.Value) return false;
		}
		return true;
	}

	// --- Facts (edgework the pilot reads to the tower) ----------------------------
	private sealed class FactDef
	{
		public string[] Values;      // pick one, when non-null
		public string Gen;           // "number" generator, else null
		public int Min, Max;
	}

	private readonly Dictionary<string, FactDef> _factDefs = new();
	private readonly List<string> _factOrder = new();
	private readonly Dictionary<string, string> _fact = new();

	public string[] FactIds() => _factOrder.ToArray();
	public string FactValue(string id) => _fact.TryGetValue(id, out var v) ? v : "?";

	// --- Manual (per-module ordered decision lists) -------------------------------
	private sealed class Condition
	{
		public string Fact, Op, Value;
		public bool Eval(string factValue)
		{
			string v = factValue ?? "";
			switch (Op)
			{
				case "eq": return string.Equals(v, Value, StringComparison.Ordinal);
				case "neq": return !string.Equals(v, Value, StringComparison.Ordinal);
				case "starts": return v.StartsWith(Value ?? "", StringComparison.Ordinal);
				case "ends": return v.EndsWith(Value ?? "", StringComparison.Ordinal);
				case "contains": return v.Contains(Value ?? "", StringComparison.Ordinal);
				case "firstVowel": return v.Length > 0 && IsVowel(v[0]);
				case "lastVowel": return v.Length > 0 && IsVowel(v[v.Length - 1]);
				case "firstConsonant": return v.Length > 0 && IsConsonant(v[0]);
				case "lastConsonant": return v.Length > 0 && IsConsonant(v[v.Length - 1]);
				case "even": return int.TryParse(v, out var n1) && (n1 % 2 == 0);
				case "odd": return int.TryParse(v, out var n2) && (n2 % 2 != 0);
				default: return false;
			}
		}
		public string Phrase()
		{
			switch (Op)
			{
				case "eq": return $"{Fact} is {Value}";
				case "neq": return $"{Fact} is not {Value}";
				case "starts": return $"{Fact} starts with {Value}";
				case "ends": return $"{Fact} ends with {Value}";
				case "contains": return $"{Fact} contains {Value}";
				case "firstVowel": return $"first letter of {Fact} is a vowel";
				case "lastVowel": return $"last letter of {Fact} is a vowel";
				case "firstConsonant": return $"first letter of {Fact} is a consonant";
				case "lastConsonant": return $"last letter of {Fact} is a consonant";
				case "even": return $"{Fact} is even";
				case "odd": return $"{Fact} is odd";
				default: return $"{Fact} {Op} {Value}";
			}
		}
	}

	private sealed class Branch
	{
		public readonly List<Condition> When = new();
		public bool IsElse;
		public int SetState;
	}

	private readonly Dictionary<string, List<Branch>> _modules = new();
	private readonly List<string> _moduleOrder = new();
	private readonly List<string> _manualErrors = new();

	private static bool IsVowel(char c) => Vowels.IndexOf(char.ToUpperInvariant(c)) >= 0;
	private static bool IsConsonant(char c) => char.IsLetter(c) && !IsVowel(c);

	private static readonly HashSet<string> _knownOps = new()
	{
		"eq", "neq", "starts", "ends", "contains",
		"firstVowel", "lastVowel", "firstConsonant", "lastConsonant", "even", "odd",
	};

	/// <summary>
	/// Load facts + manual from JSON. Shape:
	/// { "facts":[{"id","values":[..]} | {"id","gen":"number","min","max"}],
	///   "modules":{ controlId:[ {"when":[{"fact","op","value"?}],"set":label} , ... , {"else":label} ] } }
	/// Controls must already be registered so state labels resolve. Returns "OK" or a
	/// "|"-joined list of validation errors (also pushed as engine errors) — a typo'd fact,
	/// control, op, or label is caught here, not as a silently-broken round.
	/// </summary>
	public string LoadManualJson(string json)
	{
		_factDefs.Clear(); _factOrder.Clear(); _fact.Clear();
		_modules.Clear(); _moduleOrder.Clear(); _manualErrors.Clear();
		try
		{
			using var doc = JsonDocument.Parse(json);
			var root = doc.RootElement;

			if (root.TryGetProperty("facts", out var facts))
				foreach (var f in facts.EnumerateArray())
				{
					string id = f.GetProperty("id").GetString() ?? "";
					var def = new FactDef();
					if (f.TryGetProperty("values", out var vals))
					{
						var list = new List<string>();
						foreach (var v in vals.EnumerateArray()) list.Add(v.GetString() ?? "");
						def.Values = list.ToArray();
					}
					if (f.TryGetProperty("gen", out var gen))
					{
						def.Gen = gen.GetString();
						def.Min = f.TryGetProperty("min", out var mn) ? mn.GetInt32() : 0;
						def.Max = f.TryGetProperty("max", out var mx) ? mx.GetInt32() : 0;
					}
					if (string.IsNullOrEmpty(id)) _manualErrors.Add("fact with empty id");
					else if ((def.Values == null || def.Values.Length == 0) && def.Gen == null)
						_manualErrors.Add($"fact '{id}': needs 'values' or 'gen'");
					else
					{
						if (!_factDefs.ContainsKey(id)) _factOrder.Add(id);
						_factDefs[id] = def;
						_fact[id] = def.Values is { Length: > 0 } ? def.Values[0] : (def.Min.ToString());
					}
				}

			if (root.TryGetProperty("modules", out var modules))
				foreach (var mod in modules.EnumerateObject())
				{
					string controlId = mod.Name;
					if (!_labels.ContainsKey(controlId))
						_manualErrors.Add($"module '{controlId}': unknown control");
					var branches = new List<Branch>();
					int bi = 0;
					foreach (var b in mod.Value.EnumerateArray())
					{
						var branch = new Branch();
						string setLabel;
						if (b.TryGetProperty("else", out var elseVal))
						{
							branch.IsElse = true;
							setLabel = elseVal.GetString() ?? "";
						}
						else
						{
							setLabel = b.TryGetProperty("set", out var setVal) ? (setVal.GetString() ?? "") : "";
							if (b.TryGetProperty("when", out var whenArr))
								foreach (var cond in whenArr.EnumerateArray())
								{
									var c = new Condition
									{
										Fact = cond.GetProperty("fact").GetString() ?? "",
										Op = cond.GetProperty("op").GetString() ?? "",
										Value = cond.TryGetProperty("value", out var cv) ? cv.GetString() : null,
									};
									if (!_factDefs.ContainsKey(c.Fact))
										_manualErrors.Add($"{controlId} branch {bi}: unknown fact '{c.Fact}'");
									if (!_knownOps.Contains(c.Op))
										_manualErrors.Add($"{controlId} branch {bi}: unknown op '{c.Op}'");
									branch.When.Add(c);
								}
						}
						int idx = LabelIndex(controlId, setLabel);
						if (_labels.ContainsKey(controlId) && idx < 0)
							_manualErrors.Add($"{controlId} branch {bi}: no state '{setLabel}'");
						branch.SetState = Math.Max(0, idx);
						branches.Add(branch);
						bi++;
					}
					if (!_modules.ContainsKey(controlId)) _moduleOrder.Add(controlId);
					_modules[controlId] = branches;
				}
		}
		catch (Exception e)
		{
			_manualErrors.Add("JSON parse error: " + e.Message);
		}
		foreach (var err in _manualErrors) GD.PushError("CockpitManual: " + err);
		return _manualErrors.Count == 0 ? "OK" : string.Join(" | ", _manualErrors);
	}

	public bool ManualOk() => _manualErrors.Count == 0;

	/// <summary>
	/// Roll every fact from the seed (stable order = determinism), then DERIVE each module's
	/// required state by walking its decision list top-to-bottom; the FIRST branch whose
	/// conditions all pass wins (an "else" always passes). Same seed => same flight.
	/// </summary>
	public void GenerateFlight(int seed)
	{
		var rng = new Random(seed);
		foreach (var id in _factOrder)
		{
			var def = _factDefs[id];
			if (def.Values is { Length: > 0 })
				_fact[id] = def.Values[rng.Next(def.Values.Length)];
			else if (def.Gen == "number")
				_fact[id] = rng.Next(def.Min, def.Max + 1).ToString();
		}
		ClearRequired();
		foreach (var controlId in _moduleOrder)
		{
			foreach (var branch in _modules[controlId])
			{
				bool match = branch.IsElse;
				if (!branch.IsElse)
				{
					match = true;
					foreach (var cond in branch.When)
						if (!cond.Eval(_fact.TryGetValue(cond.Fact, out var fv) ? fv : "")) { match = false; break; }
				}
				if (match) { _required[controlId] = branch.SetState; break; }
			}
		}
	}

	/// <summary>Render the tower binder: each module as its numbered if/else-if/else list.</summary>
	public string ManualText()
	{
		var lines = new List<string>();
		foreach (var controlId in _moduleOrder)
		{
			lines.Add(controlId.ToUpperInvariant());
			var branches = _modules[controlId];
			for (int i = 0; i < branches.Count; i++)
			{
				var br = branches[i];
				string label = StateLabel(controlId, br.SetState);
				if (br.IsElse)
				{
					lines.Add($"  {i + 1}. else -> {label}");
				}
				else
				{
					var parts = new List<string>();
					foreach (var c in br.When) parts.Add(c.Phrase());
					string prefix = i == 0 ? "if" : "else if";
					lines.Add($"  {i + 1}. {prefix} {string.Join(" and ", parts)} -> {label}");
				}
			}
		}
		return string.Join("\n", lines);
	}

	/// <summary>Self-contained logic test invoked in one reflection call. Returns a PASS/FAIL report.</summary>
	public static string SelfTest()
	{
		var log = new List<string>();

		var b = new CockpitBrain();
		b.RegisterControl("gear", new[] { "UP", "DOWN" });
		b.SetRequired("gear", 1);
		bool v1 = !b.IsValid();          // gear=0, need 1 -> invalid
		b.RequestCycle("gear");
		bool v2 = b.IsValid();           // gear=1 -> valid
		b.SetRequired("ghost", 0);
		bool v3 = !b.IsValid();          // missing control -> invalid
		log.Add($"validate {v1 && v2 && v3} {((v1 && v2 && v3) ? "OK" : "FAIL")}");

		// Decision-list derivation with real predicates.
		var c = new CockpitBrain();
		c.RegisterControl("lv", new[] { "UP", "CENTER", "DOWN" });
		string manual =
			"{\"facts\":[" +
			"{\"id\":\"starting_airport\",\"values\":[\"OLY\",\"BCN\"]}," +
			"{\"id\":\"flight_number\",\"gen\":\"number\",\"min\":1000,\"max\":9999}]," +
			"\"modules\":{\"lv\":[" +
			"{\"when\":[{\"fact\":\"starting_airport\",\"op\":\"lastVowel\"}],\"set\":\"UP\"}," +
			"{\"when\":[{\"fact\":\"flight_number\",\"op\":\"even\"}],\"set\":\"DOWN\"}," +
			"{\"else\":\"CENTER\"}]}}";
		string load = c.LoadManualJson(manual);
		c.GenerateFlight(4821);
		string ap = c.FactValue("starting_airport");
		bool lastVowel = ap.Length > 0 && Vowels.IndexOf(char.ToUpperInvariant(ap[ap.Length - 1])) >= 0;
		bool even = int.TryParse(c.FactValue("flight_number"), out var fn) && fn % 2 == 0;
		int expect = lastVowel ? 0 : (even ? 2 : 1);
		bool deriv = load == "OK" && c.RequiredState("lv") == expect;
		log.Add($"decision-list(ap={ap},fn={c.FactValue("flight_number")}) got={c.RequiredState("lv")} exp={expect} {(deriv ? "OK" : "FAIL")}");

		// Validation catches a rule naming a control that doesn't exist.
		var bad = new CockpitBrain();
		bad.RegisterControl("lv", new[] { "UP", "DOWN" });
		string badres = bad.LoadManualJson("{\"facts\":[{\"id\":\"F\",\"values\":[\"X\"]}],\"modules\":{\"ghost\":[{\"else\":\"UP\"}]}}");
		bool caught = badres != "OK";
		log.Add($"validation caught bad control={caught} {(caught ? "OK" : "FAIL")}");

		bool allOk = v1 && v2 && v3 && deriv && caught;
		return (allOk ? "SELFTEST PASS :: " : "SELFTEST FAIL :: ") + string.Join(" | ", log);
	}
}
