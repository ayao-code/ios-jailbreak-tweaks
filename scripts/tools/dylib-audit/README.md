# Static dylib audit helper

`audit_dylibs.py` was retained from the former TrollFools research session.
It inspects Mach-O metadata without executing, injecting or modifying binaries.

The script is a session-specific source reference: it currently expects an
input manifest containing exactly 209 modules, matching dylibs, a runtime dylib
and an App inventory JSON. Those historical inputs were deleted during cleanup.
This is not a generic audit command that works without preparing new inputs.

Required arguments: `--input`, `--output`, `--runtime`, `--apps`.
Static classifications do not prove runtime compatibility or injection safety.
