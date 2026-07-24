import { lstat, readdir, readFile, stat } from 'node:fs/promises';
import { basename, join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

export const RELEASE_LIMIT_BYTES = 100 * 1024 * 1024;
const DEFAULT_DIST = fileURLToPath(new URL('../dist/', import.meta.url));
const EXPECTED_LEVEL_IMAGES = new Set(
  Array.from({ length: 7 }, (_, index) => `growth/level-${index + 1}.png`),
);
const FORBIDDEN_MARKERS = [
  /NEIS_API_KEY/i,
  /SUPABASE_SERVICE_ROLE_KEY/i,
  /service[_-]?role/i,
  /sk_live_/i,
  /\beval\s*\(/i,
];

function normalizedPath(root, file) {
  return relative(root, file).split('\\').join('/');
}

function excludedFromContentScan(path) {
  const name = basename(path).toLowerCase();
  return path.includes('/docs/')
    || name.endsWith('.map')
    || name.endsWith('.md')
    || name.endsWith('.markdown')
    || name === 'readme'
    || name.startsWith('readme.')
    || name.startsWith('license');
}

async function walk(root) {
  const entries = await readdir(root, { withFileTypes: true });
  const files = [];
  for (const entry of entries) {
    const child = join(root, entry.name);
    if (entry.isSymbolicLink()) {
      throw new Error('Release bundle must not contain symbolic links');
    }
    if (entry.isDirectory()) {
      files.push(...await walk(child));
    } else if (entry.isFile()) {
      files.push(child);
    }
  }
  return files;
}

async function requireDirectory(path) {
  try {
    if (!(await stat(path)).isDirectory()) {
      throw new Error('not a directory');
    }
  } catch {
    throw new Error('Release bundle is missing or is not a directory');
  }
}

async function assertDirectEntry(root, files) {
  const index = join(root, 'index.html');
  if (!files.includes(index) || (await stat(index)).size === 0) {
    throw new Error('Release bundle must include a non-empty index.html entry');
  }

  const html = await readFile(index, 'utf8');
  const assetReferences = [...html.matchAll(/\b(?:src|href)=["']([^"']+)["']/gi)]
    .map((match) => match[1])
    .filter((reference) => !/^(?:https?:|data:|#)/i.test(reference));

  if (assetReferences.length === 0) {
    throw new Error('Release entry must reference at least one direct asset');
  }
  for (const reference of assetReferences) {
    if (!reference.startsWith('/')) {
      throw new Error('Release entry must use direct-root asset URLs');
    }
    const asset = join(root, reference.replace(/^\/+/, '').split(/[?#]/, 1)[0]);
    if (!files.includes(asset)) {
      throw new Error('Release entry references an asset that is not in the bundle');
    }
  }
}

function assertLevelImages(root, files, sizes) {
  const levelFiles = files.filter((file) => /(?:^|\/)level-\d+\.png$/i.test(normalizedPath(root, file)));
  const paths = new Set(levelFiles.map((file) => normalizedPath(root, file)));
  const expectedPresent = [...EXPECTED_LEVEL_IMAGES].every((path) => paths.has(path));
  const nonEmpty = levelFiles.every((file) => sizes.get(file) > 0);

  if (levelFiles.length !== 7 || paths.size !== 7 || !expectedPresent || !nonEmpty) {
    throw new Error('Expected exactly seven non-empty level PNG assets (growth/level-1.png through growth/level-7.png)');
  }
}

async function assertSafeContent(files) {
  for (const file of files) {
    if (excludedFromContentScan(file)) continue;
    const content = await readFile(file);
    const text = content.toString('latin1');
    if (FORBIDDEN_MARKERS.some((marker) => marker.test(text))) {
      throw new Error('Forbidden release marker detected in bundle artifact');
    }
  }
}

export async function verifyRelease(root = DEFAULT_DIST) {
  await requireDirectory(root);
  const files = await walk(root);
  const sizes = new Map();
  let totalBytes = 0;

  for (const file of files) {
    const info = await lstat(file);
    if (!info.isFile()) throw new Error('Release bundle contains an unsupported artifact');
    sizes.set(file, info.size);
    totalBytes += info.size;
  }

  if (totalBytes >= RELEASE_LIMIT_BYTES) {
    throw new Error(`Uncompressed release bundle is ${totalBytes} bytes; it must be below ${RELEASE_LIMIT_BYTES} bytes`);
  }

  await assertDirectEntry(root, files);
  assertLevelImages(root, files, sizes);
  await assertSafeContent(files);

  return { totalBytes, fileCount: files.length, levelImageCount: 7 };
}

async function main() {
  try {
    const result = await verifyRelease();
    console.log(`Release checks passed: ${result.totalBytes} bytes across ${result.fileCount} files`);
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Unknown verification failure';
    console.error(`Release verification failed: ${message}`);
    process.exitCode = 1;
  }
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  await main();
}
