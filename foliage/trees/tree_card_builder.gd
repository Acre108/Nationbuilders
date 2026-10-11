class_name TreeCardBuilder
extends RefCounted

## Procedural card-canopy trees, shrubs AND conifers: a tapered trunk, one
## branch per leaf clump, and each clump filled with cards from a sprite
## atlas. Shrubs use the exact same builder as trees -- a `Species` with a
## short height, a crown that starts almost at the ground and no upward lean
## produces a rounded bush instead of a tree, with no other code path needed.
##
## Broadleaf species (oak, birch, the two shrubs) model the canopy as a
## handful of CLUMPS scattered through a crown ellipsoid, biased outward and
## upward -- see _build_broadleaf() / _clump_centre(). Conifers (spruce, fir,
## pine; `Species.is_conifer`) instead climb a single straight leader and hang
## their clumps in tapering rings round a cone -- see _build_conic() /
## _conic_clump_centre() -- and draw from the needle atlas rather than the
## leaf atlas (TreeLayer routes this by `is_conifer`, not by style).
##
## Either way, every canopy card's normal points out of its clump (blended
## towards the crown centre), which is what makes the crown shade as a few
## soft masses instead of hundreds of flat cards. The clumps also define the
## shadow proxy: one coarse ellipsoid per clump, shrunk so the outer leaves
## stay sunlit while the crown's interior falls into shade.
##
## A tree is built once per variant and instanced by MultiMesh, so everything
## here is per-variant cost, not per-tree. Seeded, so variants are stable.

const ATLAS_TILES := 4

