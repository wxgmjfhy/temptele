"""Export a plate and verify the STEP round trip independently of its mesh."""

import math
import sys
from pathlib import Path

import cadquery as cq


output = Path(sys.argv[1])
output.mkdir(parents=True, exist_ok=True)
plate = cq.Workplane("XY").box(20, 30, 5).faces(">Z").workplane().hole(6)
step = output / "plate.step"
stl = output / "plate.stl"
cq.exporters.export(plate, str(step))
cq.exporters.export(plate, str(stl))

shape = cq.importers.importStep(str(step)).solids().val()
assert shape.isValid() and len(shape.Solids()) == 1
bounds = shape.BoundingBox()
assert all(
    math.isclose(measured, expected, abs_tol=1e-6)
    for measured, expected in zip((bounds.xlen, bounds.ylen, bounds.zlen), (20, 30, 5))
)
assert math.isclose(shape.Volume(), (20 * 30 - math.pi * 3**2) * 5, abs_tol=1e-6)
assert stl.stat().st_size > 84
print(f"CADQUERY_OK {cq.__version__}, STEP/STL, volume {shape.Volume():.6f} mm³", flush=True)
