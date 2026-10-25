class_name MeshBuilder
## Процедурные меши: «надувные» скруглённые боксы (камеры ПВХ 0.35 мм),
## крылья из перьев-эллипсоидов, деревья/камни для скаттера.
## Все меши строятся кодом один раз и кэшируются — ассетов-дублей нет.

static var _cache: Dictionary = {}

## Скруглённый бокс: подразделяет BoxMesh и «надувает» вершины к форме
## со скруглёнными углами радиуса r. Нормали — аналитические.
static func rounded_box(size: Vector3, radius: float, subdiv: int = 6) -> ArrayMesh:
	var key: String = "rbox_%s_%.2f_%d" % [str(size), radius, subdiv]
	if _cache.has(key):
		return _cache[key] as ArrayMesh
	var box := BoxMesh.new()
	box.size = size
	box.subdivide_width = subdiv
	box.subdivide_height = subdiv
	box.subdivide_depth = subdiv
	var mdt := MeshDataTool.new()
	mdt.create_from_surface(box, 0)
	var half: Vector3 = size * 0.5
	var r: float = clampf(radius, 0.01, minf(half.x, minf(half.y, half.z)) - 0.001)
	var inner: Vector3 = half - Vector3(r, r, r)
	for i: int in mdt.get_vertex_count():
		var p: Vector3 = mdt.get_vertex(i)
		var c: Vector3 = p.clamp(-inner, inner)
		var d: Vector3 = p - c
		if d.length() > 0.0001:
			var n: Vector3 = d.normalized()
			mdt.set_vertex(i, c + n * r)
			mdt.set_vertex_normal(i, n)
	var mesh := ArrayMesh.new()
	mdt.commit_to_surface(mesh)
	_cache[key] = mesh
	return mesh

static func ellipsoid(radius: float, scale_v: Vector3, rings: int = 16) -> SphereMesh:
	var key: String = "ell_%.2f_%d" % [radius, rings]
	if _cache.has(key):
		return _cache[key] as SphereMesh
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	s.radial_segments = rings
	s.rings = rings / 2
	_cache[key] = s
	return s

## Надувное ангельское крыло: веер из эллипсоидов-«перьев» + основание.
## span — размах одного крыла от основания до кончика (м).
## Крыло направлено +X, толщина по Z. Зеркалится масштабом x=-1 у владельца.
static func wing_mesh(span: float, chord: float, thickness: float) -> ArrayMesh:
	var key: String = "wing_%.1f_%.1f_%.1f" % [span, chord, thickness]
	if _cache.has(key):
		return _cache[key] as ArrayMesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var base := SphereMesh.new()
	base.radius = 0.5
	base.height = 1.0
	base.radial_segments = 12
	base.rings = 6
	var feathers: int = 6
	for i: int in feathers:
		var t: float = float(i) / float(feathers - 1)
		var fx: float = lerpf(span * 0.12, span * 0.88, t)
		var fy: float = sin(t * PI * 0.55) * span * 0.18 - t * chord * 0.22
		var flen: float = lerpf(chord * 0.75, chord * 1.25, t)
		var fw: float = span * lerpf(0.13, 0.09, t)
		var xf := Transform3D()
		xf = xf.rotated(Vector3.BACK, lerpf(-0.35, 0.5, t))
		xf.origin = Vector3(fx, fy, 0.0)
		xf.basis = xf.basis.scaled(Vector3(fw, flen, thickness))
		st.append_from(base, 0, xf)
	# Плечо крыла у основания
	var shoulder := Transform3D(
		Basis.from_scale(Vector3(span * 0.55, chord * 0.8, thickness * 1.2)),
		Vector3(span * 0.2, chord * 0.08, 0.0))
	st.append_from(base, 0, shoulder)
	var mesh: ArrayMesh = st.commit()
	_cache[key] = mesh
	return mesh

## Юбка/подол: усечённый конус без крышек (платье горничной, юбка Бога).
static func skirt_mesh(top_r: float, bottom_r: float, height_m: float) -> CylinderMesh:
	var key: String = "skirt_%.2f_%.2f_%.2f" % [top_r, bottom_r, height_m]
	if _cache.has(key):
		return _cache[key] as CylinderMesh
	var c := CylinderMesh.new()
	c.top_radius = top_r
	c.bottom_radius = bottom_r
	c.height = height_m
	c.radial_segments = 24
	c.rings = 2
	c.cap_top = false
	c.cap_bottom = false
	_cache[key] = c
	return c

