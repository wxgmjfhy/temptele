extends Node3D


func _ready() -> void:
	var packed := load("res://asset.glb") as PackedScene
	if packed == null:
		fail("GLB did not import as a PackedScene")
		return
	var model := packed.instantiate()
	add_child(model)
	var mesh := find_mesh(model)
	if mesh == null or mesh.mesh.get_surface_count() == 0:
		fail("The imported scene has no mesh")
		return
	var material := mesh.get_active_material(0) as StandardMaterial3D
	if material == null or material.albedo_texture == null:
		fail("Imported surface does not use the exported texture")
		return
	if not mesh.mesh.get_aabb().size.is_equal_approx(Vector3(2, 2, 2)):
		fail("Imported mesh dimensions are different from the fixture")
		return

	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2, 2, 2)
	collision.shape = box
	body.add_child(collision)
	add_child(body)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var ray := PhysicsRayQueryParameters3D.create(Vector3(0, 0, 5), Vector3(0, 0, -5))
	if get_world_3d().direct_space_state.intersect_ray(ray).get("collider") != body:
		fail("Physics ray did not hit the test box")
		return

	if "--capture" in OS.get_cmdline_user_args():
		var camera := Camera3D.new()
		add_child(camera)
		camera.position = Vector3(3, 2, 4)
		camera.look_at(Vector3.ZERO)
		camera.current = true
		var light := DirectionalLight3D.new()
		add_child(light)
		light.rotation_degrees = Vector3(-40, 25, 0)
		light.light_energy = 2.0
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		if image == null or image.get_size() != Vector2i(128, 96):
			fail("Viewport image has the wrong resolution")
			return
		var corner := image.get_pixel(0, 0)
		var center := image.get_pixel(64, 48)
		if corner.is_equal_approx(center) or image.save_png("/out/godot.png") != OK:
			fail("No valid rendered foreground in the viewport")
			return
		print("GODOT_PIXELS_OK ", RenderingServer.get_video_adapter_name())

	print("GODOT_OK textured GLB, dimensions, ray hit")
	get_tree().quit(0)


func find_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	for child in node.get_children():
		var mesh := find_mesh(child)
		if mesh != null:
			return mesh
	return null


func fail(message: String) -> void:
	push_error(message)
	get_tree().quit(1)
