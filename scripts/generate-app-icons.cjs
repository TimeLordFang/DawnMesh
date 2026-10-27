#!/usr/bin/env node
// Reproducible platform exports from the selected, full-bleed brand artwork.
const fs = require('node:fs/promises');
const path = require('node:path');
const sharp = require(process.env.SHARP_MODULE || 'sharp');
const root = path.resolve(process.argv[2] || path.join(__dirname, '..'));
const brand = path.join(root, 'assets/branding/dawnmesh-icon.png');
async function render(destination, size, rounded = false) {
  await fs.mkdir(path.dirname(destination), { recursive: true });
  let image = sharp(brand).resize(size, size);
  if (rounded) {
    const mask = Buffer.from(`<svg width="${size}" height="${size}"><rect width="${size}" height="${size}" rx="${size * .22}" fill="white"/></svg>`);
    image = image.ensureAlpha().composite([{ input: mask, blend: 'dest-in' }]);
  } else image = image.removeAlpha();
  await image.png().toFile(destination);
}
async function main() {
  const android = path.join(root, 'android/app/src/main/res');
  if (await fs.stat(android).catch(() => null)) {
    for (const [density, size] of Object.entries({mdpi:48,hdpi:72,xhdpi:96,xxhdpi:144,xxxhdpi:192})) {
      await render(path.join(android, `mipmap-${density}/ic_launcher.png`), size, true);
    }
    await render(path.join(android, 'drawable-nodpi/dawnmesh_icon.png'), 1024);
  }
  const assets = path.join(root, 'ios/Runner/Assets.xcassets');
  const ios = path.join(assets, 'AppIcon.appiconset');
  if (await fs.stat(ios).catch(() => null)) {
    const catalog = JSON.parse(await fs.readFile(path.join(ios, 'Contents.json'), 'utf8'));
    const seen = new Set();
    for (const entry of catalog.images) {
      if (!entry.filename || seen.has(entry.filename)) continue;
      seen.add(entry.filename);
      const size = Number(entry.size.split('x')[0]) * Number((entry.scale || '1x').replace('x',''));
      await render(path.join(ios, entry.filename), size);
    }
    for (const [suffix, scale] of [['',1],['@2x',2],['@3x',3]]) {
      await render(path.join(assets, `LaunchImage.imageset/LaunchImage${suffix}.png`), 96 * scale);
    }
  }
  await render(path.join(root, 'assets/branding/google-play-icon.png'), 512);
}
main().catch(error => { console.error(error); process.exitCode = 1; });
