extends Node3D
## Мини-Реставратор: cozy 3D симулятор реставрации кукольного домика.
## Вся графика процедурная (без внешних ассетов), управление сенсорное.

const W := 6.0   # ширина комнаты
const D := 4.5   # глубина комнаты
const H := 3.4   # высота комнаты

var wallpapers := [
	{"name": "Полоска", "base": Color("f1e6cf"), "accent": Color("e5a8a8")},
	{"name": "Горошек", "base": Color("9fc7c0"), "accent": Color("f6f0e1")},
	{"name": "Клетка", "base": Color("e8d9a8"), "accent": Color("c9a766")},
	{"name": "Ромбы", "base": Color("7f95c9"), "accent": Color("e9e3d3")},
]
var paints := [
	{"name": "Мятный", "color": Color("8fcfb8")},
	{"name": "Терракот", "color": Color("c9605a")},
	{"name": "Горчица", "color": Color("e0b050")},
	{"name": "Небо", "color": Color("7fb0e0")},
	{"name": "Сливки", "color": Color("f1e6cf")},
	{"name": "Лаванда", "color": Color("a99be0")},
]
var memories := [
	{
		"title": "Ключик под кроватью",
		"text": "В пыли под кроватью нашёлся крошечный ключик на нитке. На бирке карандашом: «Для Веры, когда подрастёшь». Этот дом зимой 1962 года построил её дедушка Ян, часовщик. Он работал над ним по ночам, пока внучка спала."
	},
	{
		"title": "Обои из бабушкиного платья",
		"text": "Под старой бумагой проступил обрывок ткани. Ян не нашёл подходящих обоев и поклеил остатки платья бабушки Нины. Он выглаживал каждую складку пинцетом и говорил, что в доме должно пахнуть домом, а не магазином."
	},
	{
		"title": "Любимый цвет",
		"text": "Вера красила мебель в цвет своих варежек. Мама ворчала на пятна краски на ковре, но ни разу не запретила. Одно кресло так и осталось с отпечатком маленького пальца."
	},
	{
		"title": "Каждый вечер по-новому",
		"text": "Перед сном Вера переставляла мебель и придумывала семьи, которые здесь живут. Кровать всегда ставила к окну: кукле Лизе нужно видеть звёзды."
	},
	{
		"title": "Первый свет",
		"text": "Ян провёл в дом настоящий свет от батарейки для фонарика. Когда в комнате загорелась лампочка, Вера притихла и шёпотом сказала: «Теперь тут кто-то живёт»."
	},
	{
		"title": "Письмо на обороте стены",
		"text": "За стеной нашлась записка: «Вера, дом будет светиться, пока о нём кто-то заботится. Храни его. Дедушка Ян». Комната снова готова. Теперь дом ждёт нового хозяина."
	},
]

var rng := RandomNumberGenerator.new()

# --- мир ---
var env: Environment
var sun: DirectionalLight3D
var pivot: Node3D
var cam: Camera3D
var cam_attr: CameraAttributesPractical
var yaw := 0.3
var pitch := -0.45
var dist := 9.5
var target_dist := 9.5

var worn_tex: ImageTexture
var wp_textures: Array = []
var walls := {}
var wall_quads := {}
var wall_papered := {}
var sockets: Array = []
var furniture: Array = []
var fd := {}
var dust: Array = []
var cables: Array = []
var ring: MeshInstance3D

# --- состояние игры ---
var cur_tool := "brush"
var sel_wallpaper := 0
var sel_paint := 0
var selected: Node3D = null
var wire_src: Node3D = null
var unlocked: Array = []
var done := {}
var filter_idx := 0
var photo_mode := false
var lamps_dimmed := false

# --- ввод ---
var drag_mode := "none"
var pressing := false
var drag_moved := false
var press_pos := Vector2.ZERO
var held: Node3D = null
var touches := {}
var last_pinch := 0.0
var modal_open := false

# --- интерфейс ---
var root_ui: Control
var main_ui: Control
var photo_ui: Control
var progress_label: Label
var hint_label: Label
var toast_label: Label
var toast_tween: Tween
var popup: Control
var popup_title: Label
var popup_body: Label
var wp_box: HBoxContainer
var paint_box: HBoxContainer
var move_box: HBoxContainer
var flash: ColorRect


func _ready() -> void:
	rng.seed = 7
	_load_save()
	_build_world()
	_build_ui()
	_update_progress()
	_set_tool("brush")


# ============================================================ МИР

