class_name FoliageFamily
extends RefCounted

## Describes one placeable species family -- trees, shrubs, conifers, fir,
## ferns, cushion plants -- as data, so TreeLayer and an importer can both
## read the SAME list instead of keeping their own copy in sync by hand.
## This is the fix for a bug pattern that already happened once: fern was
## added as a species (TreePlacer, TreeCardBuilder, TreeLayer) but never
## taught to tools/geo/make_location_profile.gd's old COVER_BY_GROUP, so no
## imported real-world location got ferns unless someone remembered to
## hand-patch OVERRIDES afterward (see docs/GEO_IMPORT.md).
##
## Fir was originally a third share of the conifer family
## (`conifer_fir_share`, alongside spruce and pine) rather than its own
## registry entry. Split out 2026-09-20 at the user's request, to make fir
## independently coverable -- a pure fir stand, or fir beside a broadleaf
## wood, without dragging spruce/pine along. This is exactly the kind of
## change this registry was built to make cheap: TreeLayer and the importer
## both picked up the new family from one new `_make()` entry below, with no
## change needed anywhere else that reads the registry.
##
## The split surfaced a real gotcha worth remembering for the next one:
## `cover` is a THRESHOLD on the shared grove noise field (see
## GroveScatter.scatter_family()), not an additive tree count. Splitting one
## family's `cover` into two smaller covers for the two new families does
## NOT reproduce the same combined footprint -- it shrinks the boundary of
## where anything grows at all, since a lower cover raises the threshold
## every family's grid is tested against. A newly independent family's
## `cover` should start as its own fresh, independently-chosen value (a
## reasonable guess at "how much of the world gets this on top of whatever
## else is already there"), while the family it split FROM keeps its
## original `cover` unchanged -- it still governs the same extent it always
## did, just with one fewer species sharing its grid. Getting this backwards
## (halving both) was caught by a visibly patchier, smaller treeline in an
## actual render, not by reasoning about it in the abstract.
##
## Placement itself (grove noise, growth-mask floor, seed salt, scatter mode)
## stays in TreePlacer/GroveScatter -- that is real per-family BEHAVIOUR, not
## a fact about what exists, and does not belong here. What lives here is
## exactly the two things that were drifting: which Species presets a family
## builds (TreeLayer._build_variants(), replacing a hand-written literal
## array) and what a real-world import should guess for it per Koppen climate
## group (make_location_profile.gd, replacing COVER_BY_GROUP).
##
## FoliageProfile's own fields stay individually named @export vars -- a
## location is still hand-tuned in the inspector, not through this registry.
## Adding a family still means giving it cover/spacing/share fields on
## FoliageProfile and a placement block in TreePlacer; this only removes the
## duplicate species list and the duplicate per-climate guess table.

var key: StringName
## Species presets, in TreePlacer's fixed positional order for this family.
## TreePlacer's species indices are positional across ALL families
## concatenated in registry order -- see all_species() and TreePlacer's own
## class comment, which documents the resulting index ranges (0-1 trees,
## 2-3 shrubs, 4-5 conifers, 6 fir, 7 fern, 8 cushion) as the source of truth
## to keep in sync with this file's order if a family is ever added or
## reordered.
var species: Array[TreeCardBuilder.Species] = []
var cover_field: StringName
var spacing_field: StringName
## Extra fields an importer may set alongside cover/spacing for this family --
## typically a species-split share (one for a two-way split). Empty for a
## single-species family.
var share_fields: Array[StringName] = []
## Per Koppen leading-letter group (A/B/C/D/E, the same grouping
## FoliageProfile.palette_for_koppen() uses): {"cover": float, "spacing":
## float, <share_field>: float, ...}. A key a group's dictionary omits is left
## at FoliageProfile's own default; a group missing entirely defaults this
## family's cover to 0 for that climate. One plausible guess per group, not a
## fit for any specific place -- see make_location_profile.gd's OVERRIDES for
## per-location corrections.
var group_defaults: Dictionary = {}


static func _make(
	p_key: StringName, p_species: Array[TreeCardBuilder.Species],
	p_cover_field: StringName, p_spacing_field: StringName,
	p_share_fields: Array[StringName], p_group_defaults: Dictionary,
) -> FoliageFamily:
	var f := FoliageFamily.new()
	f.key = p_key
	f.species = p_species
	f.cover_field = p_cover_field
	f.spacing_field = p_spacing_field
	f.share_fields = p_share_fields
	f.group_defaults = p_group_defaults
	return f