## One species' shape. Presets below, tuned by eye per species.
class Species extends RefCounted:
	var name: String = "oak"
	## Metres, before per-instance scale.
	var height: float = 8.0
	## Fraction of the height where the crown starts.
	var crown_base: float = 0.32
	## Crown diameter as a fraction of height.
	var crown_width: float = 0.8
	var clumps: int = 12
	## Clump radius as a fraction of crown width.
	var clump_radius: float = 0.24
	## Leaf cards per clump at canopy detail 1.0.
	var cards_per_clump: int = 14
	## Card edge length as a multiple of clump radius.
	var card_size: float = 1.15
	var trunk_radius: float = 0.22
	var bark_colour: Color = Color("#5a4232")
	## Leaf atlas tiles this species draws from (see make_leaf_sprites.py).
	var tiles: PackedInt32Array = PackedInt32Array([0, 1])
	## Shifts the palette lookup: birch leaves sit lighter than oak.
	var palette_shift: float = 0.0
	## Upward bias of clump placement: birch crowns are taller than wide.
	var lean: float = 0.25
	## True for spruce/fir/pine: the crown is a tapering cone climbed by
	## tiered clump rings (`_conic_clump_centre()`) instead of the broadleaf
	## ellipsoid cloud (`_clump_centre()`), and TreeLayer routes its canopy to
	## the needle atlas instead of the leaf atlas.
	var is_conifer: bool = false
	## Conic species only: how sharply the crown narrows towards the apex.
	## 1.0 tapers as a straight-sided cone; higher pinches to a sharper point
	## (spruce); lower keeps more width near the top (pine's blunter crown).
	var taper_power: float = 1.0
	## True for fern: TreeLayer routes its canopy to the frond atlas instead
	## of the leaf atlas. Geometry is unaffected -- a fern still builds
	## through `_build_broadleaf()` like any other low, wide, no-lean
	## species (rounded_shrub, low_hedge); only the bound sprite sheet and
	## material differ, the same way `is_conifer` only changes the atlas for
	## a species that ALSO happens to need different clump geometry.
	var is_fern: bool = false
	## True for the alpine cushion plant: routes to the cushion atlas. Like
	## fern, geometry is unaffected -- a tight round dome is exactly what
	## `_build_broadleaf()` already does for rounded_shrub, just far smaller
	## and denser, so this needs no clump-geometry change at all.
	var is_cushion: bool = false

	static func oak() -> Species:
		return Species.new()

	static func birch() -> Species:
		var s := Species.new()
		s.name = "birch"
		s.height = 10.0
		s.crown_base = 0.3
		s.crown_width = 0.45
		s.clumps = 14
		s.clump_radius = 0.34
		s.cards_per_clump = 16
		s.card_size = 1.1
		s.trunk_radius = 0.14
		s.bark_colour = Color("#d8d6cc")
		s.tiles = PackedInt32Array([2, 3])
		s.palette_shift = 0.12
		s.lean = 0.12
		return s

	## Wide and round: broad leaves, `crown_base` almost at the ground and
	## `lean` at 0 so clumps spread evenly in every direction rather than
	## biasing upward the way a tree's do. Shares the oak leaf tiles -- both
	## are broad-leaved, and the atlas has no bush-specific art.
	static func rounded_shrub() -> Species:
		var s := Species.new()
		s.name = "rounded-shrub"
		s.height = 1.3
		s.crown_base = 0.08
		s.crown_width = 1.3
		s.clumps = 9
		s.clump_radius = 0.28
		s.cards_per_clump = 11
		s.card_size = 1.2
		s.trunk_radius = 0.05
		s.bark_colour = Color("#4a3a28")
		s.tiles = PackedInt32Array([0, 1])
		s.palette_shift = -0.05
		s.lean = 0.0
		return s

	## Lower and flatter than rounded_shrub, with the small birch-style leaf
	## tiles -- reads as clipped boxwood/hedging rather than a wild bush.
	static func low_hedge() -> Species:
		var s := Species.new()
		s.name = "low-hedge"
		s.height = 0.8
		s.crown_base = 0.05
		s.crown_width = 1.6
		s.clumps = 7
		s.clump_radius = 0.3
		s.cards_per_clump = 10
		s.card_size = 1.15
		s.trunk_radius = 0.04
		s.bark_colour = Color("#3f3120")
		s.tiles = PackedInt32Array([2, 3])
		s.palette_shift = 0.03
		s.lean = 0.0
		return s

	## Narrow and sharply pointed, needled almost to the ground -- the
	## classic Christmas-tree silhouette. Draws the needle atlas' upright
	## tiles (see make_needle_sprites.py): needles pointing outward and
	## slightly up off the twig. `clumps`/`clump_radius` are tuned for
	## majority-crown coverage: see _build_conic()'s comment for why the
	## original, sparser values read as a bare pole with ornaments on it.
	## Saplings and young trees of the woodland's regrowth layer: a small
	## broadleaf crown on a thin stem (nature pack: young_tree_*, or small
	## spruce in conifer woods -- NatureAssetCatalogue.choices() slot 9).
	static func young_tree() -> Species:
		var s := Species.new()
		s.name = "young-tree"
		s.height = 4.0
		s.crown_base = 0.25
		s.crown_width = 0.55
		s.clumps = 8
		s.trunk_radius = 0.06
		s.lean = 0.15
		return s

	static func spruce() -> Species:
		var s := Species.new()
		s.name = "spruce"
		s.height = 11.0
		s.crown_base = 0.08
		s.crown_width = 0.42
		s.taper_power = 1.6
		s.clumps = 28
		s.clump_radius = 0.27
		s.cards_per_clump = 10
		s.card_size = 0.85
		s.trunk_radius = 0.16
		s.bark_colour = Color("#3c2f24")
		s.tiles = PackedInt32Array([0, 1])
		s.palette_shift = -0.05
		s.is_conifer = true
		return s

	## Broader and blunter than spruce -- less pinched towards the apex, and
	## a wider base. Shares spruce's upright needle tiles. `clumps`/
	## `clump_radius` run higher than spruce's: fir's wider, gentler-tapering
	## cone (crown_width 0.5 against spruce's 0.42, taper_power 1.15 against
	## 1.6) has more surface area to cover with the same relative density, so
	## matching spruce's absolute values left it visibly gappier side by side.
	static func fir() -> Species:
		var s := Species.new()
		s.name = "fir"
		s.height = 12.0
		s.crown_base = 0.06
		s.crown_width = 0.5
		s.taper_power = 1.15
		s.clumps = 34
		s.clump_radius = 0.35
		s.cards_per_clump = 11
		s.card_size = 0.9
		s.trunk_radius = 0.18
		s.bark_colour = Color("#4a3a2c")
		s.tiles = PackedInt32Array([0, 1])
		s.palette_shift = 0.0
		s.is_conifer = true
		return s

	## Shorter and more open than spruce/fir, with a bare lower trunk
	## (`crown_base` far higher) and a looser, flatter crown -- a young pine's
	## silhouette rather than a dense fir wall. Draws the needle atlas' loose
	## tiles: longer, more separated bundles. `crown_base` stays high on
	## purpose (the exposed lower trunk is the point), but the crown ABOVE it
	## gets the same majority-crown density fix as spruce/fir.
	static func pine() -> Species:
		var s := Species.new()
		s.name = "pine"
		s.height = 9.5
		s.crown_base = 0.35
		s.crown_width = 0.55
		s.taper_power = 0.7
		s.clumps = 17
		s.clump_radius = 0.33
		s.cards_per_clump = 9
		s.card_size = 1.0
		s.trunk_radius = 0.15
		s.bark_colour = Color("#6b4a2f")
		s.tiles = PackedInt32Array([2, 3])
		s.palette_shift = 0.06
		s.is_conifer = true
		return s

	## Forest-floor fern: low and wide, built by _build_fern() rather than the
	## broadleaf ellipsoid-crown path (`crown_base`/`lean` are unused by it,
	## left at their defaults) -- fewer, larger clumps so individual frond
	## cards stay legible instead of blending into a solid dome, and all four
	## frond atlas tiles in play (rather than splitting a pair per species,
	## one preset covers the variety).
	static func fern() -> Species:
		var s := Species.new()
		s.name = "fern"
		s.height = 0.45
		s.crown_width = 1.8
		s.clumps = 5
		s.clump_radius = 0.34
		s.cards_per_clump = 6
		s.card_size = 1.4
		s.trunk_radius = 0.015
		s.bark_colour = Color("#3a3324")
		s.tiles = PackedInt32Array([0, 1, 2, 3])
		s.palette_shift = 0.1
		s.is_fern = true
		return s

	## Alpine cushion plant (moss campion, saxifrage): a tight, dense,
	## ground-hugging hummock -- built through the ordinary
	## `_build_broadleaf()` path, the same one rounded_shrub uses, just far
	## smaller and denser so it reads as a hand-sized mound rather than a
	## bush. No lean: the dome should spread evenly, not bias upward.
	static func cushion() -> Species:
		var s := Species.new()
		s.name = "alpine-cushion"
		s.height = 0.12
		s.crown_base = 0.05
		s.crown_width = 1.1
		s.clumps = 6
		s.clump_radius = 0.4
		s.cards_per_clump = 5
		s.card_size = 1.6
		s.trunk_radius = 0.01
		s.bark_colour = Color("#4a4238")
		s.tiles = PackedInt32Array([0, 1, 2, 3])
		s.palette_shift = 0.0
		s.lean = 0.0
		s.is_cushion = true
		return s