func _build_world() -> void:
	worn_tex = _worn_texture()
	for i in wallpapers.size():
		wp_textures.append(_wallpaper_texture(i))

	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("2a2420")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("ffe9d0")
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 20, 0)
	sun.light_energy = 0.8
	sun.light_color = Color("fff1dc")
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 30.0
	add_child(sun)

	pivot = Node3D.new()
	pivot.position = Vector3(0, 1.1, 0)
	add_child(pivot)
	cam = Camera3D.new()
	cam.fov = 38.0
	cam.near = 0.1
	cam.far = 80.0
	cam_attr = CameraAttributesPractical.new()
	cam_attr.dof_blur_far_enabled = false
	cam_attr.dof_blur_far_transition = 6.0
	cam_attr.dof_blur_amount = 0.08
	cam.attributes = cam_attr
	cam.position = Vector3(0, 0, dist)
	pivot.add_child(cam)

	# рабочий стол: зелёный коврик для резки
	var mat_table := StandardMaterial3D.new()
	mat_table.albedo_texture = _grid_texture()
	mat_table.uv1_scale = Vector3(30, 30, 1)
	mat_table.roughness = 1.0
	var plane := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	plane.mesh = pm
	plane.position.y = -0.6
	plane.material_override = mat_table
	add_child(plane)

	# подставка дома
	_box(self, Vector3(W + 1.0, 0.3, D + 1.0), Vector3(0, -0.45, 0.1), _mat(Color("5b4030"), 0.9))

	# пол
	var floor_body := StaticBody3D.new()
	floor_body.position = Vector3(0, -0.15, 0.1)
	floor_body.set_meta("kind", "floor")
	var fs := CollisionShape3D.new()
	var fb := BoxShape3D.new()
	fb.size = Vector3(W + 0.4, 0.3, D + 0.4)
	fs.shape = fb
	floor_body.add_child(fs)
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_texture = _floor_texture()
	floor_mat.uv1_scale = Vector3(4, 3, 1)
	floor_mat.roughness = 0.85
	_box(floor_body, Vector3(W + 0.4, 0.3, D + 0.4), Vector3.ZERO, floor_mat)
	add_child(floor_body)

	# стены
	_make_wall("back", Vector3(W + 0.4, H, 0.2), Vector3(0, H / 2.0, -D / 2.0 - 0.1),
		Vector2(W, H), Vector3(0, H / 2.0, -D / 2.0 + 0.003), 0.0)
	_make_wall("left", Vector3(0.2, H, D), Vector3(-W / 2.0 - 0.1, H / 2.0, 0),
		Vector2(D, H), Vector3(-W / 2.0 + 0.003, H / 2.0, 0), PI / 2.0)
	_make_wall("right", Vector3(0.2, H, D), Vector3(W / 2.0 + 0.1, H / 2.0, 0),
		Vector2(D, H), Vector3(W / 2.0 - 0.003, H / 2.0, 0), -PI / 2.0)

	_make_window()
	_make_socket(Vector3(-1.6, 0.6, -D / 2.0 + 0.02), 0.0, Vector3(0, 0, 1))
	_make_socket(Vector3(W / 2.0 - 0.02, 0.6, 0.2), PI / 2.0, Vector3(-1, 0, 0))

	# кольцо выделения мебели
	ring = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.93
	tm.outer_radius = 1.0
	ring.mesh = tm
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.albedo_color = Color("ffd24a")
	ring.material_override = rm
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	_make_all_furniture()
	_spawn_dust()
	_make_motes()


func _make_wall(id: String, box_size: Vector3, box_pos: Vector3, quad_size: Vector2,
		quad_pos: Vector3, quad_yaw: float) -> void:
	var body := StaticBody3D.new()
	body.position = box_pos
	body.set_meta("kind", "wall")
	body.set_meta("id", id)
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = box_size
	shape.shape = bs
	body.add_child(shape)
	_box(body, box_size, Vector3.ZERO, _mat(Color("7a5a3c"), 0.9))
	var quad := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = quad_size
	quad.mesh = qm
	quad.position = quad_pos - box_pos
	quad.rotation.y = quad_yaw
	var m := StandardMaterial3D.new()
	m.albedo_texture = worn_tex
	m.roughness = 1.0
	quad.material_override = m
	body.add_child(quad)
	add_child(body)
	walls[id] = body
	wall_quads[id] = quad


func _make_window() -> void:
	var wnd := Node3D.new()
	wnd.position = Vector3(0.9, 1.9, -D / 2.0 + 0.01)
	add_child(wnd)
	var pane := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(1.2, 1.0)
	pane.mesh = q
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color("bfe3ff")
	pm.emission_enabled = true
	pm.emission = Color("9ccaf0")
	pm.emission_energy_multiplier = 0.8
	pane.material_override = pm
	pane.position.z = 0.004
	wnd.add_child(pane)
	var fm := _mat(Color("f3ece0"))
	_box(wnd, Vector3(1.4, 0.1, 0.06), Vector3(0, 0.55, 0.02), fm)
	_box(wnd, Vector3(1.4, 0.1, 0.06), Vector3(0, -0.55, 0.02), fm)
	_box(wnd, Vector3(0.1, 1.2, 0.06), Vector3(-0.65, 0, 0.02), fm)
	_box(wnd, Vector3(0.1, 1.2, 0.06), Vector3(0.65, 0, 0.02), fm)
	_box(wnd, Vector3(0.05, 1.0, 0.05), Vector3(0, 0, 0.02), fm)
	_box(wnd, Vector3(1.2, 0.05, 0.05), Vector3(0, 0, 0.02), fm)


func _make_socket(pos: Vector3, yaw_angle: float, normal: Vector3) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	body.rotation.y = yaw_angle
	body.set_meta("kind", "socket")
	body.set_meta("normal", normal)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.32, 0.32, 0.14)
	cs.shape = bs
	body.add_child(cs)
	_box(body, Vector3(0.16, 0.16, 0.04), Vector3.ZERO, _mat(Color("f4efe6")))
	_box(body, Vector3(0.02, 0.05, 0.045), Vector3(-0.03, 0.0, 0.0), _mat(Color("222222")))
	_box(body, Vector3(0.02, 0.05, 0.045), Vector3(0.03, 0.0, 0.0), _mat(Color("222222")))
	add_child(body)
	sockets.append(body)


func _make_motes() -> void:
	var p := CPUParticles3D.new()
	p.amount = 40
	p.lifetime = 10.0
	p.preprocess = 10.0
	p.position = Vector3(0, 1.5, 0)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(W / 2.0 - 0.3, 1.4, D / 2.0 - 0.3)
	p.direction = Vector3(0, 1, 0)
	p.spread = 180.0
	p.initial_velocity_min = 0.02
	p.initial_velocity_max = 0.08
	p.gravity = Vector3.ZERO
	var sm := SphereMesh.new()
	sm.radius = 0.012
	sm.height = 0.024
	sm.radial_segments = 6
	sm.rings = 3
	var mm := StandardMaterial3D.new()
	mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mm.albedo_color = Color(1, 0.95, 0.8, 0.7)
	mm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.material = mm
	p.mesh = sm
	add_child(p)


# ============================================================ ПРОЦЕДУРНЫЕ ТЕКСТУРЫ

