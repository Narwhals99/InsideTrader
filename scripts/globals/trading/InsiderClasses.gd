extends Resource

class_name InsiderClasses

const DEFAULTS := {
	"exec_assistant": {
		"display_name": "Executive Assistant",
		"confidence": 0.45,
		"tip_accuracy": 0.55,
		"tip_move_size": 0.03,
		"drunk_threshold": 2,
		"max_drunk": 4,
		"interaction_prompt": "What do you need?",
		"dialogue_need_beer": "You show up empty-handed?",
		"dialogue_tip_refusal": "Bring me %d more drink(s).",
		"dialogue_pass_out": "They slump over the bar, completely out.",
		"dialogue_passed_out_tip": "...",
		"dialogue_passed_out_give": "Can't drink anymore...",
		"debug_logging": true
	},
	"accountant": {
		"display_name": "Accountant",
		"confidence": 0.6,
		"tip_accuracy": 0.75,
		"tip_move_size": 0.045,
		"drunk_threshold": 2,
		"max_drunk": 5,
		"interaction_prompt": "Numbers talk. What about you?",
		"dialogue_need_beer": "Balance sheet says you're short a drink.",
		"dialogue_tip_refusal": "Come back after %d more drink(s).",
		"dialogue_pass_out": "They groan and collapse onto the counter.",
		"dialogue_passed_out_tip": "...spreadsheets...",
		"dialogue_passed_out_give": "No more...",
		"debug_logging": true
	},
	"journalist": {
		"display_name": "Journalist",
		"confidence": 0.55,
		"tip_accuracy": 0.65,
		"tip_move_size": 0.04,
		"drunk_threshold": 3,
		"max_drunk": 5,
		"interaction_prompt": "Got a scoop or a drink?",
		"dialogue_need_beer": "No drink, no story.",
		"dialogue_tip_refusal": "Give me %d more and maybe I'll talk.",
		"dialogue_pass_out": "They face-plant onto the nearest table.",
		"dialogue_passed_out_tip": "...breaking news...",
		"dialogue_passed_out_give": "Ugh... no, I'm done...",
		"debug_logging": true
	},
	"trading_bro": {
		"display_name": "Trading Bro",
		"confidence": 0.5,
		"tip_accuracy": 0.6,
		"tip_move_size": 0.05,
		"drunk_threshold": 3,
		"max_drunk": 6,
		"interaction_prompt": "Bro! What's the move?",
		"dialogue_need_beer": "Dude, where's the drink?",
		"dialogue_tip_refusal": "Need %d more shots first, bro.",
		"dialogue_pass_out": "They tip backwards off the stool, totally KO'd.",
		"dialogue_passed_out_tip": "bro... zzz...",
		"dialogue_passed_out_give": "Can't... feel... face...",
		"debug_logging": true
	},
	"ceo": {
		"display_name": "CEO",
		"confidence": 0.85,
		"tip_accuracy": 0.9,
		"tip_move_size": 0.08,
		"drunk_threshold": 1,
		"max_drunk": 3,
		"interaction_prompt": "You'd better have something good.",
		"dialogue_need_beer": "You dare approach without tribute?",
		"dialogue_tip_refusal": "Bring %d more high-end drinks.",
		"dialogue_pass_out": "The CEO slumps in the chair, out cold.",
		"dialogue_passed_out_tip": "...quarterly...",
		"dialogue_passed_out_give": "Enough. I'm done.",
		"debug_logging": true
	}
}

static func get_class_ids() -> PackedStringArray:
	return PackedStringArray(DEFAULTS.keys())

static func get_config(class_id: StringName) -> Dictionary:
	var key := String(class_id).to_lower()
	if DEFAULTS.has(key):
		return DEFAULTS[key].duplicate(true)
	return DEFAULTS.get("exec_assistant", {}).duplicate(true)