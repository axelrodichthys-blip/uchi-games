extends Node3D
## 歩き・走りのアニメ中に、足首の骨がどの高さを通るかを実測する。
## traveler_rig.gd の FOOT_DOWN / FOOT_UP（接地の判定値）を決めるために使う。
##   godot --headless --path game res://tools/foot_probe.tscn
## 身長やモデルを変えたら実行し直すこと（walk_test の「足音の回数」が NG になったら大抵これ）。

const MODEL := preload("res://assets/traveler_cloth.glb")
const FOOT_BONES := ["mixamorig_LeftFoot", "mixamorig_RightFoot"]
const CLIPS := ["Idle", "Walking", "Running", "WalkingBackwards"]

func _ready() -> void:
	var model: Node3D = MODEL.instantiate()
	add_child(model)
	var skel: Skeleton3D = model.find_child("Skeleton3D", true, false)
	var player: AnimationPlayer = model.find_child("AnimationPlayer", true, false)
	var idx: Array[int] = []
	for n in FOOT_BONES:
		idx.append(skel.find_bone(n))
	print("[foot_probe] 足首の骨: %s" % str(idx))
	for clip in CLIPS:
		if not player.has_animation(clip):
			continue
		var anim := player.get_animation(clip)
		var lo := [INF, INF]
		var hi := [-INF, -INF]
		var steps := 60
		for i in steps:
			var t: float = anim.length * float(i) / float(steps)
			player.play(clip)
			player.seek(t, true)
			player.advance(0.0)
			await get_tree().process_frame
			for k in idx.size():
				var y: float = (skel.global_transform * skel.get_bone_global_pose(idx[k])).origin.y - global_position.y
				lo[k] = minf(lo[k], y)
				hi[k] = maxf(hi[k], y)
		print("[foot_probe] %-18s 左 %.3f〜%.3f m / 右 %.3f〜%.3f m"
			% [clip, lo[0], hi[0], lo[1], hi[1]])
	print("[foot_probe] 目安: FOOT_DOWN は「一番低い所 + 少し」、FOOT_UP は「一番高い所 - 少し」")
	get_tree().quit(0)
