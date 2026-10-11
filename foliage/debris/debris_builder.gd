class_name DebrisBuilder
extends RefCounted

## Procedural rock and fallen-tree/log meshes, one built per (species,
## variant) and instanced by MultiMesh -- the same "build once, cost per
## variant not per instance" shape as TreeCardBuilder. No shared "Species"
## config class here: a rock (a lumpy blob) and a log (a tapered tube) are
## different enough shapes that forcing one config through both would not
## actually save anything.
##
## Deadwood's bark colour is TreeCardBuilder's own oak/birch bark_colour,
## weathered duller and greyer, so a fallen tree reads as a fallen version of
## what is still standing nearby rather than a separately designed grey
## stick.

const ROCK_COLOUR := Color("#8b8378")
const ROCK_COLOUR_WARM := Color("#a08f72")
## Fades bark toward this before weathering: real deadwood is duller and
## greyer than a living trunk, whichever species it fell from.
const WEATHERED_GREY := Color(0.55, 0.52, 0.47)


## `variant` 0/1/2 give three sizes from the same recipe (pebble/boulder/
## outcrop), seeded so each is stable.
static func build_rock(variant: int, seed: int) -> DebrisVariant:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var mesh := DebrisMeshData.new()

	var base_radius: float = [0.28, 0.45, 0.7][clampi(variant, 0, 2)]
	var radii := Vector3(
		base_radius * rng.randf_range(0.85, 1.15),
		base_radius * rng.randf_range(0.55, 0.8),   # flatter than tall -- a rock sits, it does not stand
		base_radius * rng.randf_range(0.85, 1.15),
	)
	var bumpiness := 0.38 + float(variant) * 0.06
	var colour := ROCK_COLOUR.lerp(ROCK_COLOUR_WARM, rng.randf()).srgb_to_linear()
	# Centred half a radius up: sinks the blob's lower half into the ground,
	# so a tuft's-eye view never catches the sphere's equator as a hard,
	# unnaturally round silhouette skimming the surface.
	mesh.add_lumpy_blob(Vector3(0.0, radii.y * 0.5, 0.0), radii, 8, 5, bumpiness, seed, colour)

	var out := DebrisVariant.new()
	out.species = "rock"
	out.mesh = mesh.commit()
	out.triangles = mesh.triangle_count()
	return out


## `variant` 0/1 are logs (short, modest taper); 2 is a fallen tree (longer,
## thicker, more taper end to end -- big enough to read as a whole trunk down
## rather than a cut log someone left).
static func build_deadwood(variant: int, seed: int) -> DebrisVariant:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var mesh := DebrisMeshData.new()

	var is_fallen_tree := variant >= 2
	var length := rng.randf_range(4.0, 6.0) if is_fallen_tree else rng.randf_range(1.1, 2.0)
	var radius := rng.randf_range(0.22, 0.32) if is_fallen_tree else rng.randf_range(0.1, 0.18)
	var taper := rng.randf_range(0.45, 0.7)

	var bark_colour: Color = TreeCardBuilder.Species.birch().bark_colour if rng.randf() < 0.5 else TreeCardBuilder.Species.oak().bark_colour
	bark_colour = bark_colour.lerp(WEATHERED_GREY, 0.35).srgb_to_linear()

	# Lying along X, resting on the ground -- the tube's own radius keeps its
	# underside from clipping through. A little lean along its length reads
	# as having settled unevenly rather than lying on a perfectly flat rail.
	var lean := rng.randf_range(-0.06, 0.06)
	var from := Vector3(-length * 0.5, radius, 0.0)
	var to := Vector3(length * 0.5, radius + length * lean, 0.0)
	mesh.add_tube(from, to, radius, radius * taper, 7, bark_colour)

	var out := DebrisVariant.new()
	out.species = "deadwood"
	out.mesh = mesh.commit()
	out.triangles = mesh.triangle_count()
	return out
