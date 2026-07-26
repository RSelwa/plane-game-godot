using Godot;
using System;
using System.Collections.Generic;
using System.Text.Json;

namespace CockpitChaos;

/// <summary>
/// Authoritative cockpit state + the KTANE puzzle brain. Owns each control's current
/// and required state, the cue/manual system, and landing validation. Pure C# logic so
/// the test harness can drive it via reflection (see <see cref="SelfTest"/>). Presentation
/// (CSG cockpit, clicks, UI) lives in GDScript and routes every change through this node.
///
/// The manual is DATA (loaded from JSON via <see cref="LoadManualJson"/>), not code: the
/// required config each round is DERIVED from rolled cues + rules, never stored directly.
/// </summary>
[GlobalClass]
public partial class CockpitBrain : Node
{
	[Signal]
	public delegate void StateChangedEventHandler(string id, int state);

	// --- Controls -----------------------------------------------------------------
	private readonly Dictionary<string, string[]> _labels = new(); // id -> state labels
	private readonly List<string> _controlOrder = new();           // stable iteration
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

	/// <summary>Index of a state label within a control (Ordinal), or -1 if not found.</summary>
	public int LabelIndex(string id, string label)
	{
		if (!_labels.TryGetValue(id, out var l)) return -1;
		for (int i = 0; i < l.Length; i++)
			if (string.Equals(l[i], label, StringComparison.Ordinal)) return i;
		return -1;
	}

