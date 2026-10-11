class_name LocationDefinition
extends Resource

## Authored destination metadata kept out of the landing-screen controller.

@export var slug: String
@export var display_name: String
@export var region: String
@export_multiline var flavour: String
@export var latitude: float
@export var longitude: float
@export_file("*.json") var manifest_path: String
@export_file("*.tres") var foliage_profile_path: String
## Location Studio edits. Empty uses LocationEdits.default_path(slug); a
## missing file means no edits.
@export_file("*.json") var edits_path: String
@export var spawn_xz := Vector2.ZERO
@export var heading_degrees: float = 0.0
@export_range(-89.0, 89.0, 0.1) var pitch_degrees: float = -4.0
@export var eye_height: float = 1.7
@export var atmosphere_profile: AtmosphereProfile
## Season for field crops and other calendar-driven ground: day of the year,
## 1 = 1 January, as at the location (southern sites shift their calendars
## themselves). Mid-July by default.
@export_range(1, 365) var day_of_year: int = 196
## Calendar year, with day_of_year and the atmosphere's time of day, for the
## tide (the Moon's phase); 0 = the current year. Destination configuration,
## like the season.
@export var year: int = 0