func _grid_texture() -> ImageTexture:
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var c := Color("2f5d4a")
			if x % 32 == 0 or y % 32 == 0:
				c = Color("6fa08a")
			elif x % 8 == 0 or y % 8 == 0:
				c = Color("3b6e58")
			img.set_pixel(x, y, c)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _floor_texture() -> ImageTexture:
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	var row_shift := [0.0, 0.05, -0.04, 0.03]
	for y in 64:
		var row := floori(y / 16.0)
		var sh: float = row_shift[row % 4]
		for x in 64:
			var v := sh + rng.randf_range(-0.02, 0.02)
			var c := Color(0.66 + v, 0.52 + v, 0.34 + v)
			if y % 16 == 0 or (x + row * 21) % 40 == 0:
				c = Color(0.36, 0.27, 0.18)
			img.set_pixel(x, y, c)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _worn_texture() -> ImageTexture:
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var v := rng.randf_range(-0.04, 0.04)
			if sin(x * 0.3) * sin(y * 0.25) > 0.7:
				v -= 0.08
			img.set_pixel(x, y, Color(0.55 + v, 0.5 + v, 0.43 + v))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _wallpaper_texture(kind: int) -> ImageTexture:
	var base: Color = wallpapers[kind]["base"]
	var accent: Color = wallpapers[kind]["accent"]
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var col := base
			match kind:
				0:
					if x % 16 < 5:
						col = accent
				1:
					var dx := (x % 32) - 16
					var dy := (y % 32) - 16
					if dx * dx + dy * dy < 24:
						col = accent
				2:
					if (floori(x / 16.0) + floori(y / 16.0)) % 2 == 0:
						col = accent
				3:
					if absi((x % 32) - 16) + absi((y % 32) - 16) < 9:
						col = accent
			img.set_pixel(x, y, col)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


# ============================================================ МЕБЕЛЬ

func _mat(c: Color, rough := 0.8) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


func _box(parent: Node, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)
	return mi


func _cyl(parent: Node, top_r: float, bottom_r: float, h: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = top_r
	cm.bottom_radius = bottom_r
	cm.height = h
	cm.radial_segments = 20
	mi.mesh = cm
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)
	return mi


func _faded() -> Color:
	var list := [Color("a99884"), Color("9c8f80"), Color("b3a48e"), Color("a08f7a")]
	return list[rng.randi() % list.size()]


func _pbox(n: Node3D, size: Vector3, pos: Vector3) -> MeshInstance3D:
	var mi := _box(n, size, pos, _mat(_faded()))
	fd[n]["paint"].append(mi)
	return mi


func _new_furn(label: String, hx: float, hz: float, h: float, pos: Vector3, steps: int) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	n.rotation.y = steps * PI / 2.0
	var body := StaticBody3D.new()
	body.set_meta("kind", "furn")
	body.set_meta("ref", n)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(hx * 2.0, h, hz * 2.0)
	cs.shape = bs
	cs.position.y = h / 2.0
	body.add_child(cs)
	n.add_child(body)
	add_child(n)
	furniture.append(n)
	fd[n] = {
		"label": label, "hx": hx, "hz": hz, "h": h,
		"steps": steps, "rot": steps * PI / 2.0,
		"paint": [], "painted": false, "moved": false,
		"lamp": false, "wired": false,
	}
	return n


func _add_light(n: Node3D, y: float, shade: MeshInstance3D) -> void:
	var bulb_mat := StandardMaterial3D.new()
	bulb_mat.albedo_color = Color("fff3d6")
	var bulb := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.05
	sm.height = 0.1
	bulb.mesh = sm
	bulb.material_override = bulb_mat
	bulb.position.y = y
	n.add_child(bulb)
	var light := OmniLight3D.new()
	light.position.y = y
	light.light_color = Color("ffc98a")
	light.light_energy = 0.0
	light.omni_range = 4.5
	n.add_child(light)
	var d: Dictionary = fd[n]
	d["lamp"] = true
	d["light"] = light
	d["bulb_mat"] = bulb_mat
	d["shade"] = shade


func _make_all_furniture() -> void:
	_make_bed(Vector3(-1.7, 0, 0.9), 1)
	_make_wardrobe(Vector3(0.2, 0, -0.3), 2)
	_make_table(Vector3(1.5, 0, 0.8), 0)
	_make_chair(Vector3(0.3, 0, 1.3), 3)
	_make_bookshelf(Vector3(-0.6, 0, -1.0), 1)
	_make_floor_lamp(Vector3(2.5, 0, -0.4), 0)
	_make_nightstand(Vector3(-2.5, 0, -1.6), 0)
	_make_rug(Vector3(0.3, 0, -1.5), 0)
	_make_armchair(Vector3(2.3, 0, 1.6), 2)


func _make_bed(pos: Vector3, steps: int) -> void:
	var n := _new_furn("Кровать", 0.95, 0.6, 0.75, pos, steps)
	_pbox(n, Vector3(1.9, 0.25, 1.2), Vector3(0, 0.2, 0))
	_pbox(n, Vector3(0.1, 0.75, 1.2), Vector3(-0.9, 0.375, 0))
	_box(n, Vector3(1.75, 0.18, 1.1), Vector3(0.05, 0.42, 0), _mat(Color("e8e2d4")))
	_box(n, Vector3(0.45, 0.12, 0.8), Vector3(-0.62, 0.57, 0), _mat(Color("f4efe6")))
	_pbox(n, Vector3(1.0, 0.06, 1.12), Vector3(0.4, 0.52, 0))


func _make_wardrobe(pos: Vector3, steps: int) -> void:
	var n := _new_furn("Шкаф", 0.5, 0.3, 2.1, pos, steps)
	_pbox(n, Vector3(1.0, 2.0, 0.6), Vector3(0, 1.0, 0))
	_pbox(n, Vector3(1.1, 0.08, 0.7), Vector3(0, 2.04, 0))
	_box(n, Vector3(0.015, 1.8, 0.01), Vector3(0, 1.0, 0.305), _mat(Color("2b211a")))
	_box(n, Vector3(0.06, 0.06, 0.04), Vector3(-0.1, 1.0, 0.31), _mat(Color("d6a84a"), 0.3))
	_box(n, Vector3(0.06, 0.06, 0.04), Vector3(0.1, 1.0, 0.31), _mat(Color("d6a84a"), 0.3))


