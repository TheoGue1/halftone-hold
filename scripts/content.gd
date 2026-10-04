class_name Content
extends RefCounted
## Static data for the side systems: seasons, weather, omens, relics, scratch cards, crusade map, oaths, court.

const SEASON_LENGTH := 150.0
# `sector` indexes PassiveTree.SECTORS: that sector's non-keystone nodes are empowered during the season.
const SEASONS := [
	{"name": "Spring", "sector": 0, "particles": "blossom", "tint": Color(0.92, 1.0, 0.9)},
	{"name": "Summer", "sector": 5, "particles": "", "tint": Color(1.0, 0.97, 0.85)},
	{"name": "Autumn", "sector": 2, "particles": "leaves", "tint": Color(1.0, 0.88, 0.75)},
	{"name": "Winter", "sector": 3, "particles": "snow", "tint": Color(0.88, 0.93, 1.0)},
]
const WEATHER := [
	{"name": "Clear", "sector": -1, "particles": ""},
	{"name": "Storm", "sector": 4, "particles": "rain"},
	{"name": "Heatwave", "sector": 1, "particles": ""},
]
const SEASON_ADD_MULT := 1.5  # additive node values ×1.5
const SEASON_MUL_POW := 1.25  # multiplicative node values ^1.25

const OMEN_MIN_DELAY := 60.0
const OMEN_MAX_DELAY := 150.0
const OMEN_LIFETIME := 12.0
const OMENS := {
	"cart": {"name": "Golden Cart", "desc": "Tribute! A cartload of gold."},
	"star": {"name": "Falling Star", "desc": "×7 gold for 30 seconds.", "buff": 30.0},
	"dragon": {"name": "Dragon Raid", "desc": "Every levy is a critical, ×3 harder, for 15 seconds.", "buff": 15.0},
	"pilgrim": {"name": "Pilgrim", "desc": "Brings a free reliquary card."},
}
const STAR_MULT := 7.0
const DRAGON_CRIT_MULT := 3.0

const RARITIES := [
	{"name": "Common", "weight": 60.0, "color": Color(0.35, 0.3, 0.25)},
	{"name": "Rare", "weight": 28.0, "color": Color(0.2, 0.38, 0.72)},
	{"name": "Epic", "weight": 10.0, "color": Color(0.45, 0.2, 0.6)},
	{"name": "Legendary", "weight": 2.0, "color": Color(0.8, 0.5, 0.05)},
]
const RELIC_MAX_LEVEL := 5
const RELICS := [
	{"name": "Worn Horseshoe", "rarity": 0, "mods": {"click": 0.5}},
	{"name": "Tithe Box", "rarity": 0, "mods": {"gold": 0.25}},
	{"name": "Miller's Charm", "rarity": 0, "mods": {"xb2": 1.5}},
	{"name": "Peasant's Rosary", "rarity": 0, "mods": {"xb0": 2.0}},
	{"name": "Ledger Quill", "rarity": 0, "mods": {"cost": 0.1}},
	{"name": "Smith's Sigil", "rarity": 1, "mods": {"xb3": 2.0, "xb6": 1.5}},
	{"name": "Merchant's Seal", "rarity": 1, "mods": {"xb4": 2.0, "xb7": 1.5}},
	{"name": "Monk's Psalter", "rarity": 1, "mods": {"xrenown": 1.15}},
	{"name": "Hourglass Shard", "rarity": 1, "mods": {"offline": 0.5}},
	{"name": "Falcon Hood", "rarity": 1, "mods": {"crit": 0.05, "critx": 2.0}},
	{"name": "Dragon Scale", "rarity": 2, "mods": {"xb9": 3.0}},
	{"name": "Astrolabe of Ur", "rarity": 2, "mods": {"xb8": 2.5, "xb11": 2.5}},
	{"name": "Bishop's Crozier", "rarity": 2, "mods": {"xb10": 3.0, "xb5": 2.0}},
	{"name": "Royal Signet", "rarity": 2, "mods": {"xgold": 1.5}},
	{"name": "Holy Grail", "rarity": 3, "mods": {"xrenown": 1.4}},
	{"name": "Crown of the First King", "rarity": 3, "mods": {"xgold": 2.5, "xclick": 2.0}},
	{"name": "Excalibur", "rarity": 3, "mods": {"xclick": 5.0, "crit": 0.1}},
]
const BASE_RELIC_SLOTS := 3
const SLOT_DYNASTIES := [2, 8, 20]  # one extra slot at each of these dynasty counts

const CARD_CELLS := 9
const CARD_SECONDS := 60.0  # a card costs this many seconds of income
const CARD_MIN_COST := 25.0
const SYMBOLS := ["coin", "crown", "chalice", "relic", "skull"]
const SYMBOL_WEIGHTS := [22.0, 8.0, 12.0, 14.0, 44.0]

