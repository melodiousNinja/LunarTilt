class_name Economy
extends RefCounted

## Pure economy + cosmetics logic for Lunar Tilt. No IO, no scene deps, so
## every rule here is unit-testable headless. GameState persists results.

const START_COINS := 500
const STIPEND_MIN := 50
const STIPEND_GRANT := 500
const PROMOTE_STREAK := 3
const DEMOTE_STREAK := 3
const LEAGUES := ["Bronze", "Silver", "Gold", "Platinum", "Diamond", "Cosmic"]

## Cosmetic catalog (stable string ids so saves survive renames/reorders).
const COSMETICS := [
	{"id": "T_OAK",       "kind": "table", "name": "Classic Oak",      "price": 0},
	{"id": "T_MIDNIGHT",  "kind": "table", "name": "Midnight Club",    "price": 800},
	{"id": "T_BROADCAST", "kind": "table", "name": "Broadcast Studio", "price": 1200},
	{"id": "R_LOUNGE",    "kind": "room",  "name": "Warm Lounge",      "price": 0},
	{"id": "R_NEON",      "kind": "room",  "name": "Club Neon",        "price": 600},
	{"id": "R_STADIUM",   "kind": "room",  "name": "Open Stadium",     "price": 1000},
]


## Bankroll-friendly wagers that scale with league.
static func wager_for_league(league_index: int) -> int:
	return 50 * int(pow(2, clampi(league_index, 0, LEAGUES.size() - 1)))


## Settle a wager. Pure math: returns deltas, never mutates state.
static func settle_wager(coins: int, wager: int, won: bool, league_index: int,
		win_streak: int, loss_streak: int) -> Dictionary:
	var next := coins + (wager if won else -wager)
	var ws := (win_streak + 1) if won else 0
	var ls := 0 if won else (loss_streak + 1)
	var stipend := false
	if not won and next < STIPEND_MIN:
		next = STIPEND_GRANT
		stipend = true
		ws = 0
		ls = 0
	var li := clampi(league_index, 0, LEAGUES.size() - 1)
	return {
		"coins": next,
		"promoted": won and ws >= PROMOTE_STREAK and li < LEAGUES.size() - 1,
		"demoted": not won and ls >= DEMOTE_STREAK and li > 0,
		"win_streak": ws,
		"loss_streak": ls,
		"stipend": stipend,
	}


static func catalog() -> Array:
	return COSMETICS.duplicate(true)


static func cosmetic(id: String) -> Dictionary:
	for c in COSMETICS:
		if c["id"] == id:
			return c.duplicate()
	return {}


static func free_default_ids() -> Array:
	var out := []
	for c in COSMETICS:
		if int(c["price"]) == 0:
			out.append(c["id"])
	return out


## Attempt to buy a cosmetic. Pure: returns {ok, coins}. Caller owns state.
static func buy(coins: int, owned: Array, id: String) -> Dictionary:
	var c := cosmetic(id)
	if c.is_empty() or int(c["price"]) <= 0:
		return {"ok": false, "coins": coins}
	if owned.has(id):
		return {"ok": false, "coins": coins}
	if coins < int(c["price"]):
		return {"ok": false, "coins": coins}
	return {"ok": true, "coins": coins - int(c["price"])}