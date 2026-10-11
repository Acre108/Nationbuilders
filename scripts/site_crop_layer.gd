class_name SiteCropLayer
extends Node3D

## Field crops streamed from the site's fields mask (tools/geo/crops.py), for
## every mapped or WorldCover field, not just authored records. Which crop a
## field grows is import data (observed OSM tag, inferred regional rotation or
## reviewed override); how it looks today -- bare, green, flowering, ripe,
## stubble -- follows `day_of_year` through CropCatalogue.
##
## Near plants: deterministic rows within `_radius`. Mid distance: a raised
## row canopy for tall crops out to CANOPY_RADIUS. Beyond that, the terrain
## shader's field surface alone. Roads, buildings and woodland are already
## cleared in the site mask's farmland channel; headlands in the fields mask.
##
## Both are placed on WorkerThreadPool through ChunkStreamer, nearest first,
## and committed within its main-thread budget: a near cell can hold thousands
## of stalks, and placing them on the main thread stalled flight over fields.
var terrain: HeightmapTerrainProvider
var focus: Node3D
var quality_level: FoliageQuality.Level = FoliageQuality.Level.HIGH
var day_of_year: float = 196.0
var plant_count := 0
var field_count := 0
var canopy_cells := 0
var _site: ImportedSite
var _looks := {}
var _plant_meshes := {}
var _chunks := {}
var _canopies := {}
var _plants: ChunkStreamer
var _canopy: ChunkStreamer
var _last_focus := Vector2(INF,INF)
var _radius := 90.0
var _last_aerial := false
var _canopy_material: ShaderMaterial
const CELL := 24.0
const CANOPY_CELL := 48.0
const CANOPY_STEP := 3.0
const CANOPY_RADIUS := 450.0
## Crops shorter than this read fine as the terrain's field surface.
const CANOPY_MIN_HEIGHT := 0.5
## Plants stand only where the site mask is fully farmland.
const FARMLAND_MIN := 0.99
## Plant models are built at 1 m; MaizeMesh is authored at a 2 m reference.
const NATIVE_HEIGHT := {"maize": 2.0}

func _ready() -> void:
	_site=terrain.imported_site
	field_count=_site.data.get("fields",[]).size()
	_radius=60.0 if quality_level==FoliageQuality.Level.LOW else 90.0
	_canopy_material=ShaderMaterial.new()
	_canopy_material.shader=load("res://foliage/shaders/crop_canopy.gdshader")
	_canopy_material.set_shader_parameter("near_radius",_radius)
	_plants=ChunkStreamer.new()
	_plants.commit=_commit_chunk
	_plants.release=_release_chunk
	_canopy=ChunkStreamer.new()
	_canopy.commit=_commit_canopy
	_canopy.release=_release_canopy
	_refresh_looks()
	_refresh_jobs()
	update_focus()

func _process(_delta: float) -> void:
	update_focus()
	# Distant fields never instantiate stalks.
	_plants.update()
	_canopy.update()

func _exit_tree() -> void:
	# Waits for in-flight placement so no worker outlives the layer.
	if _plants!=null: _plants.clear()
	if _canopy!=null: _canopy.clear()

## Appearance per crop id for the current day, and the plant models' colours.
func _refresh_looks() -> void:
	_looks.clear()
	var day:=_site.crop_day(day_of_year)
	for id in CropCatalogue.MAX_CROPS:
		if not CropCatalogue.crop(id).is_empty(): _looks[id]=CropCatalogue.appearance(id,day)
	for id in _plant_meshes:
		_tint(_plant_meshes[id],id)

func set_day_of_year(day: float) -> void:
	day_of_year=day
	_refresh_looks()
	_refresh_jobs()
	update_focus()

## A fresh placement snapshot (looks, density) for both streamers. Live cells
## stay up until their rebuilt replacements commit.
func _refresh_jobs() -> void:
	var entries: Dictionary={}
	for id in _looks: entries[id]=CropCatalogue.crop(id)
	for canopy in [false,true]:
		var job:=Job.new()
		job.canopy=canopy
		job.terrain=terrain
		job.site=_site
		job.looks=_looks.duplicate(true)
		job.entries=entries.duplicate(true)
		job.stride=2 if quality_level==FoliageQuality.Level.LOW else 1
		var streamer:=_canopy if canopy else _plants
		streamer.job=job
		streamer.invalidate()
	_last_focus=Vector2(INF,INF)

