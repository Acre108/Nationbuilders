class_name DebrisVariant
extends RefCounted

## One rock or deadwood shape, ready to instance. Unlike TreeVariant there is
## only one mesh: debris has no separate canopy/bark/shadow-proxy split. It is
## cheap enough (a few dozen triangles) to cast its own shadow directly.

var species: String
var source_asset: String
var mesh: Mesh
var triangles: int
