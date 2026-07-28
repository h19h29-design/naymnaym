import { createHash } from 'node:crypto';
import { lstat, readdir, readFile } from 'node:fs/promises';
import { extname, join, posix, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

import { AppsInTossBundle } from '@apps-in-toss/ait-format';
import { inflateSync, unzlibSync } from 'fflate';

export const RELEASE_LIMIT_BYTES = 100 * 1024 * 1024;
export const PRODUCTION_CONSOLE_IDENTITY = Object.freeze({
  appName: 'nyam-levelup',
  displayName: '급식레벨업',
});
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
const JWT_PATTERN = /[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}/g;
const ZIP_LOCAL_SIGNATURE = 0x04034b50;
const ZIP_CENTRAL_SIGNATURE = 0x02014b50;
const ZIP_EOCD_SIGNATURE = 0x06054b50;
const PNG_BIT_DEPTHS = new Map([
  [0, new Set([1, 2, 4, 8, 16])],
  [2, new Set([8, 16])],
  [3, new Set([1, 2, 4, 8])],
  [4, new Set([8, 16])],
  [6, new Set([8, 16])],
]);

function releaseError(message) {
  return new Error(message);
}

function crc32(bytes) {
  let crc = 0xffffffff;
  for (const byte of bytes) {
    crc ^= byte;
    for (let bit = 0; bit < 8; bit += 1) crc = (crc >>> 1) ^ (crc & 1 ? 0xedb88320 : 0);
  }
  return (crc ^ 0xffffffff) >>> 0;
}

function safeEntryPath(name) {
  if (
    typeof name !== 'string'
    || name.length === 0
    || name.includes('\0')
    || name.includes('\\')
    || name.startsWith('/')
    || /^[A-Za-z]:/.test(name)
    || name.split('/').some((part) => part === '' || part === '.' || part === '..')
  ) {
    throw releaseError('Release bundle contains an unsafe entry path');
  }
  assertSafeContent(Buffer.from(name));
  return name;
}

function assertSupportedArtifact(name) {
  if (!SAFE_EXTENSIONS.has(extname(name).toLowerCase())) {
    throw releaseError('Release bundle contains an unsupported artifact');
  }
}

function decodedTexts(bytes) {
  const texts = [bytes.toString('latin1')];
  for (let alignment = 0; alignment < 2; alignment += 1) {
    const length = bytes.length - alignment - ((bytes.length - alignment) % 2);
    if (length <= 0) continue;
    const aligned = bytes.subarray(alignment, alignment + length);
    texts.push(aligned.toString('utf16le'));
    const swapped = Buffer.allocUnsafe(aligned.length);
    for (let offset = 0; offset < aligned.length; offset += 2) {
      swapped[offset] = aligned[offset + 1];
      swapped[offset + 1] = aligned[offset];
    }
    texts.push(swapped.toString('utf16le'));
  }
  return texts;
}

function assertSafeJwt(text) {
  for (const token of text.matchAll(JWT_PATTERN)) {
    try {
      const payload = JSON.parse(Buffer.from(token[0].split('.')[1], 'base64url').toString('utf8'));
      if (typeof payload?.role === 'string' && payload.role !== 'anon') {
        throw releaseError('Forbidden JWT role detected in bundle artifact');
      }
    } catch (error) {
      if (error instanceof Error && error.message.startsWith('Forbidden JWT role')) throw error;
    }
  }
}

function assertSafeContent(bytes) {
  for (const text of decodedTexts(bytes)) {
    if (FORBIDDEN_MARKERS.some((marker) => marker.test(text))) {
      throw releaseError('Forbidden release marker detected in bundle artifact');
    }
    assertSafeJwt(text);
  }
}

function assertSafeMetadata(value, seen = new Set()) {
  if (typeof value === 'string') return assertSafeContent(Buffer.from(value));
  if (value instanceof Uint8Array) return assertSafeContent(Buffer.from(value));
  if (typeof value !== 'object' || value === null || seen.has(value)) return;
  seen.add(value);
  if (Array.isArray(value)) {
    for (const item of value) assertSafeMetadata(item, seen);
  } else {
    for (const [key, item] of Object.entries(value)) {
      assertSafeContent(Buffer.from(key));
      assertSafeMetadata(item, seen);
    }
  }
}

function assertConsoleIdentity(reader, expectedIdentity) {
  if (!expectedIdentity) return;
  if (reader.appName !== expectedIdentity.appName) {
    throw releaseError('Release bundle appName does not match Toss console registration');
  }
  if (reader.metadata?.extra?.brand?.displayName !== expectedIdentity.displayName) {
    throw releaseError('Release bundle displayName does not match Toss console app information');
  }
}

function validatePng(content) {
  if (content.length < PNG_SIGNATURE.length || !content.subarray(0, 8).equals(PNG_SIGNATURE)) return false;
  let offset = PNG_SIGNATURE.length;
  let sawIhdr = false;
  let sawIdat = false;
  const idat = [];
  while (offset < content.length) {
    if (offset + 12 > content.length) return false;
    const length = content.readUInt32BE(offset);
    const end = offset + 12 + length;
    if (!Number.isSafeInteger(end) || end > content.length) return false;
    const type = content.toString('ascii', offset + 4, offset + 8);
    const data = content.subarray(offset + 8, offset + 8 + length);
    if (crc32(content.subarray(offset + 4, offset + 8 + length)) !== content.readUInt32BE(offset + 8 + length)) return false;
    if (!sawIhdr) {
      if (type !== 'IHDR' || length !== 13 || data.readUInt32BE(0) === 0 || data.readUInt32BE(4) === 0) return false;
      const bitDepths = PNG_BIT_DEPTHS.get(data[9]);
      if (!bitDepths?.has(data[8]) || data[10] !== 0 || data[11] !== 0 || data[12] > 1) return false;
      sawIhdr = true;
    } else if (type === 'IHDR') {
      return false;
    }
    if (type === 'IDAT') {
      if (!sawIhdr) return false;
      sawIdat = true;
      idat.push(data);
    }
    if (type === 'IEND') {
      if (length !== 0 || !sawIdat || end !== content.length) return false;
      try {
        return unzlibSync(Buffer.concat(idat)).length > 0;
      } catch {
        return false;
      }
    }
    offset = end;
  }
  return false;
}

function assertLevelImages(entries, prefix) {
  const expected = new Set(
    Array.from({ length: 7 }, (_, index) => `${prefix}growth/level-${index + 1}.png`),
  );
  const levelEntries = [...entries.keys()].filter((name) => /(?:^|\/)level-\d+\.png$/i.test(name));
  const expectedPresent = [...expected].every((name) => entries.has(name));
  const validPng = levelEntries.every((name) => validatePng(entries.get(name)));
  if (levelEntries.length !== 7 || new Set(levelEntries).size !== 7 || !expectedPresent || !validPng) {
    throw releaseError('Release bundle contains an invalid level PNG asset');
  }
}

function localAssetPath(reference, prefix) {
  if (/^(?:https?:|\/\/|data:|#|mailto:|tel:|javascript:)/i.test(reference)) return null;
  if (!reference.startsWith('/')) throw releaseError('Release entry must use direct-root asset URLs');
  const rawPath = reference.split(/[?#]/, 1)[0];
  let decoded;
  try {
    decoded = decodeURIComponent(rawPath);
  } catch {
    throw releaseError('Release entry contains a malformed asset URL');
  }
  if (decoded.split('/').some((part) => part === '..' || part === '.')) throw releaseError('Release entry contains an unsafe asset URL');
  const target = posix.normalize(`${prefix}${decoded.replace(/^\/+/, '')}`);
  if (!target.startsWith(prefix) || target === prefix.slice(0, -1)) throw releaseError('Release entry contains an unsafe asset URL');
  return target;
}

function assertDirectHtmlAssets(entries, indexName, prefix) {
  const html = entries.get(indexName);
  if (!html || html.length === 0) throw releaseError('Release bundle must include a non-empty index.html entry');
  const references = [...html.toString('utf8').matchAll(/\b(?:src|href)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+))/gi)]
    .map((match) => match[1] ?? match[2] ?? match[3])
    .filter((reference) => localAssetPath(reference, prefix) !== null);
  if (references.length === 0) throw releaseError('Release entry must reference at least one direct asset');
  for (const reference of references) {
    const target = localAssetPath(reference, prefix);
    if (target !== null && !entries.has(target)) throw releaseError('Release entry references an asset that is not in the bundle');
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
    for (const child of await readdir(directory, { withFileTypes: true })) {
      const location = join(directory, child.name);
      if (child.isSymbolicLink()) throw releaseError('Release web bundle must not contain symbolic links');
      if (child.isDirectory()) await visit(location);
      else if (child.isFile()) {
        if (!(await lstat(location)).isFile()) throw releaseError('Release web bundle contains an unsupported artifact');
        const name = relative(root, location).split('\\').join('/');
        if (entries.has(name)) throw releaseError('Release bundle contains a duplicate entry');
        entries.set(name, await readFile(location));
      } else throw releaseError('Release web bundle contains an unsupported artifact');
    }
  }
  await visit(root);
  return entries;
}

export async function verifyWebRelease(root = DEFAULT_WEB_DIST) {
  await assertRealDirectory(root);
  const entries = await walkWeb(root);
  const totalBytes = [...entries.values()].reduce((total, content) => total + content.length, 0);
  if (totalBytes >= RELEASE_LIMIT_BYTES) throw releaseError(`Uncompressed release bundle is ${totalBytes} bytes; it must be below ${RELEASE_LIMIT_BYTES} bytes`);
  verifyEntrySet(entries, '');
  return { totalBytes, fileCount: entries.size, levelImageCount: 7 };
}

function findEocd(zip) {
  const start = Math.max(0, zip.length - 0xffff - 22);
  for (let offset = zip.length - 22; offset >= start; offset -= 1) {
    if (zip.readUInt32LE(offset) === ZIP_EOCD_SIGNATURE && offset + 22 + zip.readUInt16LE(offset + 20) === zip.length) return offset;
  }
  throw releaseError('Final AIT artifact has malformed ZIP bounds');
}

function assertZipExtra(extra) {
  assertSafeContent(extra);
  let offset = 0;
  while (offset < extra.length) {
    if (offset + 4 > extra.length) throw releaseError('Final AIT artifact has malformed ZIP extra fields');
    const id = extra.readUInt16LE(offset);
    const length = extra.readUInt16LE(offset + 2);
    if (offset + 4 + length > extra.length) throw releaseError('Final AIT artifact has malformed ZIP extra fields');
    if (id === 0x0001) throw releaseError('Final AIT artifact uses unsupported ZIP64 or multidisk fields');
    offset += 4 + length;
  }
}

function parseZipEntries(zip) {
  if (zip.length < 22) throw releaseError('Final AIT artifact has malformed ZIP bounds');
  const eocd = findEocd(zip);
  assertSafeContent(zip.subarray(eocd + 22));
  const disk = zip.readUInt16LE(eocd + 4);
  const centralDisk = zip.readUInt16LE(eocd + 6);
  const diskCount = zip.readUInt16LE(eocd + 8);
  const count = zip.readUInt16LE(eocd + 10);
  const centralSize = zip.readUInt32LE(eocd + 12);
  const centralOffset = zip.readUInt32LE(eocd + 16);
  if (disk !== 0 || centralDisk !== 0 || diskCount !== count || count === 0xffff || centralSize === 0xffffffff || centralOffset === 0xffffffff) {
    throw releaseError('Final AIT artifact uses unsupported ZIP64 or multidisk fields');
  }
  if (centralOffset > eocd || centralSize > eocd - centralOffset || centralOffset + centralSize !== eocd) {
    throw releaseError('Final AIT artifact has malformed ZIP bounds');
  }
  const actual = new Map();
  const localRecords = [];
  let offset = centralOffset;
  for (let index = 0; index < count; index += 1) {
    if (offset + 46 > eocd || zip.readUInt32LE(offset) !== ZIP_CENTRAL_SIGNATURE) throw releaseError('Final AIT artifact has malformed ZIP bounds');
    const flags = zip.readUInt16LE(offset + 8);
    const method = zip.readUInt16LE(offset + 10);
    const crc = zip.readUInt32LE(offset + 16);
    const compressedSize = zip.readUInt32LE(offset + 20);
    const uncompressedSize = zip.readUInt32LE(offset + 24);
    const nameLength = zip.readUInt16LE(offset + 28);
    const extraLength = zip.readUInt16LE(offset + 30);
    const commentLength = zip.readUInt16LE(offset + 32);
    const diskStart = zip.readUInt16LE(offset + 34);
    const externalAttrs = zip.readUInt32LE(offset + 38);
    const localOffset = zip.readUInt32LE(offset + 42);
    const recordEnd = offset + 46 + nameLength + extraLength + commentLength;
    if (recordEnd > eocd || diskStart !== 0 || compressedSize === 0xffffffff || uncompressedSize === 0xffffffff || localOffset === 0xffffffff) {
      throw releaseError('Final AIT artifact uses unsupported ZIP64 or multidisk fields');
    }
    if ((flags & 0x0009) !== 0 || (method !== 0 && method !== 8) || ((externalAttrs >>> 16) & 0o170000) === 0o120000 || (externalAttrs & 0x10) !== 0) {
      throw releaseError('Final AIT artifact contains an unsupported ZIP entry');
    }
    const centralName = zip.subarray(offset + 46, offset + 46 + nameLength);
    const centralExtra = zip.subarray(offset + 46 + nameLength, offset + 46 + nameLength + extraLength);
    const comment = zip.subarray(offset + 46 + nameLength + extraLength, recordEnd);
    assertSafeContent(centralName);
    const name = safeEntryPath(centralName.toString('utf8'));
    assertZipExtra(centralExtra);
    assertSafeContent(comment);
    if (actual.has(name)) throw releaseError('Final AIT artifact contains a duplicate ZIP entry');
    if (localOffset + 30 > centralOffset || zip.readUInt32LE(localOffset) !== ZIP_LOCAL_SIGNATURE) throw releaseError('Final AIT artifact has malformed ZIP bounds');
    const localFlags = zip.readUInt16LE(localOffset + 6);
    const localMethod = zip.readUInt16LE(localOffset + 8);
    const localCrc = zip.readUInt32LE(localOffset + 14);
    const localCompressedSize = zip.readUInt32LE(localOffset + 18);
    const localUncompressedSize = zip.readUInt32LE(localOffset + 22);
    const localNameLength = zip.readUInt16LE(localOffset + 26);
    const localExtraLength = zip.readUInt16LE(localOffset + 28);
    const dataOffset = localOffset + 30 + localNameLength + localExtraLength;
    const dataEnd = dataOffset + compressedSize;
    if (dataOffset > centralOffset || dataEnd > centralOffset) {
      throw releaseError('Final AIT artifact has malformed ZIP bounds');
    }
    const localName = zip.subarray(localOffset + 30, localOffset + 30 + localNameLength);
    const localExtra = zip.subarray(localOffset + 30 + localNameLength, dataOffset);
    assertZipExtra(localExtra);
    if (
      localFlags !== flags
      || localMethod !== method
      || localCrc !== crc
      || localCompressedSize !== compressedSize
      || localUncompressedSize !== uncompressedSize
      || !localName.equals(centralName)
    ) {
      throw releaseError('Final AIT artifact has a local ZIP header mismatch');
    }
    localRecords.push({ start: localOffset, end: dataEnd });
    let content;
    try {
      content = method === 0 ? Buffer.from(zip.subarray(dataOffset, dataEnd)) : Buffer.from(inflateSync(zip.subarray(dataOffset, dataEnd)));
    } catch {
      throw releaseError('Final AIT artifact contains an unreadable ZIP entry');
    }
    if (content.length !== uncompressedSize) throw releaseError('Final AIT artifact has an invalid ZIP entry size');
    if (crc32(content) !== crc) throw releaseError('Final AIT artifact has an invalid ZIP entry checksum');
    actual.set(name, content);
    offset = recordEnd;
  }
  if (offset !== eocd) throw releaseError('Final AIT artifact has malformed ZIP bounds');
  localRecords.sort((left, right) => left.start - right.start);
  let localEnd = 0;
  for (const record of localRecords) {
    if (record.start !== localEnd || record.end < record.start) throw releaseError('Final AIT artifact has malformed ZIP bounds');
    localEnd = record.end;
  }
  if (localEnd !== centralOffset) throw releaseError('Final AIT artifact has malformed ZIP bounds');
  return actual;
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
  const artifacts = (await readdir(APP_ROOT, { withFileTypes: true })).filter((entry) => entry.isFile() && entry.name.endsWith('.ait'));
  if (artifacts.length !== 1) throw releaseError('Final AIT artifact is missing or ambiguous');
  return join(APP_ROOT, artifacts[0].name);
}

function assertIndexMatchesZip(index, actual) {
  const indexed = new Map();
  for (const item of index) {
    const name = safeEntryPath(item.name);
    if (indexed.has(name)) throw releaseError('Release bundle contains a duplicate entry');
    if (item.attrs !== undefined) throw releaseError('Release bundle contains a symlink-like entry');
    indexed.set(name, item);
  }
  if (indexed.size !== actual.size || [...indexed.keys()].some((name) => !actual.has(name))) {
    throw releaseError('Final AIT ZIP index does not match the protobuf index');
  }
  for (const [name, content] of actual) {
    const item = indexed.get(name);
    if (Number(item.uncompressedSize) !== content.length) throw releaseError('Final AIT artifact has an invalid ZIP entry size');
    const digest = createHash('sha256').update(content).digest('hex');
    if (typeof item.sha256Hex !== 'string' || item.sha256Hex.toLowerCase() !== digest) {
      throw releaseError('Final AIT artifact has an invalid entry digest');
    }
  }
}

export async function verifyRelease(artifactPath, expectedIdentity) {
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
  assertConsoleIdentity(reader, expectedIdentity);
  let entries;
  try {
    entries = parseZipEntries(Buffer.from(reader.readZipBlob()));
  } catch (error) {
    if (
      error instanceof Error
      && (
        error.message.startsWith('Final AIT')
        || error.message.startsWith('Release bundle')
        || error.message.startsWith('Forbidden ')
      )
    ) throw error;
    throw releaseError('Final AIT artifact cannot be read');
  }
  assertSafeMetadata({
    appName: reader.appName,
    deploymentId: reader.bundle.deploymentId,
    createdBy: reader.bundle.createdBy,
    metadata: reader.metadata,
    permissions: reader.permissions,
    packageMetadata: reader.bundle,
  });
  assertIndexMatchesZip(reader.bundle.index ?? [], entries);
  const totalBytes = [...entries.values()].reduce((total, content) => total + content.length, 0);
  if (totalBytes >= RELEASE_LIMIT_BYTES) throw releaseError(`Uncompressed release bundle is ${totalBytes} bytes; it must be below ${RELEASE_LIMIT_BYTES} bytes`);
  verifyEntrySet(entries, 'web/');
  return { totalBytes, entryCount: entries.size, levelImageCount: 7 };
}

async function main() {
  try {
    if (process.argv[2] === '--web') {
      const result = await verifyWebRelease(process.argv[3]);
      console.log(`Web preflight passed: ${result.totalBytes} bytes across ${result.fileCount} files`);
    } else {
      const result = await verifyRelease(process.argv[2], PRODUCTION_CONSOLE_IDENTITY);
      console.log(`Final AIT release checks passed: ${result.totalBytes} bytes across ${result.entryCount} entries`);
    }
  } catch (error) {
    console.error(`Release verification failed: ${error instanceof Error ? error.message : 'Unknown verification failure'}`);
    process.exitCode = 1;
  }
}

if (process.argv[1] === fileURLToPath(import.meta.url)) await main();