## Sculpted ground changed (Location Studio S5): re-place every live cell on
## the new heights, keeping the old ones up until their replacements commit.
func terrain_changed() -> void:
	_refresh_jobs()
	update_focus()

func update_focus() -> void:
	if focus==null: return
	var current:=Vector2(focus.global_position.x,focus.global_position.z)
	var aerial:=focus.global_position.y-terrain.get_height(current.x,current.y)>=100
	if current.distance_squared_to(_last_focus)<CELL*CELL*.25 and aerial==_last_aerial: return
	_last_focus=current
	_last_aerial=aerial
	var centre:=Vector3(current.x,0.0,current.y)
	# Overhead audit views use the row canopy, not tens of thousands of stalks.
	var near: Array=[{},[]] if aerial else ChunkStreamer.disc(centre,CELL,_radius)
	_plants.set_wanted(near[0],near[1])
	var far:=ChunkStreamer.disc(centre,CANOPY_CELL,CANOPY_RADIUS)
	_canopy.set_wanted(far[0],far[1])

func flush() -> void:
	update_focus()
	_plants.flush()
	_canopy.flush()

func set_quality(value: FoliageQuality.Level) -> void:
	if value==quality_level: return
	quality_level=value
	_radius=60.0 if value==FoliageQuality.Level.LOW else 90.0
	_canopy_material.set_shader_parameter("near_radius",_radius)
	for chunk: Node3D in _chunks.values():
		for instance: MultiMeshInstance3D in chunk.get_children(): instance.visibility_range_end=_radius+CELL
	_refresh_jobs()
	update_focus()

## True where a plant of field `index` may stand: inside its planted (headland
## inset) area and on fully farmed ground.
func plantable(point: Vector2, index: int) -> bool:
	return Job.plantable_on(_site,point,index)

## MAIN THREAD. One near cell's plants, already placed and packed by Job.
func _commit_chunk(cell: Vector2i, _variant: int, result: Dictionary) -> void:
	_release_chunk(cell)
	if result.is_empty(): return
	var chunk:=Node3D.new()
	chunk.name="Crops_%d_%d"%[cell.x,cell.y]
	var count:=0
	for crop_id in result:
		var transforms: Array=result[crop_id][0]
		var mm:=MultiMesh.new()
		mm.transform_format=MultiMesh.TRANSFORM_3D
		mm.mesh=_plant_mesh(crop_id)
		mm.instance_count=transforms.size()
		mm.buffer=result[crop_id][1]
		var instance:=MultiMeshInstance3D.new()
		instance.name=String(CropCatalogue.crop(crop_id).name)
		instance.multimesh=mm
		# CPU authoring record also supports headless checks: the dummy renderer
		# does not retain MultiMesh instance buffers for readback.
		instance.set_meta("plant_transforms",transforms)
		instance.set_meta("crop_id",crop_id)
		instance.visibility_range_end=_radius+CELL
		chunk.add_child(instance)
		count+=transforms.size()
	chunk.set_meta("plant_count",count)
	add_child(chunk)
	_chunks[cell]=chunk
	plant_count+=count

func _release_chunk(cell: Vector2i) -> void:
	var chunk: Node3D=_chunks.get(cell)
	if chunk==null: return
	plant_count-=int(chunk.get_meta("plant_count"))
	_chunks.erase(cell)
	chunk.queue_free()

## The plant model for a crop, coloured for the current day. One per crop id.
func _plant_mesh(crop_id: int) -> Mesh:
	if _plant_meshes.has(crop_id): return _plant_meshes[crop_id]
	var plant:=String(CropCatalogue.crop(crop_id).plant)
	var mesh: Mesh
	if plant=="maize":
		mesh=MaizeMesh.get_mesh().duplicate()
		mesh.surface_set_material(0,MaizeMesh.get_mesh().surface_get_material(0).duplicate())
	else:
		mesh=NatureMeshBuilder.build(plant,1.0,FoliageProfile.new())
	_plant_meshes[crop_id]=mesh
	_tint(mesh,crop_id)
	return mesh

