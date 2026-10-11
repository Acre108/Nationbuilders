class_name WaterDepthMap
extends RefCounted

## Bakes LandformTerrainProvider's lake depth and sea-bed height grids into a
## texture the water shader can sample -- the same role ZoneMap plays for
## the far-woodland tint. The CPU already knows exactly where water is (that
## is what drives the growth mask); this hands the same knowledge to the GPU,
## so the water surface's own rendering can react to it too -- starting with
## damping the wave swell in shallow water (see docs/WATER.md, *Terrain-aware
## water*), and later, as the same map, potentially shaping the water surface
## itself rather than relying on the ground to occlude a flat plane.
##
## Two channels, world units: R the depth of lake water (fixed), G the bed
## height under the sea. The shader takes the sea's depth as its live level
## minus G (docs/SEA_PLAN.md, SEA1), so a moving sea level needs no rebake;
## ImportedSea.bed_texture() fills the same layout for a real coastline.
## Image.FORMAT_RGF (32-bit float) usually filters fine on desktop
## Forward+/Vulkan; if that ever needs revisiting on older hardware, see
## docs/WATER.md.
##
## Built from a plain PackedFloat32Array via create_from_data() rather than a
## per-pixel set_pixel() loop, so there is no per-pixel GDScript call.

static func build(provider: LandformTerrainProvider) -> ImageTexture:
	var n := LandformTerrainProvider.WATER_GRID
	var lakes := provider.lake_depth_grid()
	var bed := provider.water_bed_grid()
	var texels := PackedFloat32Array()
	texels.resize(n * n * 2)
	for i in n * n:
		texels[i * 2] = lakes[i] if not lakes.is_empty() else 0.0
		texels[i * 2 + 1] = bed[i]
	var image := Image.create_from_data(n, n, false, Image.FORMAT_RGF, texels.to_byte_array())
	return ImageTexture.create_from_image(image)
