extends SceneTree


const PLANTS := {
	"shortid": ["var id: String = _hex(16)", "var id: String = _hex(15)"],
	"orphan": ["\tif parent != \"\":\n\t\tspan[\"parentSpanId\"] = parent\n", ""],
	"edge": ["\t\tif value <= bounds[i]:", "\t\tif value < bounds[i]:"],
	"severity": ["\t\t\"INFO\":\n\t\t\treturn 9", "\t\t\"INFO\":\n\t\t\treturn 8"],
	"gaugesum": ["\tm[\"value\"] = value\n", "\tm[\"value\"] = m[\"value\"] + value\n"],
	"samesalt": ["\trng = seed if seed != 0 else 88172645463325252\n", "\trng = 1\n"],
}


func _end(line: String, code: int) -> void:
	print(line)
	quit(code)


func _build(control: String) -> Object:
	var src: String = FileAccess.get_file_as_string("res://otel.sgd")
	if control != "":
		if src.count(PLANTS[control][0]) != 1:
			return null
		src = src.replace(PLANTS[control][0], PLANTS[control][1])
	var script: Object = ClassDB.instantiate("SafeGDScript")
	script.set_source_code(src)
	if script.get_compile_error() != "":
		print("compile otel: %s" % script.get_compile_error())
		return null
	var sb: Object = ClassDB.instantiate("Sandbox")
	sb.load_buffer(script.get_content())
	return sb


func _hexlen(s: String, n: int) -> bool:
	if s.length() != n:
		return false
	for c in s:
		if not "0123456789abcdef".contains(c):
			return false
	return true


func _check(sb: Object, seed: int) -> String:
	sb.vmcallv("reset", "gate-service", "gate-scope", seed)
	var root: String = sb.vmcallv("start_span", "root", "", 2, "1000")
	var kid: String = sb.vmcallv("start_span", "child", root, 1, "1100")
	sb.vmcallv("set_attr_s", kid, "k", "v\"q\n")
	sb.vmcallv("set_attr_i", kid, "n", 7)
	sb.vmcallv("set_attr_f", kid, "x", 0.5)
	sb.vmcallv("set_attr_b", kid, "ok", true)
	sb.vmcallv("add_event", kid, "tick", "1150")
	sb.vmcallv("set_status", kid, 2, "boom")
	sb.vmcallv("end_span", kid, "1200")
	if int(sb.vmcallv("pending")) != 1:
		return "pending after one end is not 1"
	sb.vmcallv("end_span", root, "1300")
	var text: String = sb.vmcallv("drain")
	if int(sb.vmcallv("pending")) != 0 or String(sb.vmcallv("drain")) != "":
		return "drain did not empty the queue"
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return "drain is not JSON"
	var spans: Array = parsed["resourceSpans"][0]["scopeSpans"][0]["spans"]
	if spans.size() != 2:
		return "expected 2 spans"
	var by := {}
	for s in spans:
		if not _hexlen(String(s["traceId"]), 32) or not _hexlen(String(s["spanId"]), 16):
			return "id length or alphabet"
		by[s["name"]] = s
	if by["root"]["traceId"] != by["child"]["traceId"]:
		return "trace id differs"
	if by["child"].get("parentSpanId", "") != by["root"]["spanId"]:
		return "child does not name its parent"
	if by["root"].has("parentSpanId"):
		return "root has a parent"
	if by["child"]["startTimeUnixNano"] != "1100" or by["child"]["endTimeUnixNano"] != "1200":
		return "timestamps are not decimal strings of the given times"
	if int(by["child"]["status"]["code"]) != 2 or by["child"]["status"]["message"] != "boom":
		return "status"
	if by["child"]["attributes"][0]["value"]["stringValue"] != "v\"q\n":
		return "string attribute did not survive escaping"
	if by["child"]["attributes"][1]["value"]["intValue"] != "7":
		return "int attribute"
	if by["child"]["events"][0]["name"] != "tick":
		return "event"
	var more: String = _check_more(sb, seed)
	if more != "":
		return more
	var seen := {}
	sb.vmcallv("reset", "gate-service", "gate-scope", seed)
	for i in 500:
		var id: String = sb.vmcallv("start_span", "s", "", 1, "1")
		sb.vmcallv("end_span", id, "2")
		if seen.has(id):
			return "span id repeated"
		seen[id] = true
	return ""