func _tint(mesh: Mesh, crop_id: int) -> void:
	var look: Dictionary=_looks.get(crop_id,{})
	if look.is_empty(): return
	var plant: Color=look.plant
	var tint:=Color(plant.r,plant.g,plant.b,float(look.recolour))
	for s in mesh.get_surface_count():
		var material:=mesh.surface_get_material(s) as ShaderMaterial
		if material==null: continue
		if material.shader==NatureMeshBuilder.SHADER:
			# Leaves and ears only; stems and branches keep their texture.
			if float(material.get_shader_parameter("nature_alpha_cut"))>0.0:
				material.set_shader_parameter("nature_recolour",tint)
		else:
			material.set_shader_parameter("crop_tint",tint)

## MAIN THREAD. One CANOPY_CELL's canopy surface, built by Job.
func _commit_canopy(cell: Vector2i, _variant: int, arrays: Array) -> void:
	_release_canopy(cell)
	if arrays.is_empty(): return
	var mesh:=ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var instance:=MeshInstance3D.new()
	instance.name="Canopy_%d_%d"%[cell.x,cell.y]
	instance.mesh=mesh
	instance.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.material_override=_canopy_material
	add_child(instance)
	_canopies[cell]=instance
	canopy_cells+=1

func _release_canopy(cell: Vector2i) -> void:
	var canopy: Node3D=_canopies.get(cell)
	if canopy==null: return
	_canopies.erase(cell)
	canopy.queue_free()
	canopy_cells-=1

