# DawnMesh app icons

The light and dark SVGs preserve the paths, colors and gradients from Android's
`drawable/ic_launcher_{background,foreground}.xml` and `drawable-night` variants.
The flat export uses the central 72 × 72 viewport of the 108 × 108 adaptive icon
layers, matching the area displayed by Android launchers. Keep a full opaque
background; each platform applies its own icon mask.

Android continues to use its native adaptive vectors, including the monochrome
themed icon. Its fallback PNGs use a rounded silhouette with transparent corners;
the iOS icon catalog keeps a full opaque square for the system icon mask.
Both use these SVG exports.
The iOS dark appearance uses the same blue night palette as Android.

To regenerate PNGs, install Sharp in a temporary tooling directory and run:

```sh
npm install --prefix /tmp/dawnmesh-icon-tools --no-save sharp
SHARP_MODULE=/tmp/dawnmesh-icon-tools/node_modules/sharp node scripts/generate-app-icons.cjs
```

The generator runs from either mobile repository. Keep the two SVGs and the
generator identical in DawnMesh and DawnMeshIOS when changing the branding.
Sharp is an offline asset tool; it is not an application or CI dependency.
