class_name GameState
extends Node

## Persistent player state: coin wallet, league, cosmetics.
## Godot autoload singleton ("Game"). Saved with ConfigFile so it survives
## across runs and is trivially testable.

signal coins_changed(balance: int)
signal league_changed(league: String)

const LEAGUES := ["Bronze", "Silver", "Gold", "Platinum", "Diamond", "Cosmic"]
const START_COINS := 500

var coins: int = START_COINS:
	set(value):
		coins = maxi(value, 0)
		coins_changed.emit(coins)
		save()

var league_index: int = 0:
	set(value):
		league_index = clampi(value, 0, LEAGUES.size() - 1)
		league_changed.emit(LEAGUES[league_index])
		save()

var total_matches: int = 0
var total_wins: int = 0

var _path := "user://save.cfg"


func _ready() -> void:
	load_save()


func league() -> String:
	return LEAGUES[league_index]


func wager_for_league() -> int:
	# Bankroll-friendly wagers that scale with league.
	return 50 * int(pow(2, league_index))


func load_save() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(_path) != OK:
		return
	coins = int(cfg.get_value("player", "coins", START_COINS))
	league_index = clampi(int(cfg.get_value("player", "league", 0)), 0, LEAGUES.size() - 1)
	total_matches = int(cfg.get_value("stats", "matches", 0))
	total_wins = int(cfg.get_value("stats", "wins", 0))


func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("player", "coins", coins)
	cfg.set_value("player", "league", league_index)
	cfg.set_value("stats", "matches", total_matches)
	cfg.set_value("stats", "wins", total_wins)
	cfg.save(_path)


func record_match(win: bool) -> void:
	total_matches += 1
	if win:
		total_wins += 1
	save()


## Null-object config (used by tests): in-memory only, never touches disk.
static func memory_only() -> GameState:
	var gs := GameState.new()
	gs._path = "res://tests/.memory_only.cfg"  # never actually written
	return gs