## WORKER THREAD placement for one cell: pure data over a snapshot of the
## looks and catalogue entries; terrain and site masks are only read.
class Job extends RefCounted:
	var canopy: bool
	var terrain: HeightmapTerrainProvider
	var site: ImportedSite
	var looks: Dictionary
	var entries: Dictionary
	var stride: int

	func run(cell: Vector2i, _variant: int) -> Variant:
		return _canopy_arrays(cell) if canopy else _plants(cell)

	static func plantable_on(on: ImportedSite, point: Vector2, index: int) -> bool:
		return on.field_at(point.x,point.y).x==index and on.farmland(point.x,point.y)>=SiteCropLayer.FARMLAND_MIN

	## crop id -> [world transforms, packed MultiMesh buffer].
	func _plants(cell: Vector2i) -> Dictionary:
		var rect:=Rect2(Vector2(cell)*SiteCropLayer.CELL,Vector2.ONE*SiteCropLayer.CELL)
		# Fields present in this cell: sample at about the mask's texel spacing.
		var fields: Dictionary={}
		var step:=site.field_texel_metres()
		var x:=rect.position.x+step*.5
		while x<rect.end.x:
			var z:=rect.position.y+step*.5
			while z<rect.end.y:
				var texel:=site.field_at(x,z)
				if texel.x>0: fields[texel.x]=texel
				z+=step
			x+=step
		var transforms_by_crop: Dictionary={}
		for index in fields:
			var texel: Vector3i=fields[index]
			var look: Dictionary=looks.get(texel.y,{})
			var entry: Dictionary=entries.get(texel.y,{})
			if look.is_empty() or look.height_m<=0.0 or String(entry.plant).is_empty(): continue
			var list: Array=transforms_by_crop.get(texel.y,[])
			_plant_rows(rect,index,ImportedSite.row_direction(texel.z),entry,look,list)
			transforms_by_crop[texel.y]=list
		var result: Dictionary={}
		for crop_id in transforms_by_crop:
			var transforms: Array=transforms_by_crop[crop_id]
			if not transforms.is_empty(): result[crop_id]=[transforms,_pack(transforms)]
		return result

	func _plant_rows(rect: Rect2, index: int, direction: Vector2, entry: Dictionary, look: Dictionary, out: Array) -> void:
		var across:=direction.orthogonal()
		var bounds:=Rect2(Vector2(rect.position.dot(direction),rect.position.dot(across)),Vector2.ZERO)
		for p in [Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)]:
			bounds=bounds.expand(Vector2(p.dot(direction),p.dot(across)))
		var spacing:=float(entry.plant_spacing)*stride
		var rows:=float(entry.row_spacing)*stride
		var tramlines: bool=entry.rows.tramlines
		var scale_base:=float(look.height_m)/float(SiteCropLayer.NATIVE_HEIGHT.get(String(entry.plant),1.0))
		for row in range(floori(bounds.position.y/rows),ceili(bounds.end.y/rows)+1):
			# Leave two adjacent planting rows per tramline cycle clear.
			if tramlines and posmod(row*stride,22) in [1,21]: continue
			for plant in range(floori(bounds.position.x/spacing),ceili(bounds.end.x/spacing)+1):
				var point:=direction*(plant*spacing)+across*(row*rows)
				if not rect.has_point(point) or not plantable_on(site,point,index): continue
				var variation:=float(posmod(row*73+plant*137,101))/100.0
				var basis:=Basis(Vector3.UP,variation*TAU).scaled(Vector3.ONE*scale_base*(.92+variation*.12))
				out.append(Transform3D(basis,Vector3(point.x,terrain.get_height(point.x,point.y),point.y)))

	## MultiMesh TRANSFORM_3D buffer: 3x4 row-major, no colour or custom data.
	static func _pack(transforms: Array) -> PackedFloat32Array:
		var buffer:=PackedFloat32Array()
		buffer.resize(transforms.size()*12)
		var o:=0
		for t: Transform3D in transforms:
			var b:=t.basis
			buffer[o]=b.x.x; buffer[o+1]=b.y.x; buffer[o+2]=b.z.x; buffer[o+3]=t.origin.x
			buffer[o+4]=b.x.y; buffer[o+5]=b.y.y; buffer[o+6]=b.z.y; buffer[o+7]=t.origin.y
			buffer[o+8]=b.x.z; buffer[o+9]=b.y.z; buffer[o+10]=b.z.z; buffer[o+11]=t.origin.z
			o+=12
		return buffer

	## Mid-distance canopy: terrain-following quads at crop height where tall
	## crops stand, carrying their colour and row direction. [] when none.
	func _canopy_arrays(cell: Vector2i) -> Array:
		var origin:=Vector2(cell)*SiteCropLayer.CANOPY_CELL
		var step:=SiteCropLayer.CANOPY_STEP
		var st:=SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var quads:=0
		var steps:=int(SiteCropLayer.CANOPY_CELL/step)
		for i in steps:
			for j in steps:
				var centre:=origin+Vector2(i+.5,j+.5)*step
				var texel:=site.field_at(centre.x,centre.y)
				if texel.x==0 or site.farmland(centre.x,centre.y)<SiteCropLayer.FARMLAND_MIN: continue
				var look: Dictionary=looks.get(texel.y,{})
				if look.is_empty() or float(look.height_m)<SiteCropLayer.CANOPY_MIN_HEIGHT: continue
				var entry: Dictionary=entries[texel.y]
				var lift:=float(look.height_m)*.72
				var direction:=ImportedSite.row_direction(texel.z)
				var colour: Color=look.field
				colour.a=1.0 if entry.rows.tramlines else 0.0
				var corners:=[centre+Vector2(-1,-1)*step*.5,centre+Vector2(1,-1)*step*.5,
					centre+Vector2(1,1)*step*.5,centre+Vector2(-1,1)*step*.5]
				for k in [0,1,2,0,2,3]:
					var p: Vector2=corners[k]
					st.set_color(colour)
					st.set_uv(Vector2(float(entry.rows.spacing),0.0))
					st.set_uv2(direction)
					st.set_normal(terrain.get_normal(p.x,p.y))
					st.add_vertex(Vector3(p.x,terrain.get_height(p.x,p.y)+lift,p.y))
				quads+=1
		return st.commit_to_arrays() if quads>0 else []
