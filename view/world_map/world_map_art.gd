extends Resource
## Presentation settings only; campaigns and world generation never read these.
@export var linked_tiles := true
@export_range(0.0, 1.5) var relief_strength := 1.0
@export_range(0.01, 0.10) var border_width := 0.04
@export_range(0.0, 2.0) var foliage_density := 1.0
@export_range(0.0, 1.0) var meadow_detail_cover := 0.16
@export_range(0.0, 0.15) var shore_width := 0.055
@export_range(0.0, 1.0) var wind_scale := 0.24
@export_range(0.0, 1.0) var water_glints := 0.55
@export var river_colour := Color("398fa4")
@export var shore_colour := Color("c3b28a")
@export var earth_colour := Color("81745d")
