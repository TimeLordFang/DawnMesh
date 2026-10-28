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

## App appearance

The shared palette uses navy `#080F39`, orange `#FF7446` and gold `#FFD587`.
The home screen blends indigo through peach and warm gold into ivory, with text
on the left and the sun to the right, clear of Settings. The caption is
“越过地平线，让声音相遇。”; both appearances use the same animated wave style.
Theme values are maintained in `lib/ui/theme/app_theme.dart`.

Modal actions share `DialogActionButton`: 12px corner radius, at least 48px
height, outlined secondary actions, filled primary actions and theme-aware
destructive colors. Creation confirmations say “创建”. Settings remain in one
page; room-specific options appear there while a room is active.

Adaptive PNG layers contain the inset directly, avoiding an extra XML scaling
layer. Verify launcher return animations and small/large text on real devices
using `docs/MANUAL_ACCEPTANCE.md`; component previews do not prove launcher behavior.
