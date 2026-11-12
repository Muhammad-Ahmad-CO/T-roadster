extends Node3D
## Dev-only visual check: renders the world + hero from the chase camera and
## saves screenshots, then quits. NOT the main scene. Run with:
##   xvfb-run -a godot --path . render_check.tscn --rendering-driver opengl3
## User args (after a "--" separator):
##   biome=snow|rain|neon|canyon|desert  — one chase shot of that biome,
##       saved as render_check_<biome>.png (regression check).
##   camalt=1  — alternate chase camera (higher, pitched further down) to
##       test whether it widens the ocean in frame; canonical camera is
##       the game's (0, 3.2, 7.5) -> look at (0, 1, -12).

var _shot := 0
var _biome := "coastal"
var _camalt := false

func _ready() -> void:
	# NOTE: no environment or sun of our own here — WorldBuilder builds
	# both, and this check must render exactly what the game renders.
	# (An earlier version of this file created a second WorldEnvironment
	# + a second sun with a different rotation, so the check did not
	# match the game and the sky sun sat behind the camera.)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("biome="):
			_biome = arg.trim_prefix("biome=")
		elif arg == "camalt=1":
			_camalt = true

	# --- Camera: reel chase framing ---
	var cam := Camera3D.new()
	if _camalt:
		cam.position = Vector3(0.0, 4.2, 7.5)
	else:
		cam.position = Vector3(0.0, 3.2, 7.5)
	cam.fov = 62.0
	cam.current = true
	add_child(cam)
	if _camalt:
		cam.look_at(Vector3(0.0, 0.2, -14.0), Vector3.UP)
	else:
		cam.look_at(Vector3(0.0, 1.0, -12.0), Vector3.UP)

	# --- World + hero + traffic ---
	var world := WorldBuilder.new()
	add_child(world)
	world.set_biome(_biome)
	var hero: Node3D = Vehicles.build_hero_pickup(Color(0.95, 0.95, 0.96))
	hero.position = Vector3(0.0, 0.0, 0.0)
	add_child(hero)
	# Paint variation: deep red sedan with brake lights ON (traffic
	# ahead braking is the natural chase-frame state), silver-blue
	# truck, deep blue hatch — so the check shows whether traffic
	# reads as shaped vehicles, not black boxes.
	var car1: Node3D = Vehicles.build_traffic_car("sedan", Color(0.42, 0.06, 0.06))
	car1.position = Vector3(-1.5, 0.0, -28.0)
	Vehicles.set_brake_lights(car1, true)
	add_child(car1)
	var car2: Node3D = Vehicles.build_traffic_car("truck", Color(0.55, 0.60, 0.68))
	car2.position = Vector3(1.5, 0.0, -45.0)
	add_child(car2)
	var car3: Node3D = Vehicles.build_traffic_car("hatch", Color(0.08, 0.15, 0.45))
	car3.position = Vector3(4.5, 0.0, -38.0)
	add_child(car3)
	# Store refs for the shot sequence.
	set_meta("cam", cam)
	set_meta("world", world)
	set_meta("hero", hero)

func _process(_delta: float) -> void:
	_shot += 1
	if _shot == 8:
		if _biome != "coastal":
			_grab("render_check_" + _biome + ".png")
			get_tree().quit()
			return
		_grab("render_check_coastal_camalt.png" if _camalt else "render_check_coastal.png")
	elif _shot == 14:
		# Hero close-up: cinematic detail shot.
		# Round 4 iteration 2: pulled back (was 1.8, 1.7, 4.0) — the
		# first angle cropped the tailgate's left edge. 20% further
		# out keeps the sun ~11.9 deg right of centre (fully in
		# frame) and the hero ~0.6 deg right of centre, with the
		# whole pickup inside the frame.
		var cam: Camera3D = get_meta("cam")
		cam.position = Vector3(2.2, 1.8, 4.8)
		cam.look_at(Vector3(-0.2, 0.8, -0.3), Vector3.UP)
	elif _shot == 20:
		_grab("render_check_hero.png")
		get_tree().quit()

func _grab(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var err: Error = img.save_png(path)
	print("SHOT ", path, " err=", err, " size=", img.get_width(), "x", img.get_height())
