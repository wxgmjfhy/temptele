"""Build and validate a textured asset with Blender's real background renderer."""

import json
import struct
import sys
from pathlib import Path

import bpy


output = Path(sys.argv[sys.argv.index("--") + 1])
output.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=False)
scene = bpy.context.scene
cube = bpy.data.objects["Cube"]

texture = bpy.data.images.new("Color tiles", width=2, height=2, alpha=True)
texture.pixels = [
    0.9, 0.02, 0.04, 1.0,
    0.04, 0.6, 0.03, 1.0,
    0.04, 0.06, 0.9, 1.0,
    0.7, 0.6, 0.04, 1.0,
]
texture.pack()
material = bpy.data.materials.new("Tile material")
material.use_nodes = True
image_node = material.node_tree.nodes.new("ShaderNodeTexImage")
image_node.image = texture
shader = material.node_tree.nodes.get("Principled BSDF")
material.node_tree.links.new(image_node.outputs["Color"], shader.inputs["Base Color"])
cube.data.materials.clear()
cube.data.materials.append(material)

scene.render.engine = "CYCLES"
scene.cycles.device = "CPU"
scene.cycles.samples = 2
scene.cycles.use_denoising = False
scene.render.resolution_x = 128
scene.render.resolution_y = 96
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
scene.render.filepath = str(output / "blender.png")
bpy.ops.render.render(write_still=True)

preview = bpy.data.images.load(str(output / "blender.png"), check_existing=False)
assert tuple(preview.size) == (128, 96)
assert len(set(preview.pixels[:][::4])) > 10, "Preview should contain a rendered scene"
bpy.data.images.remove(preview)

glb = output / "asset.glb"
bpy.ops.export_scene.gltf(filepath=str(glb), export_format="GLB")
data = glb.read_bytes()
magic, version, total_length, json_length, chunk_type = struct.unpack_from("<4sIII4s", data)
assert (magic, version, total_length, chunk_type) == (b"glTF", 2, len(data), b"JSON")
document = json.loads(data[20:20 + json_length])
assert document["meshes"] and document["images"] and document["textures"]
positions = document["meshes"][0]["primitives"][0]["attributes"]["POSITION"]
accessor = document["accessors"][positions]
assert accessor["min"] == [-1, -1, -1] and accessor["max"] == [1, 1, 1]

blend = output / "asset.blend"
bpy.ops.wm.save_as_mainfile(filepath=str(blend))
bpy.ops.wm.open_mainfile(filepath=str(blend), use_scripts=False)
assert "Cube" in bpy.data.objects
assert bpy.data.images["Color tiles"].packed_file
print("BLENDER_OK 128x96 PNG, textured GLB, reopened blend", flush=True)
