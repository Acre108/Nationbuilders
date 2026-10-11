class_name TreeVariant
extends RefCounted

## One tree shape, ready to instance: three meshes that must always be drawn
## together.
##
##   canopy_mesh  leaves, tree_leaf.gdshader, casts no shadow
##   bark_mesh    trunk and branches, tree_bark.gdshader, casts no shadow
##   proxy_mesh   coarse stand-in, drawn shadows-only; the tree's whole shadow
##
## Model origin is the root, on the ground; +Y up; metres.

var species: String
var source_asset: String
## Model-space height, metres.
var height: float
var canopy_mesh: Mesh
var bark_mesh: Mesh
var proxy_mesh: Mesh
## Visible triangles (canopy + bark), and the proxy's, per instance.
var triangles: int
var proxy_triangles: int
