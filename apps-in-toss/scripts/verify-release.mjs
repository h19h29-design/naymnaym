import { createHash } from 'node:crypto';
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
const VERIFIED_STAGES = [
  { bytes: 22692, sha256: 'fcf8194404f21ccf65d0d9389aa30a2ba7c23281c8f37fe2e86ec26e5415e253' },
  { bytes: 27208, sha256: 'a218b4e7c5d145068bd6cf1d7baedd68d3e4a333268dddfc4ac0ed8e036c8da4' },
  { bytes: 27078, sha256: '2bd80f3c8a55852c7f007b189c367a2aeadb6cd72008035f963daf98c10a31af' },
  { bytes: 32116, sha256: '38b7dcae3ae07e5a42aa6a37edd450913c0ea296f39bd01fab994283c7ae93c9' },
  { bytes: 32448, sha256: '42730bf7932f9ebe2293815e73cb1e38ad1110e80a75fae74c5d0641acb9042a' },
  { bytes: 36406, sha256: '33d94899587b1ddb12cb3807f465065dae8616c622391a999bf3626c3d1469ff' },
  { bytes: 40864, sha256: '7d2c237e187b2da4d9f973df37e6e37c6c7cdb1744bcf1d0301b1eb7d9003488' },
];

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

function isVerifiedStage(bytes, index) {
  const expected = VERIFIED_STAGES[index];
  return bytes.length === expected.bytes && createHash('sha256').update(bytes).digest('hex') === expected.sha256;
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
  if (levels.length !== 7 || expected.some((name, index) => !entries.has(name) || !isVerifiedStage(entries.get(name), index))) fail('Release bundle must contain exactly seven verified stage images');
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
