class_name HexSphere
extends RefCounted
## 구 위의 육각 타일 격자 (골드버그 다면체).
## 정이십면체를 세분한 뒤 그 쌍대를 취한다. 꼭짓점 하나가 타일 하나가 되고,
## 원래 정이십면체의 꼭짓점 12개는 오각형, 나머지는 모두 육각형이다.

var level: int = 0
var count: int = 0
## 타일 중심 (단위 벡터)
var centers := PackedVector3Array()
## 타일 i의 이웃/모서리는 nb_list[nb_offsets[i] .. nb_offsets[i+1]) 에 있다.
## 모서리 k 와 k+1 사이의 변을 공유하는 이웃이 nb_list[off + k] 이다.
## 모서리는 바깥에서 볼 때 반시계 방향으로 정렬되어 있다.
var nb_offsets := PackedInt32Array()
var nb_list := PackedInt32Array()
var corner_list := PackedVector3Array()
## 이웃 타일 사이 평균 각거리 (라디안)
var spacing: float = 0.0


func degree(i: int) -> int:
	return nb_offsets[i + 1] - nb_offsets[i]


func build(subdiv: int) -> void:
	level = subdiv
	var t: float = (1.0 + sqrt(5.0)) / 2.0
	var verts: Array[Vector3] = [
		Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
		Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
		Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)]
	for k in verts.size():
		verts[k] = verts[k].normalized()
	var faces := PackedInt32Array([
		0, 11, 5, 0, 5, 1, 0, 1, 7, 0, 7, 10, 0, 10, 11,
		1, 5, 9, 5, 11, 4, 11, 10, 2, 10, 7, 6, 7, 1, 8,
		3, 9, 4, 3, 4, 2, 3, 2, 6, 3, 6, 8, 3, 8, 9,
		4, 9, 5, 2, 4, 11, 6, 2, 10, 8, 6, 7, 9, 8, 1])

	for _l in subdiv:
		var cache := {}
		var nf := PackedInt32Array()
		nf.resize(faces.size() * 4)
		var w: int = 0
		for f in range(0, faces.size(), 3):
			var a: int = faces[f]
			var b: int = faces[f + 1]
			var c: int = faces[f + 2]
			var ab: int = _mid(a, b, verts, cache)
			var bc: int = _mid(b, c, verts, cache)
			var ca: int = _mid(c, a, verts, cache)
			for v in [a, ab, ca, b, bc, ab, c, ca, bc, ab, bc, ca]:
				nf[w] = v
				w += 1
		faces = nf

	count = verts.size()
	centers.resize(count)
	for k in count:
		centers[k] = verts[k]

	var face_count: int = faces.size() / 3
	var face_center := PackedVector3Array()
	face_center.resize(face_count)
	var vf: Array = []
	vf.resize(count)
	for k in count:
		vf[k] = PackedInt32Array()
	for f in face_count:
		var a: int = faces[f * 3]
		var b: int = faces[f * 3 + 1]
		var c: int = faces[f * 3 + 2]
		face_center[f] = (verts[a] + verts[b] + verts[c]).normalized()
		vf[a].append(f)
		vf[b].append(f)
		vf[c].append(f)

	nb_offsets.resize(count + 1)
	nb_list = PackedInt32Array()
	corner_list = PackedVector3Array()
	var total_sp: float = 0.0
	var total_n: int = 0
	for v in count:
		var nrm: Vector3 = verts[v]
		var ax: Vector3 = nrm.cross(Vector3.UP)
		if ax.length_squared() < 1e-6:
			ax = nrm.cross(Vector3.RIGHT)
		ax = ax.normalized()
		var bx: Vector3 = nrm.cross(ax)
		var list: PackedInt32Array = vf[v]
		var arr: Array = []
		for f in list:
			var d: Vector3 = face_center[f] - nrm
			arr.append([atan2(d.dot(bx), d.dot(ax)), f])
		arr.sort_custom(func(p, q): return p[0] < q[0])
		nb_offsets[v] = nb_list.size()
		var m: int = arr.size()
		for k in m:
			var f0: int = arr[k][1]
			var f1: int = arr[(k + 1) % m][1]
			corner_list.append(face_center[f0])
			var shared: int = -1
			for s in 3:
				var cand: int = faces[f0 * 3 + s]
				if cand == v:
					continue
				if faces[f1 * 3] == cand or faces[f1 * 3 + 1] == cand or faces[f1 * 3 + 2] == cand:
					shared = cand
					break
			nb_list.append(shared)
			total_sp += nrm.angle_to(verts[shared])
			total_n += 1
	nb_offsets[count] = nb_list.size()
	spacing = total_sp / max(total_n, 1)


func _mid(a: int, b: int, verts: Array[Vector3], cache: Dictionary) -> int:
	var key: int = mini(a, b) * 1000000 + maxi(a, b)
	if cache.has(key):
		return cache[key]
	verts.append(((verts[a] + verts[b]) * 0.5).normalized())
	var idx: int = verts.size() - 1
	cache[key] = idx
	return idx


## p 에서 가장 가까운 타일을 start 부터 이웃을 따라 언덕 오르기로 찾는다.
func find_tile(p: Vector3, start: int = 0) -> int:
	var cur: int = clampi(start, 0, count - 1)
	var best: float = centers[cur].dot(p)
	while true:
		var moved := false
		for k in range(nb_offsets[cur], nb_offsets[cur + 1]):
			var j: int = nb_list[k]
			var d: float = centers[j].dot(p)
			if d > best:
				best = d
				cur = j
				moved = true
		if not moved:
			break
	return cur
