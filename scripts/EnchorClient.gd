extends Node

signal search_completed(results: Array, total_found: int, page: int, error_msg: String)
signal download_progress(md5: String, downloaded_bytes: int, total_bytes: int)
signal download_completed(md5: String, sng_path: String, error_msg: String)
signal cover_loaded(art_md5: String, tex: Texture2D)

const API_SEARCH_URL := "https://api.enchor.us/search"
const FILES_BASE_URL := "https://files.enchor.us/"

var _search_http: HTTPRequest
var _dl_http: HTTPRequest
var _active_dl_md5: String = ""
var _active_dl_meta: Dictionary = {}
var _active_dl_tmp: String = ""
var _cover_cache: Dictionary = {} # art_md5 -> Texture2D
var _pending_covers: Dictionary = {}

func _ready() -> void:
	_search_http = HTTPRequest.new()
	_search_http.timeout = 20.0
	add_child(_search_http)
	_search_http.request_completed.connect(_on_search_done)

	_dl_http = HTTPRequest.new()
	_dl_http.use_threads = true
	_dl_http.timeout = 0.0
	add_child(_dl_http)
	_dl_http.request_completed.connect(_on_download_done)

func _process(_delta: float) -> void:
	if _active_dl_md5 != "":
		var st := _dl_http.get_http_client_status()
		if st == HTTPClient.STATUS_BODY or st == HTTPClient.STATUS_CONNECTED or st == HTTPClient.STATUS_REQUESTING:
			download_progress.emit(_active_dl_md5, _dl_http.get_downloaded_bytes(), _dl_http.get_body_size())

func search_charts(query: String = "*", page: int = 1, difficulty = null, per_page: int = 10) -> void:
	_search_http.cancel_request()
	var q := query.strip_edges()
	if q == "":
		q = "*"
	var payload := {
		"search": q,
		"per_page": per_page,
		"page": maxi(1, page),
		"instrument": "guitar",
		"difficulty": difficulty,
		"drumType": null,
		"drumsReviewed": false,
		"sort": null,
		"source": "bridge"
	}
	var headers := PackedStringArray([
		"Content-Type: application/json",
		"Accept: application/json",
		"User-Agent: DroidHeroV2/2.4"
	])
	var err := _search_http.request(API_SEARCH_URL, headers, HTTPClient.METHOD_POST, JSON.stringify(payload))
	if err != OK:
		search_completed.emit([], 0, page, "Network request error (" + str(err) + ")")

func _extract_enchor_diffs(item: Dictionary) -> Array[String]:
	var found := {}
	var nd = item.get("notesData", null)
	if typeof(nd) == TYPE_DICTIONARY:
		var counts = nd.get("noteCounts", [])
		if typeof(counts) == TYPE_ARRAY:
			for nc in counts:
				if typeof(nc) != TYPE_DICTIONARY:
					continue
				var inst := str(nc.get("instrument", "")).to_lower()
				if inst != "guitar" and inst != "":
					continue
				if int(nc.get("count", 0)) <= 0:
					continue
				var d := str(nc.get("difficulty", "")).to_lower()
				match d:
					"easy": found["Easy"] = true
					"medium": found["Medium"] = true
					"hard": found["Hard"] = true
					"expert": found["Expert"] = true
	var out: Array[String] = []
	for k in ["Easy", "Medium", "Hard", "Expert"]:
		if found.has(k):
			out.append(k)
	return out

