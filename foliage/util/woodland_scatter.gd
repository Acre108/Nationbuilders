class_name WoodlandScatter
extends RefCounted

## Forest-floor pass over the exact grove field/cover used by tree families.
## Separate salts keep trees, authored shrubs and debris bit-identical when
## this layer changes. No dependency on loaded tree chunks or worker order.
## Tree mask excludes paths, water, steep slopes and land above the treeline.
const BUSH_SALT := 0x173A421
const DEBRIS_SALT := 0x173A422


static func scatter(
	out: GroveScatter.Placement, chunk: Vector2i, world_seed: int,
	chunk_size: float, groves: FastNoiseLite, terrain: TerrainProvider,
	cover: float, density: float, spacing: float, variants: int,
	bushes: bool, rock_share: float = 0.6,
	density_at: Callable = Callable(),
	grove_at: Callable = Callable(),
) -> void:
	if cover <= 0.0 or density <= 0.0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = GrassPlacer.hash_chunk(world_seed ^ (BUSH_SALT if bushes else DEBRIS_SALT), chunk.x, chunk.y)
	var start := out.transforms.size()
	GroveScatter.scatter_family(
		out, rng, groves, terrain, chunk_size, Vector2(chunk) * chunk_size,
		spacing, cover, 0.6, 0.8, 1.25, variants, 2 if bushes else 0,
		PackedFloat32Array([1.0]) if bushes else PackedFloat32Array([rock_share, 1.0 - rock_share]),
		terrain.get_tree_mask, density, density_at, grove_at,
	)
	if not bushes:
		# Settle rocks/deadwood onto the local slope instead of floating one
		# end of a log above it. Standing bushes retain upright stems.
		for i in range(start, out.transforms.size()):
			var transform := out.transforms[i]
			var normal := terrain.get_normal(transform.origin.x, transform.origin.z)
			transform.basis = Basis(Quaternion(Vector3.UP, normal)) * transform.basis
			out.transforms[i] = transform