func _make_table(pos: Vector3, steps: int) -> void:
	var n := _new_furn("Стол", 0.6, 0.4, 0.85, pos, steps)
	_pbox(n, Vector3(1.2, 0.07, 0.8), Vector3(0, 0.71, 0))
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_pbox(n, Vector3(0.07, 0.7, 0.07), Vector3(0.52 * sx, 0.35, 0.32 * sz))
	_cyl(n, 0.05, 0.035, 0.08, Vector3(0.2, 0.785, 0.05), _mat(Color("f7f4ee"), 0.2))
	_box(n, Vector3(0.22, 0.03, 0.16), Vector3(-0.25, 0.765, -0.05), _mat(Color("b05a4a")))


func _make_chair(pos: Vector3, steps: int) -> void:
	var n := _new_furn("Стул", 0.25, 0.25, 0.95, pos, steps)
	_pbox(n, Vector3(0.5, 0.05, 0.5), Vector3(0, 0.45, 0))
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_pbox(n, Vector3(0.05, 0.45, 0.05), Vector3(0.21 * sx, 0.225, 0.21 * sz))
	_pbox(n, Vector3(0.5, 0.5, 0.05), Vector3(0, 0.725, -0.225))


func _make_bookshelf(pos: Vector3, steps: int) -> void:
	var n := _new_furn("Книжный шкаф", 0.55, 0.2, 1.8, pos, steps)
	_pbox(n, Vector3(0.05, 1.8, 0.4), Vector3(-0.525, 0.9, 0))
	_pbox(n, Vector3(0.05, 1.8, 0.4), Vector3(0.525, 0.9, 0))
	_pbox(n, Vector3(1.1, 1.8, 0.03), Vector3(0, 0.9, -0.185))
	var levels := [0.02, 0.6, 1.2, 1.78]
	for ly in levels:
		_pbox(n, Vector3(1.0, 0.04, 0.4), Vector3(0, ly, 0))
	var book_colors := [Color("b05a4a"), Color("4f7a6a"), Color("d6a84a"), Color("5c6fa0"), Color("e8d9a8"), Color("8a4a6a")]
	for lvl in 3:
		var base_y: float = levels[lvl] + 0.02
		var x := -0.46
		while x < 0.42:
			var w := rng.randf_range(0.04, 0.09)
			var hh := rng.randf_range(0.18, 0.42)
			var col: Color = book_colors[rng.randi() % book_colors.size()]
			_box(n, Vector3(w, hh, 0.22), Vector3(x + w / 2.0, base_y + hh / 2.0, 0), _mat(col))
			x += w + 0.005
			if rng.randf() < 0.12:
				x += 0.15


func _make_floor_lamp(pos: Vector3, steps: int) -> void:
	var n := _new_furn("Торшер", 0.2, 0.2, 1.7, pos, steps)
	_cyl(n, 0.18, 0.18, 0.04, Vector3(0, 0.02, 0), _mat(Color("4a3a30")))
	_cyl(n, 0.015, 0.015, 1.4, Vector3(0, 0.72, 0), _mat(Color("4a3a30")))
	var shade := _cyl(n, 0.12, 0.24, 0.32, Vector3(0, 1.55, 0), _mat(_faded()))
	fd[n]["paint"].append(shade)
	_add_light(n, 1.5, shade)


func _make_nightstand(pos: Vector3, steps: int) -> void:
	var n := _new_furn("Тумбочка с лампой", 0.3, 0.25, 0.9, pos, steps)
	_pbox(n, Vector3(0.6, 0.5, 0.5), Vector3(0, 0.25, 0))
	_box(n, Vector3(0.4, 0.015, 0.01), Vector3(0, 0.33, 0.255), _mat(Color("2b211a")))
	_box(n, Vector3(0.06, 0.03, 0.03), Vector3(0, 0.33, 0.27), _mat(Color("d6a84a"), 0.3))
	_cyl(n, 0.06, 0.06, 0.03, Vector3(0, 0.515, 0), _mat(Color("4a3a30")))
	_cyl(n, 0.01, 0.01, 0.2, Vector3(0, 0.63, 0), _mat(Color("4a3a30")))
	var shade := _cyl(n, 0.05, 0.1, 0.13, Vector3(0, 0.78, 0), _mat(_faded()))
	fd[n]["paint"].append(shade)
	_add_light(n, 0.74, shade)


func _make_rug(pos: Vector3, steps: int) -> void:
	var n := _new_furn("Ковёр", 0.9, 0.6, 0.04, pos, steps)
	var mi := _cyl(n, 0.9, 0.9, 0.03, Vector3(0, 0.015, 0), _mat(_faded(), 1.0))
	mi.scale = Vector3(1.0, 1.0, 0.66)
	fd[n]["paint"].append(mi)


func _make_armchair(pos: Vector3, steps: int) -> void:
	var n := _new_furn("Кресло", 0.4, 0.4, 0.85, pos, steps)
	_pbox(n, Vector3(0.8, 0.3, 0.8), Vector3(0, 0.15, 0))
	_pbox(n, Vector3(0.7, 0.15, 0.7), Vector3(0, 0.375, 0.02))
	_pbox(n, Vector3(0.8, 0.55, 0.15), Vector3(0, 0.575, -0.325))
	_pbox(n, Vector3(0.12, 0.3, 0.7), Vector3(-0.34, 0.45, 0.02))
	_pbox(n, Vector3(0.12, 0.3, 0.7), Vector3(0.34, 0.45, 0.02))


