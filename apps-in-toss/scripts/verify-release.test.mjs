import assert from 'node:assert/strict';
import { mkdtemp, mkdir, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';

import { verifyRelease } from './verify-release.mjs';

async function withTemporaryDirectory(run) {
  const directory = await mkdtemp(join(tmpdir(), 'nyam-release-'));
  try {
    await run(directory);
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
}

async function createValidBundle(root) {
  await mkdir(join(root, 'growth'), { recursive: true });
  await mkdir(join(root, 'assets'), { recursive: true });
  await writeFile(join(root, 'index.html'), '<!doctype html><script type="module" src="/assets/app.js"></script>');
  await writeFile(join(root, 'assets', 'app.js'), 'console.log("safe")');
  for (let level = 1; level <= 7; level += 1) {
    await writeFile(join(root, 'growth', `level-${level}.png`), Buffer.from([137, 80, 78, 71]));
  }
}

test('rejects a missing release directory', async () => {
  await withTemporaryDirectory(async (root) => {
    await assert.rejects(
      () => verifyRelease(join(root, 'missing')),
      /Release bundle is missing/,
    );
  });
});

test('accepts a complete bundle and excludes maps and documentation from content scanning', async () => {
  await withTemporaryDirectory(async (root) => {
    await createValidBundle(root);
    await writeFile(join(root, 'assets', 'app.js.map'), 'NEIS_API_KEY');
    await writeFile(join(root, 'RELEASE-NOTES.md'), 'SUPABASE_SERVICE_ROLE_KEY');

    const result = await verifyRelease(root);

    assert.equal(result.levelImageCount, 7);
    assert.ok(result.totalBytes > 0);
  });
});

test('rejects unsafe markers in an otherwise unknown release artifact without echoing the marker', async () => {
  await withTemporaryDirectory(async (root) => {
    await createValidBundle(root);
    await writeFile(join(root, 'assets', 'payload.bin'), 'prefix sk_live_example');

    await assert.rejects(
      () => verifyRelease(root),
      (error) => {
        assert.match(error.message, /Forbidden release marker detected/);
        assert.doesNotMatch(error.message, /sk_live_example/);
        return true;
      },
    );
  });
});

test('rejects an extra level image so every level is represented exactly once', async () => {
  await withTemporaryDirectory(async (root) => {
    await createValidBundle(root);
    await writeFile(join(root, 'growth', 'level-8.png'), Buffer.from([137, 80, 78, 71]));

    await assert.rejects(
      () => verifyRelease(root),
      /Expected exactly seven non-empty level PNG assets/,
    );
  });
});