## The registry. A static func, not a const: building Species presets calls
## TreeCardBuilder.Species's own static factories, which is not a constant
## expression in GDScript -- the same reason FoliageProfile.gd's palette_*()
## helpers are static funcs rather than consts.
static func all() -> Array[FoliageFamily]:
	return [
		_make(&"tree", [TreeCardBuilder.Species.oak(), TreeCardBuilder.Species.birch()],
			&"tree_cover", &"tree_spacing", [&"tree_oak_share"], {
				"A": {"cover": 0.6}, "B": {"cover": 0.05}, "C": {"cover": 0.4},
				"D": {"cover": 0.0}, "E": {"cover": 0.0},
			}),
		_make(&"shrub", [TreeCardBuilder.Species.rounded_shrub(), TreeCardBuilder.Species.low_hedge()],
			&"shrub_cover", &"shrub_spacing", [&"shrub_share"], {
				"A": {"cover": 0.35}, "B": {"cover": 0.15}, "C": {"cover": 0.3},
				"D": {"cover": 0.2}, "E": {"cover": 0.0},
			}),
		# Continental climates correlate with conifer forest more than open
		# meadow (the same reasoning FoliageProfile.palette_for_koppen() gives
		# for "D" -- see its comment); every other group leaves this at 0
		# rather than placing spruce in a tropical or dry-field location.
		# Fir used to be a third share of this family (conifer_fir_share);
		# it is now its own family below -- see this file's class comment.
		# `cover` stays at the SAME value fir's removal left behind, not a
		# reduced "spruce+pine share" of it: `cover` gates a threshold on the
		# shared grove noise field, not a tree count, so it still governs the
		# same "how much of the world is coniferous forest" extent it always
		# did -- shrinking it to fir's absence would also shrink that
		# boundary, not just fir's slice of it (caught by a visibly patchier,
		# smaller treeline in a render after getting this wrong the first
		# time -- see FoliageFamily's class comment).
		_make(&"conifer", [TreeCardBuilder.Species.spruce(), TreeCardBuilder.Species.pine()],
			&"conifer_cover", &"conifer_spacing", [&"conifer_spruce_share"], {
				"D": {"cover": 0.5},
			}),
		# Independent of the conifer family above on purpose: a location can
		# mix fir with spruce/pine, run a pure fir stand, or skip it entirely.
		# Same ecological tolerance as conifer (FIR_MIN_MASK in TreePlacer),
		# same needle atlas and conifer_palette -- only its cover/spacing are
		# separate. Default split from the family's old internal share
		# (0.35 of the combined cover) is preserved here as its own guess.
		_make(&"fir", [TreeCardBuilder.Species.fir()],
			&"fir_cover", &"fir_spacing", [], {
				"D": {"cover": 0.18},
			}),
		# Forest-floor undergrowth: a modest default wherever there is a
		# broadleaf or conifer canopy to grow beneath, 0 in open climates.
		_make(&"fern", [TreeCardBuilder.Species.fern()],
			&"fern_cover", &"fern_spacing", [], {
				"C": {"cover": 0.15}, "D": {"cover": 0.2},
			}),
		# Tundra/alpine only: unlike conifer_cover this needs no altitude-
		# gating caveat -- a cushion plant is characteristic of exactly the
		# open, treeless ground an ET/EF crop already is (see docs/FOLIAGE.md,
		# "Cushion plants").
		_make(&"cushion", [TreeCardBuilder.Species.cushion()],
			&"cushion_cover", &"cushion_spacing", [], {
				"E": {"cover": 0.3},
			}),
		# Woodland regrowth: saplings and young trees inside woods, on the
		# same woodland field as the canopy (TreePlacer, `regrowth_cover` is
		# a density there, not its own grove extent). Gives woods an age
		# structure instead of one storey of equal adults.
		_make(&"regrowth", [TreeCardBuilder.Species.young_tree()],
			&"regrowth_cover", &"regrowth_spacing", [], {
				"C": {"cover": 0.3}, "D": {"cover": 0.3},
			}),
	]


## Every family's species, concatenated in registry order -- this order IS
## TreePlacer's positional species-index contract (0=oak, 1=birch, ...).
static func all_species() -> Array[TreeCardBuilder.Species]:
	var out: Array[TreeCardBuilder.Species] = []
	for family in all():
		out.append_array(family.species)
	return out