func _spawn_dust() -> void:
	var dm := StandardMaterial3D.new()
	dm.albedo_color = Color(0.55, 0.5, 0.42, 0.8)
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.roughness = 1.0
	for i in 14:
		var p := Vector3.ZERO
		for t in 40:
			p = Vector3(rng.randf_range(-W / 2.0 + 0.5, W / 2.0 - 0.5), 0.012,
				rng.randf_range(-D / 2.0 + 0.5, D / 2.0 - 0.5))
			if _free_spot(p):
				break
		var r := rng.randf_range(0.22, 0.4)
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = r
		cm.bottom_radius = r
		cm.height = 0.02
		cm.radial_segments = 14
		mi.mesh = cm
		mi.material_override = dm
		mi.position = p
		mi.rotation.y = rng.randf() * TAU
		mi.scale = Vector3(1.0, 1.0, rng.randf_range(0.6, 1.0))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		dust.append(mi)


func _free_spot(p: Vector3) -> bool:
	for f in furniture:
		var d: Dictionary = fd[f]
		if d["label"] == "Ковёр":
			continue
		var rr := maxf(float(d["hx"]), float(d["hz"])) + 0.25
		if Vector2(p.x, p.z).distance_to(Vector2(f.position.x, f.position.z)) < rr:
			return false
	return true


# ============================================================ ИГРОВАЯ ЛОГИКА

func _pick(pos: Vector2) -> Dictionary:
	var from := cam.project_ray_origin(pos)
	var to := from + cam.project_ray_normal(pos) * 60.0
	var q := PhysicsRayQueryParameters3D.create(from, to)
	return get_world_3d().direct_space_state.intersect_ray(q)


func _kind_of(col: Object) -> String:
	if col != null and col.has_meta("kind"):
		return str(col.get_meta("kind"))
	return ""


func _wipe_at(pos: Vector2) -> void:
	var hit := _pick(pos)
	if hit.is_empty():
		return
	if _kind_of(hit["collider"]) == "wall":
		return
	var hp: Vector3 = hit["position"]
	for item in dust.duplicate():
		var mi: MeshInstance3D = item
		if Vector2(mi.position.x, mi.position.z).distance_to(Vector2(hp.x, hp.z)) < 0.55:
			dust.erase(mi)
			var tw := create_tween()
			tw.tween_property(mi, "scale", Vector3(0.01, 0.01, 0.01), 0.25)
			tw.tween_callback(mi.queue_free)
	if dust.is_empty() and not done.has("clean"):
		_milestone("clean", 0)


func _on_press(pos: Vector2) -> void:
	drag_mode = "orbit"
	var hit := _pick(pos)
	if hit.is_empty():
		return
	var kind := _kind_of(hit["collider"])
	if cur_tool == "brush" and kind != "wall":
		drag_mode = "wipe"
		_wipe_at(pos)
	elif cur_tool == "move" and kind == "furn":
		var col: Node = hit["collider"]
		held = col.get_meta("ref")
		drag_mode = "hold"
		_select(held)


func _on_drag(pos: Vector2, rel: Vector2) -> void:
	match drag_mode:
		"orbit":
			if touches.size() >= 2 or not drag_moved:
				return
			yaw = clampf(yaw - rel.x * 0.005, -1.25, 1.25)
			pitch = clampf(pitch - rel.y * 0.005, -1.3, -0.08)
		"wipe":
			_wipe_at(pos)
		"hold":
			if drag_moved:
				_drag_held(pos)


func _on_release(pos: Vector2) -> void:
	if drag_mode == "orbit" and not drag_moved:
		_on_tap(pos)
	elif drag_mode == "hold":
		held = null
		var cnt := 0
		for f in furniture:
			if fd[f]["moved"]:
				cnt += 1
		if cnt >= 6 and not done.has("arrange"):
			_milestone("arrange", 3)
	drag_mode = "none"


func _on_tap(pos: Vector2) -> void:
	var hit := _pick(pos)
	if hit.is_empty():
		return
	var col: Node = hit["collider"]
	var kind := _kind_of(col)
	match cur_tool:
		"wallpaper":
			if kind == "wall":
				_apply_wallpaper(str(col.get_meta("id")))
			else:
				toast("Коснитесь стены")
		"paint":
			if kind == "furn":
				_paint(col.get_meta("ref"))
			else:
				toast("Коснитесь мебели")
		"move":
			if kind == "furn":
				_select(col.get_meta("ref"))
		"wire":
			if kind == "furn":
				var n: Node3D = col.get_meta("ref")
				if fd[n]["lamp"]:
					wire_src = n
					_select(n)
					toast("Лампа выбрана. Коснитесь розетки на стене")
				else:
					toast("Это не лампа")
			elif kind == "socket":
				if wire_src == null:
					toast("Сначала коснитесь лампы")
				else:
					_connect(wire_src, col)


func _apply_wallpaper(id: String) -> void:
	var quad: MeshInstance3D = wall_quads[id]
	var qm := quad.mesh as QuadMesh
	var m := StandardMaterial3D.new()
	m.albedo_texture = wp_textures[sel_wallpaper]
	m.uv1_scale = Vector3(qm.size.x / 1.6, qm.size.y / 1.6, 1.0)
	m.roughness = 0.95
	m.albedo_color = Color(0.5, 0.5, 0.5)
	quad.material_override = m
	create_tween().tween_property(m, "albedo_color", Color.WHITE, 0.4)
	wall_papered[id] = true
	if wall_papered.size() >= 3 and not done.has("wallpaper"):
		_milestone("wallpaper", 1)


func _paint(n: Node3D) -> void:
	var d: Dictionary = fd[n]
	var col: Color = paints[sel_paint]["color"]
	for item in d["paint"]:
		var mi: MeshInstance3D = item
		var m := mi.material_override as StandardMaterial3D
		create_tween().tween_property(m, "albedo_color", col, 0.4)
	d["painted"] = true
	_pulse(n)
	var cnt := 0
	for f in furniture:
		if fd[f]["painted"]:
			cnt += 1
	if cnt >= 3 and not done.has("paint"):
		_milestone("paint", 2)


