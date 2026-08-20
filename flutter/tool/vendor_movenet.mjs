import { createHash } from "node:crypto";
import { mkdir, readFile, rename, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { build } from "esbuild";

const toolDirectory = path.dirname(fileURLToPath(import.meta.url));
const webDirectory = path.resolve(
  toolDirectory,
  "../apps/kinetic_field_web/web",
);
const modelDirectory = path.join(webDirectory, "movenet/model");
const outputFile = path.join(webDirectory, "movenet/kinetic_field_movenet.js");
const refreshModel = process.argv.includes("--refresh-model");

const officialModelBase =
  "https://raw.githubusercontent.com/tensorflow/tfjs-examples/master/" +
  "react-native/pose-detection/offline_model";

const modelFiles = [
  {
    name: "model.json",
    bytes: 168013,
    sha256: "c65a3447162efa0c42af29498a4b151f4415b36ff3ae6fae2b28a32e840dcbfb",
  },
  {
    name: "group1-shard1of2.bin",
    bytes: 4194304,
    sha256: "b42c3232bf13b0efc691d3f0693dd3fc74404f709b1deee0a271828af6dbbea2",
  },
  {
    name: "group1-shard2of2.bin",
    bytes: 455912,
    sha256: "8253ab965aa3122c08f331777ca395ce9ca19bb9e7cb278b99de1c46dbdeb6dc",
  },
];

function digest(contents) {
  return createHash("sha256").update(contents).digest("hex");
}

async function verifiedContents(file) {
  const destination = path.join(modelDirectory, file.name);
  let contents = null;

  if (!refreshModel) {
    try {
      contents = await readFile(destination);
    } catch {
      // A missing checked-in asset is restored from the official source below.
    }
  }

  if (contents === null) {
    const response = await fetch(`${officialModelBase}/${file.name}`);
    if (!response.ok) {
      throw new Error(`Could not download ${file.name}: HTTP ${response.status}`);
    }
    contents = Buffer.from(await response.arrayBuffer());
  }

  const actualDigest = digest(contents);
  if (contents.byteLength !== file.bytes || actualDigest !== file.sha256) {
    throw new Error(
      `${file.name} failed integrity verification ` +
      `(${contents.byteLength} bytes, sha256 ${actualDigest}).`,
    );
  }

  const temporary = `${destination}.tmp`;
  await writeFile(temporary, contents);
  await rename(temporary, destination);
  console.log(`[movenet] verified ${file.name} (${file.bytes} bytes)`);
  return contents;
}

await mkdir(modelDirectory, { recursive: true });
const verified = new Map();
for (const file of modelFiles) {
  verified.set(file.name, await verifiedContents(file));
}

const manifest = JSON.parse(verified.get("model.json").toString("utf8"));
const shardPaths = manifest.weightsManifest?.flatMap((group) => group.paths) ?? [];
const expectedShards = modelFiles.slice(1).map((file) => file.name);
if (
  manifest.format !== "graph-model" ||
  JSON.stringify(shardPaths) !== JSON.stringify(expectedShards)
) {
  throw new Error("MoveNet model.json does not reference the verified local shards.");
}

const result = await build({
  entryPoints: [path.join(toolDirectory, "movenet_bridge_entry.js")],
  outfile: outputFile,
  bundle: true,
  minify: true,
  platform: "browser",
  format: "iife",
  target: ["es2020"],
  legalComments: "external",
  sourcemap: false,
  metafile: true,
  logLevel: "warning",
  plugins: [
    {
      name: "movenet-unused-peer-stubs",
      setup(context) {
        context.onResolve(
          {
            filter: /^(@mediapipe\/pose|@tensorflow\/tfjs-backend-webgpu)$/,
          },
          () => ({
            path: path.join(toolDirectory, "movenet_unused_peer_stubs.js"),
          }),
        );
      },
    },
  ],
  banner: {
    js: "/* Local Kinetic Field MoveNet bridge. See THIRD_PARTY_NOTICES.md. */",
  },
});

const generatedBundle = await readFile(outputFile, "utf8");
const bundle = generatedBundle.replace(/[\t ]+$/gm, "");
if (bundle !== generatedBundle) {
  await writeFile(outputFile, bundle);
}
for (const forbidden of ["cdn.jsdelivr.net", "unpkg.com"]) {
  if (bundle.includes(forbidden)) {
    throw new Error(`The browser bundle contains a forbidden CDN reference: ${forbidden}`);
  }
}
if (!bundle.includes("movenet/model/model.json")) {
  throw new Error("The browser bundle does not contain the local model path.");
}

const output = Object.entries(result.metafile.outputs).find(
  ([filePath]) => path.resolve(filePath) === outputFile,
)?.[1];
if (!output) throw new Error("esbuild did not report the expected browser bundle.");
console.log(`[movenet] built ${path.relative(webDirectory, outputFile)} (${output.bytes} bytes)`);