## Builds one variant. `detail` scales cards per clump (FoliageQuality's
## tree_canopy_detail).
static func build(species: Species, seed: int, detail: float = 1.0) -> TreeVariant:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	# Conifer forests need a visibly broken crown line; a narrow 10% range
	# made every spruce/fir read as the same stamped silhouette.
	var height_range := Vector2(0.82, 1.18) if species.is_conifer else Vector2(0.9, 1.1)
	var height := species.height * rng.randf_range(height_range.x, height_range.y)
	var canopy := TreeMeshData.new(height)
	var bark := TreeMeshData.new(height)
	var proxy := TreeMeshData.new(height)
	var bark_colour := species.bark_colour.srgb_to_linear()
	var cards := maxi(3, int(round(float(species.cards_per_clump) * detail)))

	if species.is_conifer:
		_build_conic(species, rng, height, canopy, bark, proxy, bark_colour, cards)
	elif species.is_fern:
		_build_fern(species, rng, height, canopy, bark, proxy, bark_colour, cards)
	else:
		_build_broadleaf(species, rng, height, canopy, bark, proxy, bark_colour, cards)

	var variant := TreeVariant.new()
	variant.species = species.name
	variant.height = height
	variant.canopy_mesh = canopy.commit()
	variant.bark_mesh = bark.commit()
	variant.proxy_mesh = proxy.commit()
	variant.triangles = canopy.triangle_count() + bark.triangle_count()
	variant.proxy_triangles = proxy.triangle_count()
	return variant