func _pulse(n: Node3D) -> void:
	n.scale = Vector3.ONE * 1.06
	create_tween().tween_property(n, "scale", Vector3.ONE, 0.25)


func _select(n: Node3D) -> void:
	selected = n
	if ring.get_parent() != null:
		ring.get_parent().remove_child(ring)
	if n == null:
		return
	var d: Dictionary = fd[n]
	var r := maxf(float(d["hx"]), float(d["hz"])) + 0.12
	ring.scale = Vector3(r, 0.04, r)
	n.add_child(ring)
	ring.position = Vector3(0, 0.02, 0)


func _clamp_pos(n: Node3D, p: Vector3) -> Vector3:
	var d: Dictionary = fd[n]
	var hx: float = d["hx"]
	var hz: float = d["hz"]
	if int(d["steps"]) % 2 == 1:
		var tmp := hx
		hx = hz
		hz = tmp
	return Vector3(
		clampf(snappedf(p.x, 0.1), -W / 2.0 + hx, W / 2.0 - hx), 0.0,
		clampf(snappedf(p.z, 0.1), -D / 2.0 + hz, D / 2.0 - hz))


func _drag_held(pos: Vector2) -> void:
	if held == null:
		return
	var from := cam.project_ray_origin(pos)
	var dir := cam.project_ray_normal(pos)
	if absf(dir.y) < 0.001:
		return
	var t := -from.y / dir.y
	if t < 0.0:
		return
	held.position = _clamp_pos(held, from + dir * t)
	fd[held]["moved"] = true
	_update_cables()


func _rotate_selected() -> void:
	if selected == null:
		toast("Сначала выберите мебель")
		return
	var d: Dictionary = fd[selected]
	d["steps"] = (int(d["steps"]) + 1) % 4
	d["rot"] = float(d["rot"]) + PI / 2.0
	create_tween().tween_property(selected, "rotation:y", d["rot"], 0.2)
	selected.position = _clamp_pos(selected, selected.position)
	_update_cables()


func _connect(lamp: Node3D, socket: Node) -> void:
	for c in cables.duplicate():
		if c["lamp"] == lamp:
			for s in c["segs"]:
				(s as Node).queue_free()
			cables.erase(c)
	var segs: Array = []
	for i in 2:
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.012
		cm.bottom_radius = 0.012
		cm.radial_segments = 6
		mi.mesh = cm
		mi.material_override = _mat(Color("1d1d1d"))
		add_child(mi)
		segs.append(mi)
	cables.append({"lamp": lamp, "socket": socket, "segs": segs})
	_update_cables()
	var d: Dictionary = fd[lamp]
	if not d["wired"]:
		d["wired"] = true
		_lamp_on(lamp)
	wire_src = null
	toast("Подключено!")
	var all_wired := true
	for f in furniture:
		if fd[f]["lamp"] and not fd[f]["wired"]:
			all_wired = false
	if all_wired and not done.has("light"):
		_milestone("light", 4)


func _update_cables() -> void:
	for c in cables:
		var lamp: Node3D = c["lamp"]
		var sock: Node3D = c["socket"]
		var segs: Array = c["segs"]
		var a := Vector3(lamp.position.x, 0.02, lamp.position.z)
		var s := sock.position
		var nrm: Vector3 = sock.get_meta("normal")
		var f := Vector3(s.x + nrm.x * 0.12, 0.02, s.z + nrm.z * 0.12)
		_place_segment(segs[0], a, f)
		_place_segment(segs[1], f, s)


