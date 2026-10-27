# DawnMesh — Dawn Voice icon

`dawnmesh-icon.png` is the selected original artwork: a rising sun with three
voice bars on navy. Android and iOS use the same image in every appearance.
`google-play-icon.png` is its opaque 512px store export.

Regenerate with `SHARP_MODULE=/path/to/sharp node scripts/generate-app-icons.cjs`.
The optional first argument selects a repository root. This updates all Android
legacy densities, the adaptive bitmap, every named iOS AppIcon catalog entry,
all launch-image scales and the store icon. Android themed launchers use the
matching monochrome vector in `drawable/ic_launcher_monochrome.xml`.

Android adaptive layers reserve an 18dp inset in the 108dp viewport, so the
visible 72dp launcher region matches the iOS full-bleed composition. Day/night
and round/adaptive variants share the artwork. Keep this source and generator
identical in both repositories; candidate files are not runtime assets.