## Oak/birch/shrub geometry: clumps scattered through an ellipsoid crown,
## biased outward and (for trees) upward -- see _clump_centre().
static func _build_broadleaf(
	species: Species, rng: RandomNumberGenerator, height: float,
	canopy: TreeMeshData, bark: TreeMeshData, proxy: TreeMeshData,
	bark_colour: Color, cards: int,
) -> void:
	var crown_base := height * species.crown_base
	var radii := Vector3(
		height * species.crown_width * 0.5 * rng.randf_range(0.9, 1.1),
		(height - crown_base) * 0.5,
		height * species.crown_width * 0.5 * rng.randf_range(0.9, 1.1),
	)
	# A slight lean of the whole crown, so variants are not all dead upright.
	var offset := Vector3(rng.randf_range(-1.0, 1.0), 0.0, rng.randf_range(-1.0, 1.0)) * radii.x * 0.12
	var crown := Vector3(offset.x, crown_base + radii.y, offset.z)
	var clump_r := height * species.crown_width * species.clump_radius

	# Trunk: up to the crown's upper third, leaning with it.
	var top := crown + Vector3(0.0, radii.y * 0.35, 0.0)
	var mid := Vector3(offset.x * 0.4, crown_base, offset.z * 0.4)
	bark.add_tube(Vector3(0.0, -0.3, 0.0), mid, species.trunk_radius, species.trunk_radius * 0.75, 8, bark_colour)
	bark.add_tube(mid, top, species.trunk_radius * 0.75, species.trunk_radius * 0.25, 7, bark_colour)
	proxy.add_tube(Vector3(0.0, -0.3, 0.0), mid, species.trunk_radius, species.trunk_radius * 0.75, 5, bark_colour)

	for c in species.clumps:
		var centre := _clump_centre(rng, crown, radii, clump_r, species.lean)
		var r := clump_r * rng.randf_range(0.8, 1.15)
		var shift := species.palette_shift + rng.randf_range(-0.06, 0.06)

		# Branch from the trunk to just short of the clump centre.
		var start := _on_trunk(clampf(centre.y - r * 1.5, crown_base * 0.85, top.y - 0.2), mid, top)
		bark.add_tube(start, start.lerp(centre, 0.8), species.trunk_radius * 0.35, species.trunk_radius * 0.12, 5, bark_colour)

		for k in cards:
			_add_card(canopy, rng, species, centre, r, crown, radii, shift)

		# Proxy clump, shrunk: the outer shell of leaves stays sunlit, the
		# crown's interior falls into its shadow.
		# 5 x 3 (30 triangles): a shadow blob needs no more, and at 6 x 4 the
		# proxy cost more triangles than the canopy it stands in for.
		proxy.add_ellipsoid(centre, Vector3.ONE * r * 0.75, 5, 3, bark_colour)


