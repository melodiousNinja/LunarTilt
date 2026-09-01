extends SceneTree
## M2 tests: Economy settlements, cosmetic ownership/equip, Store entitlements,
## Ads pacing. Pure logic - no rendering, no device SDKs.
## Run:  godot --headless --path . --script res://tests/test_m2.gd

var _failures := 0
var _total := 0


func _initialize() -> void:
	_test_economy()
	_test_game_state()
	_test_store()
	_test_ads()
	_test_migration()
	print("M2_TEST total=%d failures=%d" % [_total, _failures])
	if _failures == 0:
		print("ALL TESTS PASSED")
		quit(0)
	else:
		printerr("M2_TEST FAILURES: %d" % _failures)
		quit(1)


func _expect(cond: bool, name: String) -> void:
	_total += 1
	if cond:
		print("  ok: " + name)
	else:
		_failures += 1
		printerr("FAIL: " + name)
		print("FAIL: " + name)


## ---------------------------------------------------------------- Economy --

func _test_economy() -> void:
	# Wager scaling: 50 * 2^league.
	var expected := [50, 100, 200, 400, 800, 1600]
	for li in range(Economy.LEAGUES.size()):
		_expect(Economy.wager_for_league(li) == expected[li],
			"wager league %d = %d" % [li, expected[li]])

	# Win pays out +wager and builds win streak.
	var r1 := Economy.settle_wager(1000, 100, true, 1, 2, 1)
	_expect(int(r1["coins"]) == 1100, "win adds wager (1100)")
	_expect(int(r1["win_streak"]) == 3 and int(r1["loss_streak"]) == 0, "win streak builds")
	_expect(bool(r1["promoted"]), "3-streak promotes")

	# Promotion only *after* 3 wins, and never at max league.
	var r2 := Economy.settle_wager(1000, 100, true, 0, 1, 0)
	_expect(not bool(r2["promoted"]), "1 win no promotion")
	var r3 := Economy.settle_wager(1000, 100, true, 5, 2, 0)
	_expect(not bool(r3["promoted"]), "no promotion past Cosmic")

	# Loss deducts wager and builds loss streak; demote at 3.
	var r4 := Economy.settle_wager(5000, 400, false, 3, 0, 2)
	_expect(int(r4["coins"]) == 4600, "loss deducts wager (4600)")
	_expect(bool(r4["demoted"]), "3-loss streak demotes")
	var r5 := Economy.settle_wager(5000, 400, false, 0, 0, 2)
	_expect(not bool(r5["demoted"]), "no demotion below Bronze")

	# Bankruptcy stipend: refill + streak reset instead of going negative.
	var r6 := Economy.settle_wager(20, 100, false, 0, 2, 1)
	_expect(int(r6["coins"]) == Economy.STIPEND_GRANT, "stipend refills to grant")
	_expect(bool(r6["stipend"]), "stipend flagged")
	_expect(int(r6["win_streak"]) == 0 and int(r6["loss_streak"]) == 0, "stipend resets streaks")

	# Buy rules: price check, double-buy rejection, free items not purchasable.
	var b1 := Economy.buy(5000, ["T_OAK", "R_LOUNGE"], "T_MIDNIGHT")
	_expect(bool(b1["ok"]) and int(b1["coins"]) == 4200, "buy midnight deducts 800")
	var b2 := Economy.buy(5000, ["T_MIDNIGHT", "T_OAK", "R_LOUNGE"], "T_MIDNIGHT")
	_expect(not bool(b2["ok"]), "cannot buy twice")
	var b3 := Economy.buy(100, ["T_OAK", "R_LOUNGE"], "T_BROADCAST")
	_expect(not bool(b3["ok"]), "cannot buy unaffordable")
	var b4 := Economy.buy(5000, ["T_OAK", "R_LOUNGE"], "T_OAK")
	_expect(not bool(b4["ok"]), "free default not buyable")
	_expect(Economy.free_default_ids().size() == 2, "two free defaults exist")


## ------------------------------------------------------------- GameState --

