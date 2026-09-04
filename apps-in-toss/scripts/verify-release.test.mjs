import assert from 'node:assert/strict';
import { mkdtemp, mkdir, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';
import { AITWriter } from '@apps-in-toss/ait-format';
import { verifyRelease, verifyWebRelease } from './verify-release.mjs';

const APP_ROOT = new URL('../', import.meta.url);
const TRUNCATED_WEBP = Buffer.from('524946460400000057454250', 'hex');

async function fixture(root, unsafe = false, imageOverride = null) {
  await mkdir(join(root, 'assets'), { recursive: true });
  await mkdir(join(root, 'growth'), { recursive: true });
  await writeFile(join(root, 'index.html'), '<script type="module" src="/assets/app.js"></script>');
  await writeFile(join(root, 'assets/app.js'), unsafe ? 'NEIS_API_KEY' : 'console.log("safe")');
  for (let level = 1; level <= 7; level += 1) {
    const image = imageOverride ?? await readFile(new URL(`public/growth/level-${level}.webp`, APP_ROOT));
    await writeFile(join(root, `growth/level-${level}.webp`), image);
  }
}

async function temporary(run) {
  const root = await mkdtemp(join(tmpdir(), 'nyam-v2-'));
  try { await run(root); } finally { await rm(root, { recursive: true, force: true }); }
}

test('accepts the exact seven-stage web bundle', async () => temporary(async (root) => {
  await fixture(root);
  const result = await verifyWebRelease(root);
  assert.equal(result.levelImageCount, 7);
}));

test('rejects source-map or bundle secret markers', async () => temporary(async (root) => {
  await fixture(root, true);
  await assert.rejects(() => verifyWebRelease(root), /Forbidden release marker/);
}));

test('rejects a truncated RIFF/WEBP header with no decodable image structure', async () => temporary(async (root) => {
  await fixture(root, false, TRUNCATED_WEBP);
  await assert.rejects(() => verifyWebRelease(root), /exactly seven verified stage images/);
}));

test('accepts an SDK-format AIT with the console appName', async () => temporary(async (root) => {
  const web = join(root, 'web');
  await fixture(web);
  const writer = new AITWriter({ appName: 'nyam-levelup', deploymentId: '019f9310-1c0b-78d1-adb0-11d90fed1676' });
  const files = ['index.html', 'assets/app.js', ...Array.from({ length: 7 }, (_, index) => `growth/level-${index + 1}.webp`)];
  for (const name of files) writer.addFile(`sources/${name}`, await import('node:fs/promises').then(({ readFile }) => readFile(join(web, name))));
  const artifact = join(root, 'nyam-levelup.ait');
  await writeFile(artifact, await writer.toBuffer());
  const result = await verifyRelease(artifact);
  assert.equal(result.appName, 'nyam-levelup');
}));