func _check_more(sb: Object, seed: int) -> String:
	sb.vmcallv("reset", "gate-service", "gate-scope", seed)
	sb.vmcallv("counter_add", "reqs", "1", 2.0, "10")
	sb.vmcallv("counter_add", "reqs", "1", 3.0, "20")
	sb.vmcallv("gauge_set", "load", "1", 5.0, "20")
	sb.vmcallv("gauge_set", "load", "1", 4.0, "30")
	for v in [1.0, 1.5, 1000.0, 2000.0]:
		sb.vmcallv("histogram_record", "ms", "ms", v, "40")
	var m: Variant = JSON.parse_string(sb.vmcallv("drain_metrics"))
	if typeof(m) != TYPE_DICTIONARY or String(sb.vmcallv("drain_metrics")) != "":
		return "metrics drain"
	var by := {}
	for e in m["resourceMetrics"][0]["scopeMetrics"][0]["metrics"]:
		by[e["name"]] = e
	if absf(by["reqs"]["sum"]["dataPoints"][0]["asDouble"] - 5.0) > 1e-9:
		return "counter did not add"
	if not by["reqs"]["sum"]["isMonotonic"]:
		return "counter not monotonic"
	if absf(by["load"]["gauge"]["dataPoints"][0]["asDouble"] - 4.0) > 1e-9:
		return "gauge is not the last value"
	var h: Dictionary = by["ms"]["histogram"]["dataPoints"][0]
	if h["count"] != "4" or h["bucketCounts"][0] != "1" or h["bucketCounts"][1] != "1" or h["bucketCounts"][8] != "1" or h["bucketCounts"][9] != "1":
		return "histogram buckets %s" % [h["bucketCounts"]]
	sb.vmcallv("reset", "gate-service", "gate-scope", seed)
	var id: String = sb.vmcallv("start_span", "s", "", 1, "1")
	sb.vmcallv("log", "INFO", "hello", id, "5")
	sb.vmcallv("log", "ERROR", "bad", "", "6")
	var l: Variant = JSON.parse_string(sb.vmcallv("drain_logs"))
	if typeof(l) != TYPE_DICTIONARY or int(sb.vmcallv("pending_logs")) != 0:
		return "logs drain"
	var recs: Array = l["resourceLogs"][0]["scopeLogs"][0]["logRecords"]
	if int(recs[0]["severityNumber"]) != 9 or int(recs[1]["severityNumber"]) != 17:
		return "severity numbers"
	if recs[0]["spanId"] != id or not _hexlen(String(recs[0]["traceId"]), 32) or recs[1].has("spanId"):
		return "log correlation"
	return ""


func _initialize() -> void:
	var control := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--control="):
			control = a.substr(10)
	var sb: Object = _build(control)
	if sb == null:
		_end("RESULT: ERROR guest did not build", 2)
		return
	var why: String = _check(sb, 12345)
	if control == "":
		_end("RESULT: PASS" if why == "" else "RESULT: FAIL " + why, 0 if why == "" else 1)
		return
	if control == "samesalt":
		var a: Object = _build(control)
		var b: Object = _build(control)
		a.vmcallv("reset", "s", "c", 1)
		b.vmcallv("reset", "s", "c", 2)
		var ta: String = a.vmcallv("start_span", "x", "", 1, "1")
		var tb: String = b.vmcallv("start_span", "x", "", 1, "1")
		why = "different seeds gave one id" if ta == tb else ""
	_end("RESULT: FAIL the planted %s was caught: %s" % [control, why] if why != "" else "RESULT: ERROR the planted %s was not caught" % control, 1 if why != "" else 2)
