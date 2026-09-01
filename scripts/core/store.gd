class_name Store
extends RefCounted

## Store catalog + entitlement granting. Play Billing / StoreKit connect in M4;
## this core is deterministic and unit-testable with a mock transaction.

const PRODUCTS := [
	{"id": "coins_small",  "name": "400 Coins",           "price_cents": 99,  "coins": 400},
	{"id": "coins_medium", "name": "1,200 Coins +20%",    "price_cents": 199, "coins": 1440},
	{"id": "coins_large",  "name": "3,200 Coins +50%",    "price_cents": 399, "coins": 4800},
	{"id": "remove_ads",   "name": "Remove Ads",          "price_cents": 399, "entitlement": "remove_ads"},
	{"id": "starter",      "name": "Starter Bundle",      "price_cents": 199, "coins": 1000,
		"entitlement": "starter", "cosmetics": ["T_MIDNIGHT", "R_NEON"]},
]


static func product(id: String) -> Dictionary:
	for p in PRODUCTS:
		if p["id"] == id:
			return p.duplicate(true)
	return {}


## Grant a successfully-purchased product. Pure: returns deltas + flags.
## Idempotent: re-buying an owned entitlement is rejected.
static func grant(purchase_id: String, owned: Array, has_remove_ads: bool, has_starter: bool) -> Dictionary:
	var p := product(purchase_id)
	if p.is_empty():
		return {"ok": false}
	if p.has("entitlement"):
		var e: String = p["entitlement"]
		if (e == "remove_ads" and has_remove_ads) or (e == "starter" and has_starter):
			return {"ok": false, "already_owned": true}
	var coins := int(p.get("coins", 0))
	var cosmetics: Array = p.get("cosmetics", [])
	var new_owned := owned.duplicate()
	for c in cosmetics:
		if not new_owned.has(c):
			new_owned.append(c)
	return {
		"ok": true,
		"coins": coins,
		"owned": new_owned,
		"remove_ads": has_remove_ads or purchase_id == "remove_ads",
		"starter": has_starter or purchase_id == "starter",
	}