func _place_segment(mi: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	var length := a.distance_to(b)
	mi.visible = length > 0.01
	if length <= 0.01:
		return
	(mi.mesh as CylinderMesh).height = length
	var dir := (b - a) / length
	var up := Vector3.UP
	if absf(dir.dot(Vector3.UP)) > 0.95:
		up = Vector3.RIGHT
	mi.look_at_from_position((a + b) * 0.5, b, up)
	mi.rotate_object_local(Vector3.RIGHT, PI / 2.0)


func _lamp_on(n: Node3D) -> void:
	var d: Dictionary = fd[n]
	var light: OmniLight3D = d["light"]
	var bm: StandardMaterial3D = d["bulb_mat"]
	bm.emission_enabled = true
	bm.emission = Color("ffd9a0")
	bm.emission_energy_multiplier = 3.0
	var sh: MeshInstance3D = d["shade"]
	var sm := sh.material_override as StandardMaterial3D
	sm.emission_enabled = true
	sm.emission = Color("ffcf8a")
	sm.emission_energy_multiplier = 0.6
	create_tween().tween_property(light, "light_energy", 2.2, 0.6)
	if not lamps_dimmed:
		lamps_dimmed = true
		var tw := create_tween().set_parallel(true)
		tw.tween_property(env, "ambient_light_energy", 0.3, 1.5)
		tw.tween_property(sun, "light_energy", 0.4, 1.5)


func _milestone(id: String, mem_idx: int) -> void:
	done[id] = true
	await get_tree().create_timer(0.7).timeout
	_unlock_memory(mem_idx)


func _unlock_memory(i: int) -> void:
	if i in unlocked:
		toast("Этап пройден. Это воспоминание уже в дневнике")
		return
	unlocked.append(i)
	_save()
	_update_progress()
	_show_popup("Воспоминание: " + str(memories[i]["title"]), str(memories[i]["text"]))


# ============================================================ КАМЕРА И ФОТО

func _process(dt: float) -> void:
	dist = lerpf(dist, target_dist, clampf(dt * 8.0, 0.0, 1.0))
	pivot.rotation = Vector3(pitch, yaw, 0.0)
	cam.position = Vector3(0.0, 0.0, dist)
	var cx := cam.global_position.x
	_set_wall_visible("left", cx > -W / 2.0 - 0.1)
	_set_wall_visible("right", cx < W / 2.0 + 0.1)
	if photo_mode:
		cam_attr.dof_blur_far_distance = dist + 4.0


func _set_wall_visible(id: String, vis: bool) -> void:
	var body: StaticBody3D = walls[id]
	body.visible = vis
	body.collision_layer = 1 if vis else 0


func _zoom(delta: float) -> void:
	target_dist = clampf(target_dist + delta, 4.5, 15.0)


func _enter_photo() -> void:
	photo_mode = true
	main_ui.visible = false
	photo_ui.visible = true
	_select(null)
	cam_attr.dof_blur_far_enabled = true


func _exit_photo() -> void:
	photo_mode = false
	main_ui.visible = true
	photo_ui.visible = false
	cam_attr.dof_blur_far_enabled = false


func _next_filter() -> void:
	filter_idx = (filter_idx + 1) % 3
	env.adjustment_enabled = filter_idx != 0
	match filter_idx:
		0:
			toast("Фильтр: обычный")
		1:
			env.adjustment_saturation = 1.35
			env.adjustment_contrast = 1.05
			toast("Фильтр: насыщенный")
		2:
			env.adjustment_saturation = 0.0
			env.adjustment_contrast = 1.1
			toast("Фильтр: чёрно-белый")


func _take_photo() -> void:
	photo_ui.visible = false
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	photo_ui.visible = true
	flash.modulate.a = 0.9
	create_tween().tween_property(flash, "modulate:a", 0.0, 0.4)
	var path := _save_image(img)
	if path == "":
		toast("Не удалось сохранить фото")
	else:
		toast("Фото сохранено: " + path)
	if done.size() >= 5 and not done.has("photo"):
		_milestone("photo", 5)
	elif not done.has("photo"):
		await get_tree().create_timer(2.5).timeout
		toast("Закончите все этапы, и фото откроет последнее воспоминание")


func _save_image(img: Image) -> String:
	var fname := "dollhouse_%d.png" % int(Time.get_unix_time_from_system())
	var dirs: Array = []
	if OS.get_name() == "Android":
		dirs.append(OS.get_system_dir(OS.SYSTEM_DIR_PICTURES) + "/MiniRestorer")
	dirs.append(OS.get_user_data_dir() + "/photos")
	for dir_path in dirs:
		if DirAccess.make_dir_recursive_absolute(dir_path) == OK:
			var p: String = str(dir_path) + "/" + fname
			if img.save_png(p) == OK:
				return p
	return ""


# ============================================================ ВВОД

func _input(e: InputEvent) -> void:
	if e is InputEventScreenTouch:
		if e.pressed:
			touches[e.index] = e.position
		else:
			touches.erase(e.index)
		last_pinch = 0.0
	elif e is InputEventScreenDrag:
		touches[e.index] = e.position
		if touches.size() == 2 and not modal_open:
			var ks := touches.keys()
			var p0: Vector2 = touches[ks[0]]
			var p1: Vector2 = touches[ks[1]]
			var d := p0.distance_to(p1)
			if last_pinch > 0.0:
				target_dist = clampf(target_dist - (d - last_pinch) * 0.02, 4.5, 15.0)
			last_pinch = d


func _unhandled_input(e: InputEvent) -> void:
	if modal_open:
		return
	if e is InputEventMouseButton:
		if e.button_index == MOUSE_BUTTON_LEFT:
			if e.pressed:
				pressing = true
				drag_moved = false
				press_pos = e.position
				_on_press(e.position)
			else:
				if pressing:
					_on_release(e.position)
				pressing = false
		elif e.pressed and e.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom(-1.0)
		elif e.pressed and e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom(1.0)
	elif e is InputEventMouseMotion and pressing:
		if not drag_moved and e.position.distance_to(press_pos) > 14.0:
			drag_moved = true
		_on_drag(e.position, e.relative)


# ============================================================ ИНТЕРФЕЙС

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var theme := Theme.new()
	theme.default_font_size = 26
	root_ui = Control.new()
	root_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	root_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_ui.theme = theme
	layer.add_child(root_ui)

	main_ui = _margin_root()
	root_ui.add_child(main_ui)
	var vbox := VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main_ui.add_child(vbox)

	# верхняя панель
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(top)
	var pp := PanelContainer.new()
	progress_label = Label.new()
	pp.add_child(progress_label)
	top.add_child(pp)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(sp)
	_btn(top, "Дневник", _open_diary)
	_btn(top, "Фото", _enter_photo)
	_btn(top, "+", _zoom.bind(-1.5))
	_btn(top, "-", _zoom.bind(1.5))

	hint_label = _outlined_label(vbox)
	toast_label = _outlined_label(vbox)
	toast_label.text = " "
	toast_label.modulate.a = 0.0

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(spacer)

	# палитры
	var palette := HBoxContainer.new()
	palette.alignment = BoxContainer.ALIGNMENT_CENTER
	palette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(palette)

	wp_box = HBoxContainer.new()
	wp_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	palette.add_child(wp_box)
	var wp_group := ButtonGroup.new()
	for i in wallpapers.size():
		var b := _swatch(wp_box, str(wallpapers[i]["name"]), wallpapers[i]["base"],
			wallpapers[i]["accent"], wp_group, _pick_wallpaper.bind(i))
		b.button_pressed = (i == 0)

	paint_box = HBoxContainer.new()
	paint_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	palette.add_child(paint_box)
	var pg := ButtonGroup.new()
	for i in paints.size():
		var b := _swatch(paint_box, str(paints[i]["name"]), paints[i]["color"],
			Color("2b211a"), pg, _pick_paint.bind(i))
		b.button_pressed = (i == 0)

	move_box = HBoxContainer.new()
	move_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	palette.add_child(move_box)
	_btn(move_box, "Повернуть", _rotate_selected)

	# панель инструментов
	var tools := HBoxContainer.new()
	tools.alignment = BoxContainer.ALIGNMENT_CENTER
	tools.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(tools)
	var tg := ButtonGroup.new()
	var tool_defs := [["brush", "Кисть"], ["wallpaper", "Обои"], ["paint", "Краска"],
		["move", "Мебель"], ["wire", "Свет"]]
	for td in tool_defs:
		var b := Button.new()
		b.text = td[1]
		b.toggle_mode = true
		b.button_group = tg
		b.custom_minimum_size = Vector2(150, 68)
		b.pressed.connect(_set_tool.bind(td[0]))
		tools.add_child(b)
		if td[0] == "brush":
			b.button_pressed = true

	# режим фото
	photo_ui = _margin_root()
	photo_ui.visible = false
	root_ui.add_child(photo_ui)
	var pv := VBoxContainer.new()
	pv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	photo_ui.add_child(pv)
	var ptop := HBoxContainer.new()
	ptop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pv.add_child(ptop)
	_btn(ptop, "Назад", _exit_photo)
	var psp := Control.new()
	psp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	psp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pv.add_child(psp)
	var pbot := HBoxContainer.new()
	pbot.alignment = BoxContainer.ALIGNMENT_CENTER
	pbot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pv.add_child(pbot)
	_btn(pbot, "+", _zoom.bind(-1.5))
	_btn(pbot, "-", _zoom.bind(1.5))
	_btn(pbot, "Фильтр", _next_filter)
	var shutter := _btn(pbot, "Снять", _take_photo)
	shutter.custom_minimum_size = Vector2(200, 80)

	_build_popup()

	flash = ColorRect.new()
	flash.color = Color.WHITE
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.modulate.a = 0.0
	root_ui.add_child(flash)


func _margin_root() -> MarginContainer:
	var m := MarginContainer.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 16)
	return m


