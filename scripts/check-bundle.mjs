import { readdir, readFile } from "node:fs/promises";
import path from "node:path";
import { gzipSync } from "node:zlib";

const KIB = 1024;
const assetsDirectory = path.resolve("dist/assets");

const limits = {
  totalJavaScriptRaw: 800 * KIB,
  totalJavaScriptGzip: 220 * KIB,
  largestJavaScriptRaw: 550 * KIB,
  largestJavaScriptGzip: 145 * KIB,
  totalStylesGzip: 20 * KIB,
};

async function walk(directory) {
  const entries = await readdir(directory, { withFileTypes: true });
  const files = await Promise.all(
    entries.map(async (entry) => {
      const absolutePath = path.join(directory, entry.name);
      return entry.isDirectory() ? walk(absolutePath) : absolutePath;
    }),
  );
  return files.flat();
}

function kib(bytes) {
  return `${(bytes / KIB).toFixed(1)} KiB`;
}

function largest(items, key) {
  return items.reduce(
    (current, item) => (item[key] > current[key] ? item : current),
    items[0],
  );
}

let assetPaths;
try {
  assetPaths = await walk(assetsDirectory);
} catch (error) {
  console.error("[bundle] Build assets are missing. Run the production build first.");
  throw error;
}

const assets = await Promise.all(
  assetPaths.map(async (filePath) => {
    const contents = await readFile(filePath);
    return {
      filePath,
      extension: path.extname(filePath),
      raw: contents.byteLength,
      gzip: gzipSync(contents, { level: 9 }).byteLength,
    };
  }),
);

const javascript = assets.filter((asset) => asset.extension === ".js");
const styles = assets.filter((asset) => asset.extension === ".css");

if (javascript.length === 0) {
  throw new Error("[bundle] No JavaScript assets were produced.");
}

const largestJavaScriptRaw = largest(javascript, "raw");
const largestJavaScriptGzip = largest(javascript, "gzip");
const totals = {
  javascriptRaw: javascript.reduce((sum, asset) => sum + asset.raw, 0),
  javascriptGzip: javascript.reduce((sum, asset) => sum + asset.gzip, 0),
  stylesGzip: styles.reduce((sum, asset) => sum + asset.gzip, 0),
};

const checks = [
  ["total JavaScript raw", totals.javascriptRaw, limits.totalJavaScriptRaw],
  ["total JavaScript gzip", totals.javascriptGzip, limits.totalJavaScriptGzip],
  [
    `largest JavaScript raw (${path.basename(largestJavaScriptRaw.filePath)})`,
    largestJavaScriptRaw.raw,
    limits.largestJavaScriptRaw,
  ],
  [
    `largest JavaScript gzip (${path.basename(largestJavaScriptGzip.filePath)})`,
    largestJavaScriptGzip.gzip,
    limits.largestJavaScriptGzip,
  ],
  ["total CSS gzip", totals.stylesGzip, limits.totalStylesGzip],
];

let failed = false;
for (const [label, actual, limit] of checks) {
  const status = actual <= limit ? "ok" : "over";
  console.log(`[bundle] ${status.padEnd(4)} ${label}: ${kib(actual)} / ${kib(limit)}`);
  failed ||= actual > limit;
}

if (failed) {
  console.error("[bundle] Production assets exceed the checked-in budget.");
  process.exitCode = 1;
}
