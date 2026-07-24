import { lstat, readdir, readFile } from 'node:fs/promises';
import { extname, join, posix, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

import { AppsInTossBundle } from '@apps-in-toss/ait-format';

export const RELEASE_LIMIT_BYTES = 100 * 1024 * 1024;
const APP_ROOT = fileURLToPath(new URL('../', import.meta.url));
const DEFAULT_WEB_DIST = join(APP_ROOT, 'dist');
const PNG_SIGNATURE = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);
const SAFE_EXTENSIONS = new Set([
  '.bundle', '.css', '.gif', '.html', '.ico', '.jpeg', '.jpg', '.js', '.json',
  '.map', '.md', '.mjs', '.otf', '.png', '.svg', '.txt', '.ttf', '.wasm', '.webp',
  '.woff', '.woff2', '.xml',
]);
const FORBIDDEN_MARKERS = [
  /neis_api_key/i,
  /supabase_service_role_key/i,
  /service[_\s-]?role/i,
  /sb_secret_/i,
  /sk_live_/i,
  /\beval\s*\(/i,
];

function releaseError(message) {
  return new Error(message);
}

function safeEntryPath(name) {
  if (
    typeof name !== 'string'
    || name.length === 0
    || name.includes('\0')
    || name.includes('\\')
    || name.startsWith('/')
    || name.split('/').some((part) => part === '' || part === '.' || part === '..')
  ) {
    throw releaseError('Release bundle contains an unsafe entry path');
  }
  return name;
}

function assertSupportedArtifact(name) {
  if (!SAFE_EXTENSIONS.has(extname(name).toLowerCase())) {
    throw releaseError('Release bundle contains an unsupported artifact');
  }
}

function containsForbiddenMarker(bytes) {
  const latin1 = bytes.toString('latin1');
  const utf16le = bytes.toString('utf16le');
  const utf16beBytes = Buffer.allocUnsafe(bytes.length - (bytes.length % 2));
  for (let index = 0; index < utf16beBytes.length; index += 2) {
    utf16beBytes[index] = bytes[index + 1];
    utf16beBytes[index + 1] = bytes[index];
  }
  const utf16be = utf16beBytes.toString('utf16le');
  return FORBIDDEN_MARKERS.some((marker) => (
    marker.test(latin1) || marker.test(utf16le) || marker.test(utf16be)
  ));
}

function assertSafeContent(bytes) {
  if (containsForbiddenMarker(bytes)) {
    throw releaseError('Forbidden release marker detected in bundle artifact');
  }
}

function assertLevelImages(entries, prefix) {
  const expected = new Set(
    Array.from({ length: 7 }, (_, index) => `${prefix}growth/level-${index + 1}.png`),
  );
  const levelEntries = [...entries.keys()]
    .filter((name) => /(?:^|\/)level-\d+\.png$/i.test(name));
  const expectedPresent = [...expected].every((name) => entries.has(name));
  const nonEmptyAndPng = levelEntries.every((name) => {
    const content = entries.get(name);
    return content.length >= PNG_SIGNATURE.length
      && content.subarray(0, PNG_SIGNATURE.length).equals(PNG_SIGNATURE);
  });

  if (
    levelEntries.length !== 7
    || new Set(levelEntries).size !== 7
    || !expectedPresent
    || !nonEmptyAndPng
  ) {
    throw releaseError('Expected exactly seven non-empty level PNG assets (growth/level-1.png through growth/level-7.png)');
  }
}

function localAssetPath(reference, prefix) {
  if (/^(?:https?:|\/\/|data:|#|mailto:|tel:|javascript:)/i.test(reference)) return null;
  if (!reference.startsWith('/')) {
    throw releaseError('Release entry must use direct-root asset URLs');
  }
  const rawPath = reference.split(/[?#]/, 1)[0];
  let decoded;
  try {
    decoded = decodeURIComponent(rawPath);
  } catch {
    throw releaseError('Release entry contains a malformed asset URL');
  }
  if (decoded.split('/').some((part) => part === '..' || part === '.')) {
    throw releaseError('Release entry contains an unsafe asset URL');
  }
  const target = posix.normalize(`${prefix}${decoded.replace(/^\/+/, '')}`);
  if (!target.startsWith(prefix) || target === prefix.slice(0, -1)) {
    throw releaseError('Release entry contains an unsafe asset URL');
  }
  return target;
}

function assertDirectHtmlAssets(entries, indexName, prefix) {
  const html = entries.get(indexName);
  if (!html || html.length === 0) {
    throw releaseError('Release bundle must include a non-empty index.html entry');
  }
  const text = html.toString('utf8');
  const assetReferences = [...text.matchAll(/\b(?:src|href)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+))/gi)]
    .map((match) => match[1] ?? match[2] ?? match[3])
    .filter((reference) => localAssetPath(reference, prefix) !== null);

  if (assetReferences.length === 0) {
    throw releaseError('Release entry must reference at least one direct asset');
  }
  for (const reference of assetReferences) {
    const target = localAssetPath(reference, prefix);
    if (target !== null && !entries.has(target)) {
      throw releaseError('Release entry references an asset that is not in the bundle');
    }
  }
}

function verifyEntrySet(entries, prefix) {
  for (const [name, content] of entries) {
    safeEntryPath(name);
    assertSupportedArtifact(name);
    assertSafeContent(content);
  }
  assertDirectHtmlAssets(entries, `${prefix}index.html`, prefix);
  assertLevelImages(entries, prefix);
}

async function assertRealDirectory(root) {
  try {
    const info = await lstat(root);
    if (info.isSymbolicLink()) throw releaseError('Release web root must not be a symbolic link');
    if (!info.isDirectory()) throw releaseError('Release web bundle is missing or is not a directory');
  } catch (error) {
    if (error instanceof Error && error.message.startsWith('Release web')) throw error;
    throw releaseError('Release web bundle is missing or is not a directory');
  }
}

async function walkWeb(root) {
  const entries = new Map();
  async function visit(directory) {
    const children = await readdir(directory, { withFileTypes: true });
    for (const child of children) {
      const location = join(directory, child.name);
      if (child.isSymbolicLink()) throw releaseError('Release web bundle must not contain symbolic links');
      if (child.isDirectory()) {
        await visit(location);
      } else if (child.isFile()) {
        const info = await lstat(location);
        if (!info.isFile()) throw releaseError('Release web bundle contains an unsupported artifact');
        const name = relative(root, location).split('\\').join('/');
        if (entries.has(name)) throw releaseError('Release bundle contains a duplicate entry');
        entries.set(name, await readFile(location));
      } else {
        throw releaseError('Release web bundle contains an unsupported artifact');
      }
    }
  }
  await visit(root);
  return entries;
}

export async function verifyWebRelease(root = DEFAULT_WEB_DIST) {
  await assertRealDirectory(root);
  const entries = await walkWeb(root);
  let totalBytes = 0;
  for (const content of entries.values()) totalBytes += content.length;
  if (totalBytes >= RELEASE_LIMIT_BYTES) {
    throw releaseError(`Uncompressed release bundle is ${totalBytes} bytes; it must be below ${RELEASE_LIMIT_BYTES} bytes`);
  }
  verifyEntrySet(entries, '');
  return { totalBytes, fileCount: entries.size, levelImageCount: 7 };
}

async function assertRealAit(path) {
  try {
    const info = await lstat(path);
    if (info.isSymbolicLink() || !info.isFile()) throw releaseError('Final AIT artifact is missing or is not a regular file');
  } catch (error) {
    if (error instanceof Error && error.message.startsWith('Final AIT')) throw error;
    throw releaseError('Final AIT artifact is missing or is not a regular file');
  }
}

async function resolveDefaultAit() {
  const entries = await readdir(APP_ROOT, { withFileTypes: true });
  const artifacts = entries.filter((entry) => entry.isFile() && entry.name.endsWith('.ait'));
  if (artifacts.length !== 1) throw releaseError('Final AIT artifact is missing or ambiguous');
  return join(APP_ROOT, artifacts[0].name);
}

function assertAitIndex(index) {
  const names = new Set();
  for (const entry of index) {
    const name = safeEntryPath(entry.name);
    if (names.has(name)) throw releaseError('Release bundle contains a duplicate entry');
    if (entry.attrs && entry.attrs.length > 0) throw releaseError('Release bundle contains a symlink-like entry');
    names.add(name);
  }
  return names;
}

export async function verifyRelease(artifactPath) {
  const path = artifactPath ?? await resolveDefaultAit();
  await assertRealAit(path);
  const bytes = await readFile(path);
  if (!AppsInTossBundle.isAIT(bytes)) throw releaseError('Final AIT artifact has invalid magic bytes');

  let reader;
  try {
    reader = AppsInTossBundle.reader(bytes);
  } catch {
    throw releaseError('Final AIT artifact cannot be read');
  }
  const index = reader.bundle.index ?? [];
  const names = assertAitIndex(index);
  const entries = new Map();
  let totalBytes = 0;

  for (const entry of index) {
    let content;
    try {
      content = Buffer.from(await reader.readEntry(entry.name));
    } catch {
      throw releaseError('Final AIT artifact contains an unreadable entry');
    }
    const declaredSize = Number(entry.uncompressedSize);
    if (!Number.isSafeInteger(declaredSize) || declaredSize < 0 || declaredSize !== content.length) {
      throw releaseError('Final AIT artifact has an invalid entry size');
    }
    totalBytes += content.length;
    entries.set(entry.name, content);
  }

  if (entries.size !== names.size) throw releaseError('Final AIT artifact index is inconsistent');
  if (totalBytes >= RELEASE_LIMIT_BYTES) {
    throw releaseError(`Uncompressed release bundle is ${totalBytes} bytes; it must be below ${RELEASE_LIMIT_BYTES} bytes`);
  }
  verifyEntrySet(entries, 'web/');
  return { totalBytes, entryCount: entries.size, levelImageCount: 7 };
}

async function main() {
  try {
    if (process.argv[2] === '--web') {
      const result = await verifyWebRelease(process.argv[3]);
      console.log(`Web preflight passed: ${result.totalBytes} bytes across ${result.fileCount} files`);
    } else {
      const result = await verifyRelease(process.argv[2]);
      console.log(`Final AIT release checks passed: ${result.totalBytes} bytes across ${result.entryCount} entries`);
    }
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Unknown verification failure';
    console.error(`Release verification failed: ${message}`);
    process.exitCode = 1;
  }
}

if (process.argv[1] === fileURLToPath(import.meta.url)) await main();