func _outlined_label(parent: Control) -> Label:
	var l := Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 8)
	parent.add_child(l)
	return l


func _btn(parent: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(120, 60)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _sb(fill: Color, border: Color, bw: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fill
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(14)
	s.set_content_margin_all(8)
	return s


func _swatch(parent: Control, text: String, fill: Color, border: Color, group: ButtonGroup, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.button_group = group
	b.custom_minimum_size = Vector2(130, 64)
	for c in ["font_color", "font_pressed_color", "font_hover_color", "font_hover_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(c, Color("2b211a"))
	for st in ["normal", "hover", "focus"]:
		b.add_theme_stylebox_override(st, _sb(fill, border, 4))
	for st in ["pressed", "hover_pressed"]:
		b.add_theme_stylebox_override(st, _sb(fill, Color.WHITE, 8))
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _build_popup() -> void:
	popup = Control.new()
	popup.set_anchors_preset(Control.PRESET_FULL_RECT)
	popup.visible = false
	root_ui.add_child(popup)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	popup.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	popup.add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var m := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 24)
	panel.add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	m.add_child(v)
	popup_title = Label.new()
	popup_title.add_theme_font_size_override("font_size", 34)
	popup_title.add_theme_color_override("font_color", Color("ffd9a0"))
	popup_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	popup_title.custom_minimum_size = Vector2(740, 0)
	v.add_child(popup_title)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(760, 280)
	v.add_child(sc)
	popup_body = Label.new()
	popup_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	popup_body.custom_minimum_size = Vector2(740, 0)
	sc.add_child(popup_body)
	_btn(v, "Закрыть", _close_popup)


func _show_popup(t: String, b: String) -> void:
	popup_title.text = t
	popup_body.text = b
	popup.visible = true
	modal_open = true
	pressing = false
	drag_mode = "none"


func _close_popup() -> void:
	popup.visible = false
	modal_open = false


func _open_diary() -> void:
	var s := ""
	for i in memories.size():
		if i in unlocked:
			s += "— " + str(memories[i]["title"]) + "\n" + str(memories[i]["text"]) + "\n\n"
		else:
			s += "— ???\n\n"
	_show_popup("Дневник дома (%d/%d)" % [unlocked.size(), memories.size()], s)


func _update_progress() -> void:
	progress_label.text = "Воспоминания: %d/%d" % [unlocked.size(), memories.size()]


func _pick_wallpaper(i: int) -> void:
	sel_wallpaper = i


func _pick_paint(i: int) -> void:
	sel_paint = i


func _set_tool(id: String) -> void:
	cur_tool = id
	wire_src = null
	wp_box.visible = id == "wallpaper"
	paint_box.visible = id == "paint"
	move_box.visible = id == "move"
	match id:
		"brush":
			hint_label.text = "Кисть: проведите по пыли на полу. Тяните по стене, чтобы вращать камеру"
		"wallpaper":
			hint_label.text = "Обои: выберите узор и коснитесь стены"
		"paint":
			hint_label.text = "Краска: выберите цвет и коснитесь мебели"
		"move":
			hint_label.text = "Мебель: перетащите предмет. «Повернуть» крутит выбранный"
		"wire":
			hint_label.text = "Свет: коснитесь лампы, затем розетки на стене"


func toast(t: String) -> void:
	toast_label.text = t
	toast_label.modulate.a = 1.0
	if toast_tween:
		toast_tween.kill()
	toast_tween = create_tween()
	toast_tween.tween_interval(2.4)
	toast_tween.tween_property(toast_label, "modulate:a", 0.0, 0.6)


# ============================================================ СОХРАНЕНИЕ

func _save() -> void:
	var f := FileAccess.open("user://save.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"memories": unlocked}))


func _load_save() -> void:
	if not FileAccess.file_exists("user://save.json"):
		return
	var f := FileAccess.open("user://save.json", FileAccess.READ)
	if f == null:
		return
	var data = JSON.parse_string(f.get_as_text())
	if data is Dictionary and data.has("memories"):
		unlocked.clear()
		for v in data["memories"]:
			unlocked.append(int(v))
