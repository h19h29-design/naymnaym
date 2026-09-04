import { lstat, readdir, readFile } from 'node:fs/promises';
import { extname, join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';
import { AppsInTossBundle } from '@apps-in-toss/ait-format';
import { unzipSync } from 'fflate';

const APP_ROOT = fileURLToPath(new URL('../', import.meta.url));
const MAX_BYTES = 100 * 1024 * 1024;
const SAFE_EXTENSIONS = new Set(['.html', '.js', '.css', '.webp', '.png', '.jpg', '.jpeg', '.svg', '.json', '.map', '.woff', '.woff2', '.ttf', '.otf', '.wasm']);
const FORBIDDEN = [/neis_api_key/i, /supabase_service_role_key/i, /service[_ -]?role/i, /sb_secret_/i, /sk_live_/i];
const JWT = /[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}/g;

function fail(message) { throw new Error(message); }

function texts(bytes) {
  const result = [bytes.toString('latin1')];
  if (bytes.length > 1) result.push(bytes.subarray(0, bytes.length - bytes.length % 2).toString('utf16le'));
  return result;
}

function assertSafe(bytes) {
  for (const text of texts(bytes)) {
    if (FORBIDDEN.some((pattern) => pattern.test(text))) fail('Forbidden release marker detected');
    for (const token of text.match(JWT) ?? []) {
      try {
        const payload = JSON.parse(Buffer.from(token.split('.')[1], 'base64url').toString('utf8'));
        if (typeof payload.role === 'string' && payload.role !== 'anon') fail('Forbidden JWT role detected');
      } catch (error) {
        if (error instanceof Error && error.message.startsWith('Forbidden')) throw error;
      }
    }
  }
}

function assertEntryName(name) {
  if (!name || name.startsWith('/') || name.includes('\\') || name.split('/').some((part) => !part || part === '.' || part === '..')) fail('Release bundle contains an unsafe entry path');
  if (!SAFE_EXTENSIONS.has(extname(name).toLowerCase())) fail('Release bundle contains an unsupported artifact');
}

function webpDimensions(bytes) {
  if (bytes.length < 20 || bytes.toString('ascii', 0, 4) !== 'RIFF' || bytes.readUInt32LE(4) + 8 !== bytes.length || bytes.toString('ascii', 8, 12) !== 'WEBP') return null;
  let dimensions = null;
  let imageData = false;
  let offset = 12;
  while (offset < bytes.length) {
    if (offset + 8 > bytes.length) return null;
    const type = bytes.toString('ascii', offset, offset + 4);
    const size = bytes.readUInt32LE(offset + 4);
    const data = offset + 8;
    const end = data + size;
    const paddedEnd = end + (size % 2);
    if (end > bytes.length || paddedEnd > bytes.length) return null;
    let candidate = null;
    if (type === 'VP8X') {
      if (size !== 10) return null;
      candidate = { width: bytes.readUIntLE(data + 4, 3) + 1, height: bytes.readUIntLE(data + 7, 3) + 1 };
    } else if (type === 'VP8L') {
      if (size < 5 || bytes[data] !== 0x2f) return null;
      const bits = bytes.readUInt32LE(data + 1);
      candidate = { width: (bits & 0x3fff) + 1, height: ((bits >>> 14) & 0x3fff) + 1 };
      imageData = true;
    } else if (type === 'VP8 ') {
      if (size < 10 || bytes[data + 3] !== 0x9d || bytes[data + 4] !== 0x01 || bytes[data + 5] !== 0x2a) return null;
      candidate = { width: bytes.readUInt16LE(data + 6) & 0x3fff, height: bytes.readUInt16LE(data + 8) & 0x3fff };
      imageData = true;
    }
    if (candidate) {
      if (candidate.width < 1 || candidate.height < 1 || (dimensions && (dimensions.width !== candidate.width || dimensions.height !== candidate.height))) return null;
      dimensions = candidate;
    }
    offset = paddedEnd;
  }
  return offset === bytes.length && imageData ? dimensions : null;
}

function isVerifiedStageWebp(bytes) {
  const dimensions = webpDimensions(bytes);
  return dimensions?.width === 512 && dimensions.height === 512;
}

function validateEntries(entries, prefix = '') {
  let totalBytes = 0;
  for (const [name, bytes] of entries) {
    assertEntryName(name);
    assertSafe(bytes);
    totalBytes += bytes.length;
  }
  if (totalBytes >= MAX_BYTES) fail('Release bundle must be below 100 MB');
  const levels = [...entries].filter(([name]) => name.startsWith(`${prefix}growth/level-`));
  const expected = Array.from({ length: 7 }, (_, index) => `${prefix}growth/level-${index + 1}.webp`);
  if (levels.length !== 7 || expected.some((name) => !entries.has(name) || !isVerifiedStageWebp(entries.get(name)))) fail('Release bundle must contain exactly seven verified stage images');
  const html = entries.get(`${prefix}index.html`)?.toString('utf8');
  if (!html || !/<script\b[^>]*\bsrc=/i.test(html)) fail('Release bundle is missing its app entry');
  return { totalBytes, fileCount: entries.size, levelImageCount: 7 };
}

async function walk(root) {
  const rootInfo = await lstat(root).catch(() => null);
  if (!rootInfo?.isDirectory() || rootInfo.isSymbolicLink()) fail('Release web bundle is missing or invalid');
  const entries = new Map();
  async function visit(directory) {
    for (const child of await readdir(directory, { withFileTypes: true })) {
      const path = join(directory, child.name);
      if (child.isSymbolicLink()) fail('Release bundle must not contain symbolic links');
      if (child.isDirectory()) await visit(path);
      else if (child.isFile()) entries.set(relative(root, path).split('\\').join('/'), await readFile(path));
      else fail('Release bundle contains an unsupported artifact');
    }
  }
  await visit(root);
  return entries;
}

export async function verifyWebRelease(root = join(APP_ROOT, 'dist')) {
  return validateEntries(await walk(root));
}

export async function verifyRelease(path = join(APP_ROOT, 'nyam-levelup.ait')) {
  const info = await lstat(path).catch(() => null);
  if (!info?.isFile() || info.isSymbolicLink()) fail('Final AIT artifact is missing or invalid');
  const bytes = await readFile(path);
  if (!AppsInTossBundle.isAIT(bytes)) fail('Final AIT artifact has invalid magic bytes');
  const reader = AppsInTossBundle.reader(bytes);
  if (reader.appName !== 'nyam-levelup') fail('Final AIT appName does not match the Toss console');
  assertSafe(Buffer.from(JSON.stringify({ appName: reader.appName, metadata: reader.metadata })));
  let unzipped;
  try { unzipped = unzipSync(new Uint8Array(reader.readZipBlob())); }
  catch { fail('Final AIT archive cannot be read'); }
  const entries = new Map(Object.entries(unzipped).map(([name, data]) => [name, Buffer.from(data)]));
  const result = validateEntries(entries, 'sources/');
  return { ...result, entryCount: result.fileCount, appName: reader.appName };
}

async function main() {
  try {
    if (process.argv[2] === '--web') {
      const result = await verifyWebRelease(process.argv[3]);
      console.log(`Web preflight passed: ${result.totalBytes} bytes across ${result.fileCount} files`);
    } else {
      const result = await verifyRelease(process.argv[2]);
      console.log(`Final AIT checks passed: ${result.totalBytes} bytes across ${result.entryCount} entries`);
    }
  } catch (error) {
    console.error(`Release verification failed: ${error instanceof Error ? error.message : 'unknown error'}`);
    process.exitCode = 1;
  }
}

if (process.argv[1] === fileURLToPath(import.meta.url)) await main();
