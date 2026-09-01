class_name AdsProvider
extends RefCounted

## AdMob abstraction. The real SDK binds in M4; this class owns the business
## rules (reward types, interstitial pacing) so they are testable headless.

const REWARD_DOUBLE := "double_winnings"
const REWARD_STIPEND := "stipend_bonus"
const INTERSTITIAL_GAP_MATCHES := 1

var _last_interstitial_match := -100


func can_show_interstitial(match_index: int) -> bool:
	return match_index - _last_interstitial_match > INTERSTITIAL_GAP_MATCHES


func note_interstitial_shown(match_index: int) -> void:
	_last_interstitial_match = match_index


## Rewarded-ad rewards inflate a payout deterministically. Pure static math.
static func apply_reward(payout: int, reward_id: String) -> int:
	match reward_id:
		REWARD_DOUBLE:
			return payout * 2
		REWARD_STIPEND:
			return payout + 50 + payout / 5
		_:
			return payout