## Conifer geometry: a single straight leader climbing almost to the tip, and
## clumps arranged in tapering rings round it (`_conic_clump_centre()`)
## instead of a Gaussian cloud -- the tiered-branch cone silhouette that
## reads as "conifer" rather than "broadleaf" at a glance.
##
## Majority-crown density: an isolated in-game render of the original tuning
## (16 spruce clumps up an 11 m cone, independently randomly placed) showed
## the actual failure mode -- not the crown_base/height fraction, which was
## already ~92% crown, but that clumps sat far enough apart vertically that
## bare trunk and bare branch spokes showed through the gaps, with a bare
## multi-metre whip above the last one. Raising `clumps`/`clump_radius``
## alone (see the species presets above) helped but did not fix it outright:
## independent random placement can still roll an unlucky gap even at higher
## density, and with dozens of trees per grove an "unlikely" gap shows up
## constantly. Clumps are now grouped into evenly spaced TIERS instead (see
## below), which makes a gap wider than one tier's band structurally
## impossible rather than merely improbable -- and happens to be the more
## botanically accurate shape too: a real conifer's whorls form roughly one
## per year of growth, at fairly even intervals, not at random heights.
static func _build_conic(
	species: Species, rng: RandomNumberGenerator, height: float,
	canopy: TreeMeshData, bark: TreeMeshData, proxy: TreeMeshData,
	bark_colour: Color, cards: int,
) -> void:
	var crown_base_y := height * species.crown_base
	var apex_y := height * 0.97
	var base_radius := height * species.crown_width * 0.5
	var mid := Vector3(0.0, lerp(crown_base_y, apex_y, 0.4), 0.0)
	var top := Vector3(0.0, apex_y, 0.0)
	bark.add_tube(Vector3(0.0, -0.3, 0.0), mid, species.trunk_radius, species.trunk_radius * 0.7, 8, bark_colour)
	bark.add_tube(mid, top, species.trunk_radius * 0.7, species.trunk_radius * 0.15, 7, bark_colour)
	proxy.add_tube(Vector3(0.0, -0.3, 0.0), mid, species.trunk_radius, species.trunk_radius * 0.7, 5, bark_colour)

	# A bounding ellipsoid purely for _add_card()'s shading maths (interior
	# darkening, outward-normal blend) -- clump placement itself follows the
	# cone below, not this shape.
	var crown := Vector3(0.0, (crown_base_y + apex_y) * 0.5, 0.0)
	var radii := Vector3(base_radius, (apex_y - crown_base_y) * 0.5, base_radius)
	var clump_r := base_radius * species.clump_radius

	# Tiers: roughly one whorl per 2-3 clumps, each whorl at a fixed height
	# fraction (jittered within its own band, so it does not look perfectly
	# robotic) rather than an independent random draw. `base_per_tier` is
	# guaranteed >= 1 (tier_count is clamped to at most `clumps`), so every
	# tier gets at least one clump -- no tier can be empty. The remainder is
	# handed to the LOWEST tiers first, which keeps the "more branch mass low
	# down" look the original per-clump height bias was going for, just
	# expressed as tier density instead of tier position.
	var tier_count := clampi(int(round(float(species.clumps) / 2.5)), 5, species.clumps)
	var base_per_tier := species.clumps / tier_count
	var extra_tiers := species.clumps - base_per_tier * tier_count
	for tier in tier_count:
		var tier_clumps := base_per_tier + (1 if tier < extra_tiers else 0)
		var tier_fraction := (float(tier) + 0.5) / float(tier_count)
		for c in tier_clumps:
			var jitter := rng.randf_range(-0.4, 0.4) / float(tier_count)
			var height_fraction := clampf(tier_fraction + jitter, 0.0, 0.97)
			var placement := _conic_clump_centre(rng, crown_base_y, apex_y, base_radius, species.taper_power, height_fraction)
			var centre: Vector3 = placement[0]
			var radius_here: float = placement[1]
			# Clamped to the cone's own local width (plus a splay allowance):
			# without an upper bound an enlarged clump balloons past the
			# cone's silhouette where it is already narrow, near the apex.
			# The floor matters more than it looks: a sharply tapering
			# species (spruce's taper_power 1.6) shrinks radius_here fast, so
			# too tight a floor here starves exactly the tiers that most need
			# to bridge to their neighbours -- that gap showed clearly in an
			# isolated render before the floor was loosened to 0.55.
			var r := clampf(clump_r * rng.randf_range(0.85, 1.2), clump_r * 0.55, radius_here + clump_r * 1.1)
			var shift := species.palette_shift + rng.randf_range(-0.06, 0.06)

			var start := _on_trunk(clampf(centre.y - r * 1.2, crown_base_y * 0.9, top.y - 0.1), mid, top)
			# Carry the branch almost into the outer clump, then seed a
			# bigger inner spray near its origin. This removes the long
			# bare spokes that dominated close Black Forest views without
			# filling the whole cone -- the inner spray needs to be generous
			# enough to bury the trunk/branch join itself, not just soften it,
			# for the "continuous needle coverage" look a real, well-shaded
			# conifer has (no visible woody structure at all bar a hint at
			# the very base).
			bark.add_tube(start, start.lerp(centre, 0.96), species.trunk_radius * 0.3, species.trunk_radius * 0.08, 5, bark_colour)
			var inner := start.lerp(centre, 0.5)
			for k in maxi(3, cards / 3):
				_add_card(canopy, rng, species, inner, r * 0.8, crown, radii, shift)

			for k in cards:
				_add_card(canopy, rng, species, centre, r, crown, radii, shift)

			proxy.add_ellipsoid(centre, Vector3.ONE * r * 0.7, 5, 3, bark_colour)

	# Guaranteed leader tuft: the last tier already reaches close to the
	# apex, but a real leader tapers to a short whip, not a bare pole, so
	# this places one small tuft right at the tip unconditionally rather
	# than trusting the last tier's jitter to land close enough every time.
	var tip_placement := _conic_clump_centre(
		rng, crown_base_y, apex_y, base_radius, species.taper_power, rng.randf_range(0.96, 0.99),
	)
	var tip_centre: Vector3 = tip_placement[0]
	var tip_radius_here: float = tip_placement[1]
	var tip_r := clampf(clump_r * 0.6, clump_r * 0.45, tip_radius_here + clump_r * 0.6)
	var tip_shift := species.palette_shift + rng.randf_range(-0.06, 0.06)
	var tip_start := _on_trunk(clampf(tip_centre.y - tip_r * 1.2, crown_base_y * 0.9, top.y - 0.05), mid, top)
	bark.add_tube(tip_start, tip_start.lerp(tip_centre, 0.9), species.trunk_radius * 0.2, species.trunk_radius * 0.08, 4, bark_colour)
	for k in maxi(3, cards / 2):
		_add_card(canopy, rng, species, tip_centre, tip_r, crown, radii, tip_shift)
	proxy.add_ellipsoid(tip_centre, Vector3.ONE * tip_r * 0.7, 4, 3, bark_colour)