const DESTINATIONS := [
	{"id": "holy", "name": "The Holy Land", "renown": 1.0, "spoils": {}, "need_renown": 0.0, "need_dyn": 0,
		"desc": "The faithful road. Full Renown.", "pos": Vector2(0.78, 0.62)},
	{"id": "north", "name": "The Northern Wilds", "renown": 0.7, "spoils": {"xgold": 4.0}, "need_renown": 100.0,
		"need_dyn": 0, "desc": "×0.7 Renown. Plundered silver: next run earns ×4 gold.", "pos": Vector2(0.42, 0.14)},
	{"id": "peaks", "name": "The Dragon Peaks", "renown": 0.5, "spoils": {}, "need_renown": 0.0, "need_dyn": 4,
		"desc": "×0.5 Renown. Slay a wyrm: a guaranteed Rare-or-better relic.", "pos": Vector2(0.86, 0.22)},
	{"id": "silk", "name": "The Silk Road", "renown": 1.5, "spoils": {"xcost": 3.0}, "need_renown": 0.0,
		"need_dyn": 7, "desc": "×1.5 Renown. Exotic debts: next run's holdings cost ×3.", "pos": Vector2(0.62, 0.86)},
]

const OATH_MAX := 6
const OATH_POINTS := 2  # permanent web points per completion
const OATH_GOLD := 1.5  # permanent gold multiplier per completion
const OATHS := [
	{"id": "poverty", "name": "Oath of Poverty", "desc": "Peasants, Farmsteads and Watermills produce nothing.",
		"mods": {"xb0": 0.0, "xb1": 0.0, "xb2": 0.0}},
	{"id": "silence", "name": "Oath of Silence", "desc": "Levies, by hand or by reeve, yield nothing.",
		"mods": {"xclick": 0.0}},
	{"id": "humility", "name": "Oath of Humility", "desc": "The Passive Web is sealed for the run.", "mods": {}},
	{"id": "haste", "name": "Oath of Want", "desc": "All gold income ×0.1.", "mods": {"xgold": 0.1}},
]

const ADVISORS := [
	{"id": "steward", "name": "The Steward", "deeds": 15, "desc": "Buys the most efficient holding every second."},
	{"id": "marshal", "name": "The Marshal", "deeds": 25,
		"desc": "Leads you to the Holy Land whenever a crusade would double your Renown."},
	{"id": "falconer", "name": "The Falconer", "deeds": 33, "desc": "Catches every omen the moment it appears."},
	{"id": "abbot", "name": "The Abbot", "deeds": 40,
		"desc": "Buys and scratches a reliquary card whenever you hold 20× its cost."},
	{"id": "regent", "name": "The Regent", "deeds": 47,
		"desc": "Founds a new dynasty whenever it would at least double your Royal Blood."},
]

# Features reveal themselves in this order as the realm grows. Conditions live in Game.unlock_ready().
const UNLOCKS := [
	{"id": "buy10", "name": "Bulk orders", "desc": "Buy holdings ten at a time."},
	{"id": "omens", "name": "Omens", "desc": "Strange sights cross the sky. Click them for rewards."},
	{"id": "crusade", "name": "Crusades", "desc": "Trade this run's gold for Renown, which multiplies all gold."},
	{"id": "web", "name": "The Passive Web", "desc": "Spend points from Renown on 714 passive nodes."},
	{"id": "buymax", "name": "Royal purchasing", "desc": "Buy ×100 or as many as you can afford."},
	{"id": "hold", "name": "Iron grip", "desc": "Hold the mouse on the seal to levy repeatedly."},
	{"id": "relics", "name": "The Reliquary", "desc": "Scratch cards for gold and relics."},
	{"id": "map", "name": "The crusade map", "desc": "Choose where to crusade; new roads open as you grow."},
	{"id": "court", "name": "The Royal Court", "desc": "Advisors who automate your realm join as you earn deeds."},
	{"id": "repeat", "name": "Standing orders", "desc": "Repeat your last crusade in one click."},
	{"id": "dynasty", "name": "Dynasties", "desc": "Trade Renown and the Web for Royal Blood."},
	{"id": "reveal", "name": "Reveal all", "desc": "Uncover a whole reliquary card at once."},
	{"id": "seasons", "name": "Seasons & weather", "desc": "Each season empowers one sector of the Web."},
	{"id": "slot1", "name": "A fourth relic slot", "desc": "Equip one more relic."},
	{"id": "table", "name": "The Counting Table", "desc": "Slide coins together to mint finer ones. Your best coin multiplies all gold."},
	{"id": "presets", "name": "Web layouts", "desc": "Save two Web builds and swap them with the seasons."},
	{"id": "peaks", "name": "The Dragon Peaks", "desc": "A new crusade road: guaranteed rare relics."},
	{"id": "oaths", "name": "Oaths", "desc": "Swear a restriction on a run for permanent rewards."},
	{"id": "chapel", "name": "The Chapel", "desc": "Slide the shards of a stained-glass window back into place."},
	{"id": "silk", "name": "The Silk Road", "desc": "A new crusade road: ×1.5 Renown, costly spoils."},
	{"id": "slot2", "name": "A fifth relic slot", "desc": "Equip one more relic."},
	{"id": "window2", "name": "A second window", "desc": "Another shattered window waits in the Chapel."},
	{"id": "window3", "name": "A third window", "desc": "Another shattered window waits in the Chapel."},
	{"id": "ledger", "name": "The Royal Ledger", "desc": "Offline earnings last 3 days and gain +25% efficiency."},
	{"id": "window4", "name": "A fourth window", "desc": "Another shattered window waits in the Chapel."},
	{"id": "window5", "name": "A fifth window", "desc": "Another shattered window waits in the Chapel."},
	{"id": "window6", "name": "The great rose window", "desc": "The last and largest window waits in the Chapel."},
	{"id": "slot3", "name": "A sixth relic slot", "desc": "Equip one more relic."},
]
const HOLD_LEVY_RATE := 8.0  # levies per second while holding the seal