	public int RequestCycle(string id)
	{
		if (!_state.ContainsKey(id)) { GD.PushError($"CockpitBrain: cycle on unknown control '{id}'."); return -1; }
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

	/// <summary>
	/// Landing check: every required control must EXIST and match its required state.
	/// A requirement on a control that was never registered is an automatic FAIL.
	/// </summary>
	public bool IsValid()
	{
		foreach (var kv in _required)
		{
			if (!_state.TryGetValue(kv.Key, out var s)) return false;
			if (s != kv.Value) return false;
		}
		return true;
	}

	// --- Cue / Manual (data-driven puzzle) ----------------------------------------
	private sealed class Condition
	{
		public readonly string CueId, Match;
		public readonly bool Prefix;
		public Condition(string cueId, string match, bool prefix) { CueId = cueId; Match = match; Prefix = prefix; }
		public bool Fires(string v) => Prefix
			? v.StartsWith(Match, StringComparison.Ordinal)
			: string.Equals(v, Match, StringComparison.Ordinal);
		public string Display => Prefix ? $"{CueId} {Match}*" : $"{CueId} {Match}";
	}

	private sealed class Rule
	{
		public readonly List<Condition> When = new();
		public readonly List<(string controlId, int state)> Require = new();
	}

	private readonly Dictionary<string, string[]> _cueValues = new();
	private readonly List<string> _cueOrder = new();        // stable iteration for determinism
	private readonly Dictionary<string, string> _cue = new();
	private readonly List<Rule> _manual = new();
	private readonly List<string> _manualErrors = new();

	public void RegisterCue(string cueId, string[] values)
	{
		if (string.IsNullOrEmpty(cueId) || values == null || values.Length == 0)
		{
			GD.PushError("CockpitBrain: invalid cue registration ignored.");
			return;
		}
		if (!_cueValues.ContainsKey(cueId))
			_cueOrder.Add(cueId);
		_cueValues[cueId] = (string[])values.Clone();
		if (!_cue.ContainsKey(cueId))
			_cue[cueId] = values[0];
	}

	private bool CueValueValid(string cueId, string match, bool prefix)
	{
		if (!_cueValues.TryGetValue(cueId, out var vals)) return false;
		foreach (var v in vals)
			if (prefix ? v.StartsWith(match, StringComparison.Ordinal) : string.Equals(v, match, StringComparison.Ordinal))
				return true;
		return false;
	}

	/// <summary>
	/// Load the whole manual from a JSON string. Shape:
	/// { "cues":[{"id","values":[..]}], "rules":[{"when":{cueId:value}, "require":{controlId:label}}] }
	/// A value ending in '*' is a prefix match. Controls must already be registered so labels
	/// resolve to indices. Returns "OK", or a "|"-joined list of validation errors (also pushed
	/// as engine errors) — a typo'd cue/control/label is caught here, not as a silently-broken round.
	/// </summary>
	public string LoadManualJson(string json)
	{
		_cueValues.Clear(); _cueOrder.Clear(); _cue.Clear(); _manual.Clear(); _manualErrors.Clear();
		try
		{
			using var doc = JsonDocument.Parse(json);
			var root = doc.RootElement;

			if (root.TryGetProperty("cues", out var cues))
				foreach (var c in cues.EnumerateArray())
				{
					string id = c.GetProperty("id").GetString();
					var vals = new List<string>();
					foreach (var v in c.GetProperty("values").EnumerateArray())
						vals.Add(v.GetString());
					RegisterCue(id, vals.ToArray());
				}

			if (root.TryGetProperty("rules", out var rules))
			{
				int ri = 0;
				foreach (var r in rules.EnumerateArray())
				{
					var rule = new Rule();
					foreach (var w in r.GetProperty("when").EnumerateObject())
					{
						string cueId = w.Name;
						string val = w.Value.GetString() ?? "";
						bool prefix = val.EndsWith("*", StringComparison.Ordinal);
						string match = prefix ? val.Substring(0, val.Length - 1) : val;
						if (!_cueValues.ContainsKey(cueId))
							_manualErrors.Add($"rule {ri}: unknown cue '{cueId}'");
						else if (!CueValueValid(cueId, match, prefix))
							_manualErrors.Add($"rule {ri}: '{val}' is not a value of cue '{cueId}'");
						rule.When.Add(new Condition(cueId, match, prefix));
					}
					foreach (var req in r.GetProperty("require").EnumerateObject())
					{
						string controlId = req.Name;
						string label = req.Value.GetString() ?? "";
						if (!_labels.ContainsKey(controlId))
							_manualErrors.Add($"rule {ri}: unknown control '{controlId}'");
						int idx = LabelIndex(controlId, label);
						if (_labels.ContainsKey(controlId) && idx < 0)
							_manualErrors.Add($"rule {ri}: control '{controlId}' has no state '{label}'");
						rule.Require.Add((controlId, Math.Max(0, idx)));
					}
					_manual.Add(rule);
					ri++;
				}
			}
		}
		catch (Exception e)
		{
			_manualErrors.Add("JSON parse error: " + e.Message);
		}
		foreach (var err in _manualErrors)
			GD.PushError("CockpitManual: " + err);
		return _manualErrors.Count == 0 ? "OK" : string.Join(" | ", _manualErrors);
	}

	public string[] CueIds() => _cueOrder.ToArray();
	public string CueValue(string cueId) => _cue.TryGetValue(cueId, out var v) ? v : "?";
	public bool ManualOk() => _manualErrors.Count == 0;

	/// <summary>
	/// Roll every cue (stable order for seed-determinism), then DERIVE the required config
	/// from the rules that fire. Rules apply in order; the FIRST rule to constrain a control
	/// wins (order = priority), so branching is a designed property, not an accident.
	/// </summary>
	public void GenerateScenario(int seed)
	{
		var rng = new Random(seed);
		foreach (var id in _cueOrder)
		{
			var vals = _cueValues[id];
			_cue[id] = vals[rng.Next(vals.Length)];
		}
		ClearRequired();
		foreach (var rule in _manual)
		{
			bool all = true;
			foreach (var cond in rule.When)
				if (!_cue.TryGetValue(cond.CueId, out var v) || !cond.Fires(v)) { all = false; break; }
			if (!all) continue;
			foreach (var (controlId, state) in rule.Require)
				if (!_required.ContainsKey(controlId))
					_required[controlId] = state;
		}
	}

	/// <summary>Render the tower rulebook: one "IF conditions -> required" line per rule.</summary>
	public string ManualText()
	{
		var lines = new List<string>();
		foreach (var rule in _manual)
		{
			var conds = new List<string>();
			foreach (var c in rule.When) conds.Add(c.Display);
			var reqs = new List<string>();
			foreach (var (cid, st) in rule.Require) reqs.Add($"{cid} {StateLabel(cid, st)}");
			lines.Add($"IF {string.Join(" + ", conds)}  ->  {string.Join(", ", reqs)}");
		}
		return string.Join("\n", lines);
	}

	/// <summary>
	/// Self-contained logic test the harness invokes in ONE reflection call (static — no scene
	/// node). Returns a "SELFTEST PASS/FAIL :: ..." report.
	/// </summary>
	public static string SelfTest()
	{
		var b = new CockpitBrain();
		var log = new List<string>();
		b.RegisterControl("gear", new[] { "UP", "DOWN" });
		b.RegisterControl("gear", new[] { "X" }); // duplicate -> rejected
		log.Add($"gear.n={b.NumStates("gear")} exp=2 {(b.NumStates("gear") == 2 ? "OK" : "FAIL")}");
		int s = b.RequestCycle("gear");
		log.Add($"cycle->{s} exp=1 {(s == 1 ? "OK" : "FAIL")}");
		b.SetRequired("gear", 1);
		bool v1 = b.IsValid();
		b.RequestCycle("gear");
		bool v2 = b.IsValid();
		b.SetRequired("ghost", 0);
		bool v3 = b.IsValid();
		log.Add($"valid {v1}/{!v2}/{!v3} exp T/T/T {((v1 && !v2 && !v3) ? "OK" : "FAIL")}");

		// Data-driven manual: derivation + multi-condition + validation.
		var c = new CockpitBrain();
		c.RegisterControl("sw", new[] { "OFF", "ON" });
		c.RegisterControl("lv", new[] { "UP", "CENTER", "DOWN" });
		string manual = "{\"cues\":[{\"id\":\"WARN\",\"values\":[\"GREEN\",\"RED\"]},{\"id\":\"CODE\",\"values\":[\"A1\",\"B7\"]}]," +
			"\"rules\":[{\"when\":{\"WARN\":\"RED\"},\"require\":{\"sw\":\"ON\"}}," +
			"{\"when\":{\"CODE\":\"B*\"},\"require\":{\"lv\":\"CENTER\"}}]}";
		string load = c.LoadManualJson(manual);
		c.GenerateScenario(12345);
		bool deriv = load == "OK";
		deriv &= (c.CueValue("WARN") == "RED") ? c.RequiredState("sw") == 1 : !c.HasRequired("sw");
		deriv &= c.CueValue("CODE").StartsWith("B", StringComparison.Ordinal) ? c.RequiredState("lv") == 1 : !c.HasRequired("lv");
		log.Add($"manual(load={load}) derive={deriv} {(deriv ? "OK" : "FAIL")}");

		// Validation must reject a rule naming a control that doesn't exist.
		var bad = new CockpitBrain();
		bad.RegisterControl("sw", new[] { "OFF", "ON" });
		string badres = bad.LoadManualJson("{\"cues\":[{\"id\":\"W\",\"values\":[\"X\"]}],\"rules\":[{\"when\":{\"W\":\"X\"},\"require\":{\"ghost\":\"ON\"}}]}");
		bool caught = badres != "OK";
		log.Add($"validation caught bad control={caught} {(caught ? "OK" : "FAIL")}");

		bool allOk = b.NumStates("gear") == 2 && s == 1 && v1 && !v2 && !v3 && deriv && caught;
		return (allOk ? "SELFTEST PASS :: " : "SELFTEST FAIL :: ") + string.Join(" | ", log);
	}
}