## Fern geometry: no meaningful trunk, and clumps sampled directly in a LOW
## band across a flat disc (not biased through an ellipsoid crown, the way
## _clump_centre()'s `lean` does for broadleaf species) -- that bias is too
## weak to pull a crown's centre of mass down to the ground convincingly
## (tried first; still read as a sapling on a stick), where placing the
## clumps' own y coordinate directly in a low range is not.
static func _build_fern(
	species: Species, rng: RandomNumberGenerator, height: float,
	canopy: TreeMeshData, bark: TreeMeshData, proxy: TreeMeshData,
	bark_colour: Color, cards: int,
) -> void:
	var base_radius := height * species.crown_width * 0.5
	var clump_r := base_radius * species.clump_radius
	var top := Vector3(0.0, height * 0.15, 0.0)
	bark.add_tube(Vector3(0.0, -0.1, 0.0), top, species.trunk_radius, species.trunk_radius * 0.6, 5, bark_colour)
	proxy.add_tube(Vector3(0.0, -0.1, 0.0), top, species.trunk_radius, species.trunk_radius * 0.6, 4, bark_colour)

	# A bounding ellipsoid purely for _add_card()'s shading maths, as in
	# _build_conic() -- clump placement itself ignores it.
	var crown := Vector3(0.0, height * 0.4, 0.0)
	var radii := Vector3(base_radius, height * 0.5, base_radius)

	for c in species.clumps:
		var theta := rng.randf() * TAU
		var horiz := base_radius * sqrt(rng.randf()) * rng.randf_range(0.5, 1.0)
		var y := height * rng.randf_range(0.05, 0.4)
		var centre := Vector3(cos(theta) * horiz, y, sin(theta) * horiz)
		var r := clump_r * rng.randf_range(0.85, 1.2)
		var shift := species.palette_shift + rng.randf_range(-0.06, 0.06)

		for k in cards:
			_add_card(canopy, rng, species, centre, r, crown, radii, shift)

		proxy.add_ellipsoid(centre, Vector3.ONE * r * 0.65, 5, 3, bark_colour)


## The point at height `y` on the two-segment trunk root -> mid -> top.
static func _on_trunk(y: float, mid: Vector3, top: Vector3) -> Vector3:
	if y <= mid.y:
		return Vector3.ZERO.lerp(mid, clampf(y / maxf(mid.y, 0.01), 0.0, 1.0))
	return mid.lerp(top, clampf((y - mid.y) / maxf(top.y - mid.y, 0.01), 0.0, 1.0))


## A clump position inside the crown ellipsoid, biased outwards (leaves live on
## the outside of a crown) and upwards by `lean`, kept far enough inside that
## the clump's leaves reach the crown surface but not far past it.
static func _clump_centre(rng: RandomNumberGenerator, crown: Vector3, radii: Vector3, clump_r: float, lean: float) -> Vector3:
	var dir := Vector3(rng.randfn(), rng.randfn() + lean, rng.randfn()).normalized()
	var reach := pow(rng.randf(), 0.35)
	var inset := Vector3(
		maxf(radii.x - clump_r * 0.6, radii.x * 0.3),
		maxf(radii.y - clump_r * 0.6, radii.y * 0.3),
		maxf(radii.z - clump_r * 0.6, radii.z * 0.3),
	)
	return crown + dir * inset * reach


