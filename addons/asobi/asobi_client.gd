class_name AsobiClient
extends Node

@export var host: String = "localhost"
@export var port: int = 8084
@export var use_ssl: bool = false

const _TOKEN_STORE_PATH := "user://asobi_auth.cfg"

var access_token: String = ""
var refresh_token: String = ""
var player_id: String = ""
var is_authenticated: bool:
	get: return access_token != ""

var http: AsobiHttp
var auth: AsobiAuth
var players: AsobiPlayers
var matchmaker: AsobiMatchmaker
var matches: AsobiMatches
var leaderboards: AsobiLeaderboards
var economy: AsobiEconomy
var inventory: AsobiInventory
var social: AsobiSocial
var tournaments: AsobiTournaments
var notifications: AsobiNotifications
var storage: AsobiStorage
var iap: AsobiIAP
var votes: AsobiVotes
var worlds: AsobiWorlds
var dm: AsobiDM
var chat: AsobiChat
var realtime: AsobiRealtime

var base_url: String:
	get:
		var scheme := "https" if use_ssl else "http"
		return "%s://%s:%d" % [scheme, host, port]

var ws_url: String:
	get:
		var scheme := "wss" if use_ssl else "ws"
		return "%s://%s:%d/ws" % [scheme, host, port]

func _ready() -> void:
	_load_refresh_token()

	http = AsobiHttp.new()
	add_child(http)

	auth = AsobiAuth.new(self)
	players = AsobiPlayers.new(self)
	matchmaker = AsobiMatchmaker.new(self)
	matches = AsobiMatches.new(self)
	leaderboards = AsobiLeaderboards.new(self)
	economy = AsobiEconomy.new(self)
	inventory = AsobiInventory.new(self)
	social = AsobiSocial.new(self)
	tournaments = AsobiTournaments.new(self)
	notifications = AsobiNotifications.new(self)
	storage = AsobiStorage.new(self)
	iap = AsobiIAP.new(self)
	votes = AsobiVotes.new(self)
	worlds = AsobiWorlds.new(self)
	dm = AsobiDM.new(self)
	chat = AsobiChat.new(self)
	realtime = AsobiRealtime.new(self)
	add_child(realtime)

func save_refresh_token() -> void:
	var config := ConfigFile.new()
	config.set_value("auth", "refresh_token", refresh_token)
	config.save(_TOKEN_STORE_PATH)

func clear_persisted_token() -> void:
	refresh_token = ""
	if FileAccess.file_exists(_TOKEN_STORE_PATH):
		DirAccess.remove_absolute(_TOKEN_STORE_PATH)

func _load_refresh_token() -> void:
	var config := ConfigFile.new()
	if config.load(_TOKEN_STORE_PATH) == OK:
		refresh_token = config.get_value("auth", "refresh_token", "")
