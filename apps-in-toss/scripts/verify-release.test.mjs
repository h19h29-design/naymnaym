import assert from 'node:assert/strict';
import { mkdtemp, mkdir, rm, symlink, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';

import { AITWriter } from '@apps-in-toss/ait-format';
import { verifyRelease, verifyWebRelease } from './verify-release.mjs';

const PNG = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);

async function withTemporaryDirectory(run, prefix = 'nyam-release-') {
  const directory = await mkdtemp(join(tmpdir(), prefix));
  try {
    await run(directory);
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
}

function validEntries() {
  const entries = new Map([
    ['web/index.html', Buffer.from('<!doctype html><script type="module" src="/assets/app.js"></script>')],
    ['web/assets/app.js', Buffer.from('console.log("safe")')],
  ]);
  for (let level = 1; level <= 7; level += 1) {
    entries.set(`web/growth/level-${level}.png`, PNG);
  }
  return entries;
}

async function writeAit(path, entries) {
  const writer = new AITWriter({
    appName: 'nyam-release-fixture',
    deploymentId: '019f9310-1c0b-78d1-adb0-11d90fed1676',
  });
  for (const [name, data] of entries) writer.addFile(name, data);
  await writeFile(path, await writer.toBuffer());
}

async function createWebBundle(root, entries = validEntries()) {
  for (const [path, data] of entries) {
    const destination = join(root, ...path.replace(/^web\//, '').split('/'));
    await mkdir(join(destination, '..'), { recursive: true });
    await writeFile(destination, data);
  }
}

function expectsSafeFailure(assertion) {
  return (error) => {
    assert.match(error.message, assertion);
    assert.doesNotMatch(error.message, /sk_live_example|sb_secret_example/);
    return true;
  };
}

test('rejects a missing final AIT artifact', async () => {
  await withTemporaryDirectory(async (root) => {
    await assert.rejects(() => verifyRelease(join(root, 'missing.ait')), /Final AIT artifact is missing/);
  });
});

test('accepts a complete final AIT artifact made with the official writer', async () => {
  await withTemporaryDirectory(async (root) => {
    const artifact = join(root, 'nyam.ait');
    await writeAit(artifact, validEntries());

    const result = await verifyRelease(artifact);

    assert.equal(result.levelImageCount, 7);
    assert.equal(result.entryCount, 9);
    assert.ok(result.totalBytes > 0);
  });
});

test('rejects a secret marker in a bundled documentation entry', async () => {
  await withTemporaryDirectory(async (root) => {
    const entries = validEntries();
    entries.set('web/docs/release.md', Buffer.from('NEIS_API_KEY'));
    const artifact = join(root, 'nyam.ait');
    await writeAit(artifact, entries);

    await assert.rejects(() => verifyRelease(artifact), expectsSafeFailure(/Forbidden release marker detected/));
  });
});

test('rejects a secret marker in a source map', async () => {
  await withTemporaryDirectory(async (root) => {
    const entries = validEntries();
    entries.set('web/assets/app.js.map', Buffer.from('SUPABASE_SERVICE_ROLE_KEY'));
    const artifact = join(root, 'nyam.ait');
    await writeAit(artifact, entries);

    await assert.rejects(() => verifyRelease(artifact), expectsSafeFailure(/Forbidden release marker detected/));
  });
});

test('rejects an sb secret marker in a shipped bundle', async () => {
  await withTemporaryDirectory(async (root) => {
    const entries = validEntries();
    entries.set('web/assets/app.js', Buffer.from('prefix sb_secret_example'));
    const artifact = join(root, 'nyam.ait');
    await writeAit(artifact, entries);

    await assert.rejects(() => verifyRelease(artifact), expectsSafeFailure(/Forbidden release marker detected/));
  });
});

test('rejects a UTF-16 secret marker in a shipped bundle', async () => {
  await withTemporaryDirectory(async (root) => {
    const entries = validEntries();
    entries.set('web/assets/app.js', Buffer.from('prefix NEIS_API_KEY', 'utf16le'));
    const artifact = join(root, 'nyam.ait');
    await writeAit(artifact, entries);

    await assert.rejects(() => verifyRelease(artifact), /Forbidden release marker detected/);
  });
});

test('rejects a traversing or duplicate AIT entry', async () => {
  await withTemporaryDirectory(async (root) => {
    const entries = validEntries();
    entries.set('web/../escape.js', Buffer.from('safe'));
    const artifact = join(root, 'nyam.ait');
    await writeAit(artifact, entries);

    await assert.rejects(() => verifyRelease(artifact), /unsafe entry path/);

    const duplicate = join(root, 'duplicate.ait');
    const writer = new AITWriter({
      appName: 'nyam-release-fixture',
      deploymentId: '019f9310-1c0b-78d1-adb0-11d90fed1676',
    });
    for (const [name, data] of validEntries()) writer.addFile(name, data);
    writer.addFile('web/assets/app.js', Buffer.from('console.log("duplicate")'));
    await writeFile(duplicate, await writer.toBuffer());
    await assert.rejects(() => verifyRelease(duplicate), /duplicate entry/);
  });
});

test('rejects unsupported AIT artifacts and missing unquoted HTML assets', async () => {
  await withTemporaryDirectory(async (root) => {
    const unsupported = validEntries();
    unsupported.set('web/assets/payload.exe', Buffer.from('safe'));
    const unsupportedArtifact = join(root, 'unsupported.ait');
    await writeAit(unsupportedArtifact, unsupported);
    await assert.rejects(() => verifyRelease(unsupportedArtifact), /unsupported artifact/);

    const missingAsset = validEntries();
    missingAsset.set('web/index.html', Buffer.from('<script src=/assets/missing.js></script>'));
    const missingArtifact = join(root, 'missing-asset.ait');
    await writeAit(missingArtifact, missingAsset);
    await assert.rejects(() => verifyRelease(missingArtifact), /references an asset that is not in the bundle/);
  });
});

test('does not bypass content checks when the web bundle parent path includes docs', async () => {
  await withTemporaryDirectory(async (root) => {
    const bundle = join(root, 'web');
    const entries = validEntries();
    entries.set('web/assets/app.js', Buffer.from('sk_live_example'));
    await createWebBundle(bundle, entries);

    await assert.rejects(() => verifyWebRelease(bundle), expectsSafeFailure(/Forbidden release marker detected/));
  }, 'docs-parent-');
});

test('rejects a symbolic-link web root and an extra level image', async () => {
  await withTemporaryDirectory(async (root) => {
    const bundle = join(root, 'bundle');
    await createWebBundle(bundle);
    const linkedRoot = join(root, 'linked-bundle');
    await symlink(bundle, linkedRoot);
    await assert.rejects(() => verifyWebRelease(linkedRoot), /must not be a symbolic link/);

    await writeFile(join(bundle, 'growth', 'level-8.png'), PNG);
    await assert.rejects(() => verifyWebRelease(bundle), /Expected exactly seven non-empty level PNG assets/);
  });
});
