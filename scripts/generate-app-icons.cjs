#!/usr/bin/env node
// SVG rasterization only; no generated artwork or new app dependencies.
const fs = require('node:fs/promises');
const path = require('node:path');
const sharp = require(process.env.SHARP_MODULE || 'sharp');
const root = path.resolve(__dirname, '..');

async function render(source, destination, size, legacyAndroid = false) {
  let icon = sharp(source, { density: 384 }).resize(size, size);
  if (legacyAndroid) {
    const mask = Buffer.from(`<svg width="${size}" height="${size}"><rect width="${size}" height="${size}" rx="${size * 0.22}" fill="white"/></svg>`);
    icon = icon.ensureAlpha().composite([{ input: mask, blend: 'dest-in' }]);
  } else {
    icon = icon.removeAlpha();
  }
  await icon.png().toFile(destination);
}

async function main() {
  const light = path.join(root, 'assets/branding/dawnmesh-icon-light.svg');
  const dark = path.join(root, 'assets/branding/dawnmesh-icon-dark.svg');
  const android = path.join(root, 'android/app/src/main/res');
  const ios = path.join(root, 'ios/Runner/Assets.xcassets/AppIcon.appiconset');
  if (await fs.stat(android).catch(() => null)) {
    for (const [density, size] of Object.entries({
      mdpi: 48, hdpi: 72, xhdpi: 96, xxhdpi: 144, xxxhdpi: 192,
    })) {
      await render(light, path.join(android, `mipmap-${density}/ic_launcher.png`), size, true);
    }
  }
  if (await fs.stat(ios).catch(() => null)) {
    const catalog = JSON.parse(await fs.readFile(path.join(ios, 'Contents.json'), 'utf8'));
    const seen = new Set();
    for (const entry of catalog.images) {
      if (!entry.filename || seen.has(entry.filename)) continue;
      seen.add(entry.filename);
      const size = Number(entry.size.split('x')[0]) * Number((entry.scale || '1x').replace('x', ''));
      const isDark = entry.appearances?.some(a => a.appearance === 'luminosity' && a.value === 'dark');
      await render(isDark ? dark : light, path.join(ios, entry.filename), size);
    }
  }
}

main().catch(error => { console.error(error); process.exitCode = 1; });