func _test_game_state() -> void:
	var gs := GameState.new()
	gs._path = "user://m2_test.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(gs._path))
	gs.load_save()
	gs.coins = 5000  # top up so the 800-coin purchase is affordable

	_expect(gs.owned_cosmetics.size() >= 2, "fresh player owns free defaults")
	_expect(gs.equipped_table == "T_OAK" and gs.equipped_room == "R_LOUNGE", "fresh player equips defaults")

	# Purchase through GameState persists.
	var bought := gs.purchase_cosmetic("T_MIDNIGHT")
	_expect(bought and gs.owned_cosmetics.has("T_MIDNIGHT"), "game_state purchase persists")
	_expect(gs.coins == 5000 - 800, "coins reflect purchase")
	_expect(not gs.purchase_cosmetic("T_MIDNIGHT"), "double purchase rejected")

	# Equip validation.
	_expect(gs.equip("table", "T_MIDNIGHT"), "equip owned table")
	_expect(gs.equipped_table == "T_MIDNIGHT", "equipped table updated")
	_expect(not gs.equip("table", "T_BROADCAST"), "cannot equip unowned")
	_expect(not gs.equip("bogus", "T_OAK"), "bogus kind rejected")

	# Full match settlement via record_match_result.
	var c0 := gs.coins
	var res := gs.record_match_result(true, 50)
	_expect(gs.coins == c0 + 50, "match win pays out")
	_expect(gs.total_matches == 1 and gs.total_wins == 1, "match stats increment")

	gs.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(gs._path))
## ----------------------------------------------------------------- Store --

func _test_store() -> void:
	var owned: Array = ["T_OAK", "R_LOUNGE"]

	var r := Store.grant("coins_medium", owned, false, false)
	_expect(bool(r["ok"]) and int(r["coins"]) == 1440, "medium pack grants 1440")

	var unknown := Store.grant("nope", owned, false, false)
	_expect(not bool(unknown["ok"]), "unknown product rejected")

	var ra := Store.grant("remove_ads", owned, false, false)
	_expect(bool(ra["ok"]) and bool(ra["remove_ads"]), "remove_ads entitlement granted")
	_expect(int(ra["coins"]) == 0, "remove_ads grants no coins")

	var ra2 := Store.grant("remove_ads", owned, true, false)
	_expect(not bool(ra2["ok"]) and bool(ra2.get("already_owned", false)),
		"remove_ads idempotent - cannot re-buy")

	var st := Store.grant("starter", owned, false, false)
	_expect(bool(st["ok"]) and int(st["coins"]) == 1000, "starter grants 1000 coins")
	_expect(st["owned"].has("T_MIDNIGHT") and st["owned"].has("R_NEON"), "starter grants cosmetics")
	_expect(bool(st["starter"]) and not bool(st["remove_ads"]), "starter entitlement flagged")

	var st2 := Store.grant("starter", owned, false, true)
	_expect(not bool(st2["ok"]), "starter idempotent - cannot re-buy")


## ------------------------------------------------------------------- Ads --

func _test_ads() -> void:
	var ads := AdsProvider.new()
	_expect(ads.can_show_interstitial(0), "interstitial allowed on first match")
	ads.note_interstitial_shown(0)
	_expect(not ads.can_show_interstitial(1), "blocked immediately after showing")
	_expect(ads.can_show_interstitial(2), "allowed one match later (gap=1)")
	_expect(ads.can_show_interstitial(3), "allowed two matches later")
	_expect(int(AdsProvider.apply_reward(100, AdsProvider.REWARD_DOUBLE)) == 200, "double reward")
	_expect(int(AdsProvider.apply_reward(100, AdsProvider.REWARD_STIPEND)) == 170, "stipend reward")
	_expect(int(AdsProvider.apply_reward(100, "bogus")) == 100, "unknown reward passthrough")


## ------------------------------------------------------------ Migration --

func _test_migration() -> void:
	# A save written before M2 (no cosmetics keys) must load safely.
	var path := "user://m2_legacy.cfg"
	var cfg := ConfigFile.new()
	cfg.set_value("player", "coins", 999)
	cfg.set_value("player", "league", 2)
	cfg.set_value("stats", "matches", 7)
	cfg.set_value("stats", "wins", 4)
	cfg.save(path)

	var gs := GameState.new()
	gs._path = path
	gs._ready()
	_expect(gs.coins == 999 and gs.league_index == 2, "legacy save values loaded")
	_expect(gs.owned_cosmetics.has("T_OAK") and gs.owned_cosmetics.has("R_LOUNGE"),
		"legacy save gains free cosmetics")
	_expect(gs.equipped_table == "T_OAK", "legacy save equips default table")

	gs.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
