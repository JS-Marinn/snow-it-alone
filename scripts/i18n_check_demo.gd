extends Node

# --i18n-check: exercises translation integrity, key coverage, and pseudo-locale expansion.
#
# Headless-safe (Gpu = $false). Reports:
# [I18N] RESULT: N OK / M FAIL

const CSV_PATH: String = "res://locale/strings.csv"
const InputBindingsScript = preload("res://scripts/input_bindings.gd")

var _ok: int = 0
var _fail: int = 0

func _ready() -> void:
	print("[I18N] ==== TRANSLATION & LOCALIZATION CHECK ====")
	_run_checks()
	print("[I18N] RESULT: %d OK / %d FAIL" % [_ok, _fail])
	get_tree().create_timer(0.2).timeout.connect(get_tree().quit)

func _check(label: String, ok: bool) -> void:
	print("[I18N] %s %s" % ["[OK] " if ok else "[FAIL]", label])
	if ok:
		_ok += 1
	else:
		_fail += 1

func _run_checks() -> void:
	# 1. Parse strings.csv
	if not FileAccess.file_exists(CSV_PATH):
		_check("strings.csv exists at " + CSV_PATH, false)
		return

	var file := FileAccess.open(CSV_PATH, FileAccess.READ)
	if file == null:
		_check("strings.csv can be opened", false)
		return

	var header := file.get_csv_line()
	var expected_cols := header.size()
	_check("CSV header has keys and en columns", expected_cols >= 2 and header[0] == "keys" and header[1] == "en")

	var col_en_xa := -1
	for c in range(header.size()):
		if header[c] == "en_XA":
			col_en_xa = c
			break
	_check("CSV header contains en_XA pseudo-locale", col_en_xa >= 0)

	var csv_keys: Array[String] = []
	var csv_data: Dictionary = {} # key -> Dictionary of col_name -> text
	var duplicate_keys: Array[String] = []
	var malformed_rows: Array[int] = []
	var empty_en_keys: Array[String] = []
	var line_idx := 1

	while not file.eof_reached():
		var row := file.get_csv_line()
		line_idx += 1
		if row.is_empty() or (row.size() == 1 and row[0].strip_edges() == ""):
			continue
		if row.size() != expected_cols:
			malformed_rows.append(line_idx)
			continue
		var key := row[0].strip_edges()
		if key == "":
			continue
		if csv_data.has(key):
			duplicate_keys.append(key)
		csv_keys.append(key)
		var entry: Dictionary = {}
		for c in range(row.size()):
			entry[header[c]] = row[c]
		csv_data[key] = entry
		if entry.get("en", "").strip_edges() == "":
			empty_en_keys.append(key)

	file.close()

	_check("CSV has rows (%d keys loaded)" % csv_keys.size(), csv_keys.size() > 0)
	_check("no malformed rows with unequal column count", malformed_rows.is_empty())
	if not malformed_rows.is_empty():
		print("[I18N] Malformed rows at lines: %s" % str(malformed_rows))
	_check("no duplicate keys in CSV", duplicate_keys.is_empty())
	if not duplicate_keys.is_empty():
		print("[I18N] Duplicate keys: %s" % str(duplicate_keys))
	_check("no empty English entries", empty_en_keys.is_empty())
	if not empty_en_keys.is_empty():
		print("[I18N] Empty English keys: %s" % str(empty_en_keys))

	# 2. Collect script contents and keys used in code
	var scripts_dir := "res://scripts"
	var dir := DirAccess.open(scripts_dir)
	var gd_files: Array[String] = []
	var script_texts: Dictionary = {} # file_path -> text
	var all_script_text := ""

	if dir != null:
		dir.list_dir_begin()
		var file_name := dir.get_next()
		while file_name != "":
			if not dir.current_is_dir() and file_name.ends_with(".gd"):
				var path := scripts_dir + "/" + file_name
				gd_files.append(path)
				var text := FileAccess.get_file_as_string(path)
				script_texts[path] = text
				all_script_text += "\n" + text
			file_name = dir.get_next()
		dir.list_dir_end()

	# Also search scenes/ for script strings if needed, but scripts/ is primary
	var tr_regex := RegEx.new()
	tr_regex.compile('tr\\(\\s*["\']([A-Za-z0-9_]+)["\']\\s*\\)')

	var code_keys: Dictionary = {} # key -> Array of locations
	for path in gd_files:
		var text: String = script_texts[path]
		for m in tr_regex.search_all(text):
			var k: String = m.get_string(1)
			if not code_keys.has(k):
				code_keys[k] = []
			code_keys[k].append(path)

	# Dynamic keys from InputBindingsScript
	for action in InputBindingsScript.ACTIONS:
		var act_key := "ACTION_" + action.to_upper()
		if not code_keys.has(act_key):
			code_keys[act_key] = ["res://scripts/input_bindings.gd (dynamic)"]

	# Check 1: Every key used in code exists in the CSV English column
	var missing_in_csv: Array[String] = []
	for k in code_keys.keys():
		if not csv_data.has(k):
			missing_in_csv.append(k)

	_check("every key used in code exists in strings.csv (%d code keys found)" % code_keys.size(), missing_in_csv.is_empty())
	if not missing_in_csv.is_empty():
		print("[I18N] Code keys missing from strings.csv: %s" % str(missing_in_csv))

	# Check 2: No dead keys in CSV (every key is referenced in scripts)
	var dead_keys: Array[String] = []
	for k in csv_keys:
		if code_keys.has(k):
			continue
		# Also check if verbatim string appears in script text (e.g. constant or helper argument)
		if all_script_text.contains('"' + k + '"') or all_script_text.contains("'" + k + "'"):
			continue
		dead_keys.append(k)

	_check("no dead keys in CSV (%d checked)" % csv_keys.size(), dead_keys.is_empty())
	if not dead_keys.is_empty():
		print("[I18N] Dead keys found in CSV: %s" % str(dead_keys))

	# Check 4: Language columns match English (report table, inform only, do not fail)
	print("[I18N] ---- LANGUAGE COVERAGE TABLE ----")
	for c in range(2, header.size()):
		var lang_code := header[c]
		var missing_count := 0
		for k in csv_keys:
			var val: String = csv_data[k].get(lang_code, "")
			if val.strip_edges() == "":
				missing_count += 1
		print("[I18N] Language %-10s : %d / %d translated (missing: %d)" % [
			lang_code, csv_keys.size() - missing_count, csv_keys.size(), missing_count])
	_check("language column comparison completed for %d languages" % max(header.size() - 2, 0), true)

	# Check 5: Heuristic scan for literal .text = "..." > 12 chars not using tr (warn only)
	var text_literal_regex := RegEx.new()
	text_literal_regex.compile('\\.text\\s*=\\s*"([^"\\n]{13,})"')
	var warn_count := 0
	for path in gd_files:
		var text: String = script_texts[path]
		var lines := text.split("\n")
		for i in range(lines.size()):
			var line := lines[i]
			if line.strip_edges().begins_with("#"):
				continue
			var m := text_literal_regex.search(line)
			if m != null:
				var lit: String = m.get_string(1)
				# Ignore diagnostic lines or formatted lines
				if not lit.begins_with("[") and not line.contains("tr("):
					warn_count += 1
					print("[I18N] [WARN] possible unextracted text at %s:%d: %s" % [path.get_file(), i + 1, lit])
	print("[I18N] Unextracted string heuristic scan found %d warnings (non-fatal)" % warn_count)
	_check("unextracted text heuristic scan completed", true)

	# Check 6: Pseudo-locale is complete and every entry is longer than English
	var pseudo_missing: Array[String] = []
	var pseudo_not_longer: Array[String] = []
	if col_en_xa >= 0:
		for k in csv_keys:
			var en_val: String = csv_data[k].get("en", "")
			var xa_val: String = csv_data[k].get("en_XA", "")
			if xa_val.strip_edges() == "":
				pseudo_missing.append(k)
			elif xa_val.length() <= en_val.length():
				pseudo_not_longer.append(k)

	var pseudo_ok := pseudo_missing.is_empty() and pseudo_not_longer.is_empty()
	_check("pseudo-locale en_XA is complete and expanded (> len(en)) for all %d keys" % csv_keys.size(), pseudo_ok)
	if not pseudo_missing.is_empty():
		print("[I18N] Pseudo-locale missing keys: %s" % str(pseudo_missing))
	if not pseudo_not_longer.is_empty():
		print("[I18N] Pseudo-locale not expanded for keys: %s" % str(pseudo_not_longer))

	# Check 7: Font resource and glyph coverage for Latin, Cyrillic, Greek, Japanese, and Korean
	var font: Font = load("res://fonts/default_font.tres")
	_check("default_font.tres loaded successfully", font != null)
	if font != null:
		var test_scripts: Dictionary = {
			"Latin & Pseudo-locale": "Éñglïsh Psêudô [SNÖW ÏT TÖGÊTHÊR~~~~~] äöüßç",
			"Cyrillic": "Русский язык",
			"Greek": "Ελληνικά",
			"Japanese (ja)": "日本語 雪かき 新しいゲーム スノー",
			"Korean (ko)": "한국어 눈 치우기 새 게임",
		}
		for script_name in test_scripts.keys():
			var sample: String = test_scripts[script_name]
			var missing_chars: Array[String] = []
			for idx in range(sample.length()):
				var ch := sample[idx]
				if ch == " " or ch == "[" or ch == "]" or ch == "~":
					continue
				if not font.has_char(ch.unicode_at(0)):
					missing_chars.append(ch)
			var has_all := missing_chars.is_empty()
			_check("font covers %s without tofu (tested %d chars)" % [script_name, sample.length()], has_all)
			if not has_all:
				print("[I18N] Missing glyphs for %s: %s" % [script_name, str(missing_chars)])