static func capsule(r: float, h: float) -> CapsuleMesh:
	var key: String = "cap_%.2f_%.2f" % [r, h]
	if _cache.has(key):
		return _cache[key] as CapsuleMesh
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = h
	c.radial_segments = 12
	c.rings = 4
	_cache[key] = c
	return c

static func box(size: Vector3) -> BoxMesh:
	var key: String = "box_" + str(size)
	if _cache.has(key):
		return _cache[key] as BoxMesh
	var b := BoxMesh.new()
	b.size = size
	_cache[key] = b
	return b

static func cylinder(top_r: float, bottom_r: float, h: float, seg: int = 16) -> CylinderMesh:
	var key: String = "cyl_%.2f_%.2f_%.2f_%d" % [top_r, bottom_r, h, seg]
	if _cache.has(key):
		return _cache[key] as CylinderMesh
	var c := CylinderMesh.new()
	c.top_radius = top_r
	c.bottom_radius = bottom_r
	c.height = h
	c.radial_segments = seg
	c.rings = 1
	_cache[key] = c
	return c

static func cone(r: float, h: float, seg: int = 16) -> CylinderMesh:
	return cylinder(0.02, r, h, seg)

## Сосна для скаттера: ствол + 3 яруса кроны (2 поверхности: кора/хвоя).
static func pine_tree_mesh() -> ArrayMesh:
	if _cache.has("pine_tree"):
		return _cache["pine_tree"] as ArrayMesh
	var mesh := ArrayMesh.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(GameMaterials.bark())
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.18
	trunk.bottom_radius = 0.3
	trunk.height = 3.0
	trunk.radial_segments = 8
	st.append_from(trunk, 0, Transform3D(Basis.IDENTITY, Vector3(0, 1.5, 0)))
	st.commit(mesh)
	var st2 := SurfaceTool.new()
	st2.begin(Mesh.PRIMITIVE_TRIANGLES)
	st2.set_material(GameMaterials.pine_green())
	for i: int in 3:
		var t: float = float(i)
		var c := CylinderMesh.new()
		c.top_radius = 0.05
		c.bottom_radius = lerpf(2.2, 0.9, t / 2.0)
		c.height = 3.2
		c.radial_segments = 10
		st2.append_from(c, 0, Transform3D(Basis.IDENTITY, Vector3(0, 3.4 + t * 1.9, 0)))
	st2.commit(mesh)
	_cache["pine_tree"] = mesh
	return mesh

## Мёртвое дерево (хоррор-акцент ночной долины).
static func dead_tree_mesh() -> ArrayMesh:
	if _cache.has("dead_tree"):
		return _cache["dead_tree"] as ArrayMesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.12
	trunk.bottom_radius = 0.35
	trunk.height = 5.0
	trunk.radial_segments = 7
	st.append_from(trunk, 0, Transform3D(Basis.IDENTITY, Vector3(0, 2.5, 0)))
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	for i: int in 7:
		var br := CylinderMesh.new()
		br.top_radius = 0.02
		br.bottom_radius = 0.08
		br.height = rng.randf_range(1.4, 2.6)
		br.radial_segments = 5
		var xf := Transform3D()
		xf = xf.rotated(Vector3.UP, rng.randf() * TAU)
		xf = xf.rotated(Vector3.RIGHT, rng.randf_range(0.6, 1.2))
		xf.origin = Vector3(0, rng.randf_range(3.0, 4.8), 0) + xf.basis.y * br.height * 0.4
		st.append_from(br, 0, xf)
	var mesh: ArrayMesh = st.commit()
	_cache["dead_tree"] = mesh
	return mesh

## Камень: сплюснутая сфера с плоской шейдинг-огранкой.
static func rock_mesh() -> ArrayMesh:
	if _cache.has("rock"):
		return _cache["rock"] as ArrayMesh
	var s := SphereMesh.new()
	s.radius = 1.0
	s.height = 1.4
	s.radial_segments = 9
	s.rings = 5
	var mdt := MeshDataTool.new()
	mdt.create_from_surface(s, 0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	for i: int in mdt.get_vertex_count():
		var p: Vector3 = mdt.get_vertex(i)
		var k: float = rng.randf_range(0.8, 1.15)
		mdt.set_vertex(i, Vector3(p.x * k, p.y * 0.75, p.z * (2.0 - k)))
	var mesh := ArrayMesh.new()
	mdt.commit_to_surface(mesh)
	var st := SurfaceTool.new()
	st.create_from(mesh, 0)
	st.generate_normals()
	mesh = st.commit()
	_cache["rock"] = mesh
	return mesh