func _on_search_done(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or (response_code != 200 and response_code != 201):
		search_completed.emit([], 0, 1, "enchor.us HTTP " + str(response_code) + " (check connection)")
		return
	var parsed = JSON.parse_string(body.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY:
		search_completed.emit([], 0, 1, "Invalid response from enchor.us")
		return
	var raw_list: Array = parsed.get("data", [])
	var clean_list: Array[Dictionary] = []
	for item in raw_list:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var md5 := str(item.get("md5", ""))
		if md5 == "":
			continue
		var avail_diffs := _extract_enchor_diffs(item)
		clean_list.append({
			"id": md5,
			"md5": md5,
			"albumArtMd5": str(item.get("albumArtMd5", "")),
			"name": GameState._strip_rich_tags(str(item.get("name", "Unknown Song"))),
			"artist": GameState._strip_rich_tags(str(item.get("artist", "Unknown Artist"))),
			"album": GameState._strip_rich_tags(str(item.get("album", ""))),
			"genre": GameState._strip_rich_tags(str(item.get("genre", "Rock"))),
			"year": str(item.get("year", "")),
			"charter": GameState._strip_rich_tags(str(item.get("charter", "Community"))),
			"song_length": int(item.get("song_length", 180000)),
			"diff_guitar": int(item.get("diff_guitar", 3)),
			"diff_drums": int(item.get("diff_drums", -1)),
			"available_diffs": avail_diffs,
			"hasVideoBackground": bool(item.get("hasVideoBackground", false))
		})
	search_completed.emit(clean_list, int(parsed.get("found", clean_list.size())), int(parsed.get("page", 1)), "")

func is_downloaded(md5: String) -> bool:
	return FileAccess.file_exists(GameState.SONGS_DIR + "/" + md5 + ".sng")

func download_chart(song_meta: Dictionary) -> void:
	var md5 := str(song_meta.get("md5", ""))
	if md5 == "":
		download_completed.emit("", "", "Missing chart MD5")
		return
	if _active_dl_md5 != "":
		_dl_http.cancel_request()
	_active_dl_md5 = md5
	_active_dl_meta = song_meta.duplicate(true)
	_active_dl_tmp = GameState.SONGS_DIR + "/" + md5 + ".sng.part"
	_dl_http.download_file = _active_dl_tmp
	var has_vid := bool(song_meta.get("hasVideoBackground", false))
	var suffix := "_novideo.sng" if has_vid else ".sng"
	var url := FILES_BASE_URL + md5 + suffix
	var headers := PackedStringArray(["User-Agent: DroidHeroV2/2.0"])
	var err := _dl_http.request(url, headers, HTTPClient.METHOD_GET)
	if err != OK:
		var m := _active_dl_md5
		_active_dl_md5 = ""
		download_completed.emit(m, "", "Download start error (" + str(err) + ")")

func cancel_download() -> void:
	if _active_dl_md5 != "":
		_dl_http.cancel_request()
		if FileAccess.file_exists(_active_dl_tmp):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(_active_dl_tmp))
		_active_dl_md5 = ""

func _on_download_done(result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	var md5 := _active_dl_md5
	var meta := _active_dl_meta
	var tmp := _active_dl_tmp
	_active_dl_md5 = ""

	# Fallback: if _novideo.sng returned 404, retry standard .sng
	if (response_code == 404 or result != HTTPRequest.RESULT_SUCCESS) and bool(meta.get("hasVideoBackground", false)):
		meta["hasVideoBackground"] = false
		download_chart(meta)
		return

	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		if FileAccess.file_exists(tmp):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))
		download_completed.emit(md5, "", "Download failed (HTTP " + str(response_code) + ")")
		return

	var final_path := GameState.SONGS_DIR + "/" + md5 + ".sng"
	var g_tmp := ProjectSettings.globalize_path(tmp)
	var g_final := ProjectSettings.globalize_path(final_path)
	if FileAccess.file_exists(final_path):
		DirAccess.remove_absolute(g_final)
	DirAccess.rename_absolute(g_tmp, g_final)

	# Save sidecar metadata JSON for instant library startup
	var mf := FileAccess.open(final_path + ".json", FileAccess.WRITE)
	if mf:
		mf.store_string(JSON.stringify(meta, "\t"))

	GameState.scan_library()
	download_completed.emit(md5, final_path, "")

func request_cover(art_md5: String) -> void:
	if art_md5 == "" or art_md5 == "null":
		return
	if _cover_cache.has(art_md5):
		cover_loaded.emit(art_md5, _cover_cache[art_md5])
		return
	if _pending_covers.has(art_md5):
		return
	_pending_covers[art_md5] = true
	var req := HTTPRequest.new()
	req.timeout = 12.0
	add_child(req)
	req.request_completed.connect(func(res: int, code: int, _h: PackedStringArray, b: PackedByteArray):
		_pending_covers.erase(art_md5)
		req.queue_free()
		if res == HTTPRequest.RESULT_SUCCESS and code == 200 and b.size() > 64:
			var img := Image.new()
			if img.load_jpg_from_buffer(b) == OK or img.load_png_from_buffer(b) == OK or img.load_webp_from_buffer(b) == OK:
				var tex := ImageTexture.create_from_image(img)
				if _cover_cache.size() > 60:
					_cover_cache.clear()
				_cover_cache[art_md5] = tex
				cover_loaded.emit(art_md5, tex)
	)
	req.request(FILES_BASE_URL + art_md5 + ".jpg", PackedStringArray(["User-Agent: DroidHeroV2/2.0"]))
