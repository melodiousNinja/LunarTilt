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
var win_streak: int = 0
var loss_streak: int = 0

# Cosmetic ownership + equipped presets (persisted).
var owned_cosmetics: Array = []
var equipped_table: String = "T_OAK"
var equipped_room: String = "R_LOUNGE"

var _path := "user://save.cfg"


func _ready() -> void:
	load_save()
	_ensure_cosmetic_defaults()


func league() -> String:
	return LEAGUES[league_index]


func wager_for_league() -> int:
	# Bankroll-friendly wagers that scale with league.
	return 50 * int(pow(2, league_index))


func load_save() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(_path) != OK:
		_ensure_cosmetic_defaults()
		return
	coins = int(cfg.get_value("player", "coins", START_COINS))
	league_index = clampi(int(cfg.get_value("player", "league", 0)), 0, LEAGUES.size() - 1)
	total_matches = int(cfg.get_value("stats", "matches", 0))
	total_wins = int(cfg.get_value("stats", "wins", 0))
	win_streak = int(cfg.get_value("stats", "win_streak", 0))
	loss_streak = int(cfg.get_value("stats", "loss_streak", 0))
	owned_cosmetics = cfg.get_value("cosmetics", "owned", [])
	equipped_table = cfg.get_value("cosmetics", "equipped_table", "T_OAK")
	equipped_room = cfg.get_value("cosmetics", "equipped_room", "R_LOUNGE")
	_ensure_cosmetic_defaults()


func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("player", "coins", coins)
	cfg.set_value("player", "league", league_index)
	cfg.set_value("stats", "matches", total_matches)
	cfg.set_value("stats", "wins", total_wins)
	cfg.set_value("stats", "win_streak", win_streak)
	cfg.set_value("stats", "loss_streak", loss_streak)
	cfg.set_value("cosmetics", "owned", owned_cosmetics)
	cfg.set_value("cosmetics", "equipped_table", equipped_table)
	cfg.set_value("cosmetics", "equipped_room", equipped_room)
	cfg.save(_path)


func record_match(win: bool) -> void:
	record_match_result(win, Economy.wager_for_league(league_index))


## Full settlement: runs the wager through Economy, updates streak + league,
## persists. Returns the settlement dict (see Economy.settle_wager).
func record_match_result(win: bool, wager: int) -> Dictionary:
	total_matches += 1
	if win:
		total_wins += 1
	var res := Economy.settle_wager(coins, wager, win, league_index, win_streak, loss_streak)
	coins = maxi(int(res["coins"]), 0)
	win_streak = int(res["win_streak"])
	loss_streak = int(res["loss_streak"])
	if bool(res["promoted"]):
		league_index += 1
	if bool(res["demoted"]):
		league_index = maxi(league_index - 1, 0)
	save()
	return res


func can_afford(wager: int) -> bool:
	return coins >= wager


## Buy a cosmetic (pure rule via Economy); persists on success.
func purchase_cosmetic(id: String) -> bool:
	var res := Economy.buy(coins, owned_cosmetics, id)
	if not bool(res["ok"]):
		return false
	coins = maxi(int(res["coins"]), 0)
	owned_cosmetics.append(id)
	save()
	return true


## Equip an owned cosmetic for its kind (table|room).
func equip(kind: String, id: String) -> bool:
	if not owned_cosmetics.has(id):
		return false
	match kind:
		"table":
			equipped_table = id
		"room":
			equipped_room = id
		_:
			return false
	save()
	return true


## Make sure free cosmetics are always owned and equipped ids are valid.
func _ensure_cosmetic_defaults() -> void:
	for id in Economy.free_default_ids():
		if not owned_cosmetics.has(id):
			owned_cosmetics.append(id)
	if Economy.cosmetic(equipped_table).is_empty() or not owned_cosmetics.has(equipped_table):
		equipped_table = "T_OAK"
	if Economy.cosmetic(equipped_room).is_empty() or not owned_cosmetics.has(equipped_room):
		equipped_room = "R_LOUNGE"


## Null-object config (used by tests): in-memory only, never touches disk.
static func memory_only() -> GameState:
	var gs := GameState.new()
	gs._path = "res://tests/.memory_only.cfg"  # never actually written
	return gs