## A clump position on the cone's tapering surface at a given `height_fraction`
## (0 = crown_base_y, 1 = apex_y -- the caller decides the distribution, see
## _build_conic()'s tiers): the radius at that height follows `taper_power`,
## and the clump sits near the cone's outer skin rather than its axis -- the
## tiered-branch rings that tell a conifer apart from a broadleaf's rounded
## cloud.
##
## Returns `[position, radius_here]`: the local cone radius at that height is
## handed back too, so a caller can clamp how big a clump is allowed to be at
## that height -- without it, a large clump near the narrow apex balloons
## past the cone's own silhouette.
##
## `reach` (how far from the trunk axis, as a fraction of `radius_here`, the
## clump CENTRE sits) is deliberately pulled well in from the true skin, not
## out near 1.0: a clump's own radius already reaches the skin from further
## in (see _build_conic()'s widened `r` ceiling), and a distant clump centre
## is what forces its connecting branch to stretch far from the trunk to
## reach it. On a gently-tapering, wide-based species (fir's taper_power
## 1.15, pine's 0.7) that stretch was long enough to read as a stray
## detached arm rather than a bough -- caught by rendering fir in isolation,
## not visible in-grove where neighbours hide it, but wrong regardless of
## whether it shows.
static func _conic_clump_centre(
	rng: RandomNumberGenerator, base_y: float, apex_y: float, base_radius: float, taper_power: float,
	height_fraction: float,
) -> Array:
	var y: float = lerp(base_y, apex_y, height_fraction)
	var radius_here := base_radius * pow(1.0 - height_fraction, taper_power)
	var reach := rng.randf_range(0.35, 0.65)
	var theta := rng.randf() * TAU
	var position := Vector3(cos(theta) * radius_here * reach, y, sin(theta) * radius_here * reach)
	return [position, radius_here]


static func _add_card(
	mesh: TreeMeshData, rng: RandomNumberGenerator, species: Species,
	clump: Vector3, r: float, crown: Vector3, radii: Vector3, shift: float,
) -> void:
	var centre := clump + Vector3(rng.randfn(), rng.randfn(), rng.randfn()).normalized() * r * sqrt(rng.randf()) * 0.6
	var facing := Vector3(rng.randfn(), rng.randfn(), rng.randfn()).normalized()
	var u := facing.cross(Vector3.UP if absf(facing.y) < 0.9 else Vector3.RIGHT).normalized()
	var v := facing.cross(u).normalized()
	var spin := rng.randf() * TAU
	var axis_u := (u * cos(spin) + v * sin(spin))
	var axis_v := (v * cos(spin) - u * sin(spin))
	var half := r * species.card_size * 0.5 * rng.randf_range(0.85, 1.15)

	var tile := species.tiles[rng.randi() % species.tiles.size()]
	var tile_origin := Vector2(float(tile % 2), float(tile / 2)) * 0.5

	var ids := PackedInt32Array()
	for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var p: Vector3 = centre + axis_u * corner.x * half + axis_v * corner.y * half
		# The clump normal: out of this clump, pulled 40% towards "out of the
		# crown" so neighbouring clumps blend into one rounded canopy rather
		# than reading as separate balls.
		var from_clump := (p - clump).normalized()
		var from_crown := (p - crown).normalized()
		var normal := (from_clump * 0.6 + from_crown * 0.4).normalized()
		var depth := ((p - crown) / radii).length()
		var colour := Color(clampf(1.0 - depth, 0.0, 1.0), 1.0, clampf(shift + 0.5, 0.0, 1.0), 1.0)
		var uv := tile_origin + (Vector2(corner.x, -corner.y) * 0.5 + Vector2(0.5, 0.5)) * 0.5
		ids.push_back(mesh.add_vertex(p, normal, colour, uv))
	# The leaf material is double sided; winding only needs to be consistent.
	mesh.add_triangle(ids[0], ids[1], ids[2])
	mesh.add_triangle(ids[0], ids[2], ids[3])
