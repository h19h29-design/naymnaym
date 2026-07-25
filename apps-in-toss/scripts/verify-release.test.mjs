import assert from 'node:assert/strict';
import { mkdtemp, mkdir, readFile, rm, symlink, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';
import { deflateSync } from 'node:zlib';

import { AITWriter, AppsInTossBundle } from '@apps-in-toss/ait-format';
import { AITBundle } from '@apps-in-toss/ait-format-proto';
import { unzipSync, zipSync } from 'fflate';
import { verifyRelease, verifyWebRelease } from './verify-release.mjs';

const PNG_SIGNATURE = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);

function crc32(bytes) {
  let crc = 0xffffffff;
  for (const byte of bytes) {
    crc ^= byte;
    for (let bit = 0; bit < 8; bit += 1) crc = (crc >>> 1) ^ (crc & 1 ? 0xedb88320 : 0);
  }
  return (crc ^ 0xffffffff) >>> 0;
}

function pngChunk(type, data) {
  const chunk = Buffer.alloc(12 + data.length);
  chunk.writeUInt32BE(data.length, 0);
  chunk.write(type, 4, 4, 'ascii');
  data.copy(chunk, 8);
  chunk.writeUInt32BE(crc32(chunk.subarray(4, 8 + data.length)), 8 + data.length);
  return chunk;
}

function validPng({ bitDepth = 8, colorType = 6, compression = 0, filter = 0, interlace = 0 } = {}) {
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(1, 0);
  ihdr.writeUInt32BE(1, 4);
  ihdr.set([bitDepth, colorType, compression, filter, interlace], 8);
  return Buffer.concat([
    PNG_SIGNATURE,
    pngChunk('IHDR', ihdr),
    pngChunk('IDAT', deflateSync(Buffer.from([0, 0, 0, 0, 0]))),
    pngChunk('IEND', Buffer.alloc(0)),
  ]);
}

const PNG = validPng();

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

async function writeAit(path, entries, options = {}) {
  const writer = new AITWriter({
    appName: 'nyam-release-fixture',
    deploymentId: '019f9310-1c0b-78d1-adb0-11d90fed1676',
  });
  if (options.metadata) writer.setMetadata(options.metadata);
  for (const [name, data] of entries) writer.addFile(name, data, options.fileOptions?.get(name));
  await writeFile(path, await writer.toBuffer());
}

function aitParts(buffer) {
  const bundleLength = Number(buffer.readBigUInt64BE(12));
  const zipLengthOffset = 20 + bundleLength;
  const zipOffset = zipLengthOffset + 8;
  const zipLength = Number(buffer.readBigUInt64BE(zipLengthOffset));
  return { zipLengthOffset, zipOffset, zipLength, tailOffset: zipOffset + zipLength };
}

function replaceZip(buffer, zip) {
  const parts = aitParts(buffer);
  const prefix = Buffer.from(buffer.subarray(0, parts.zipOffset));
  prefix.writeBigUInt64BE(BigInt(zip.length), parts.zipLengthOffset);
  return Buffer.concat([prefix, zip, buffer.subarray(parts.tailOffset)]);
}

function replaceBundle(buffer, bundle) {
  const bundleLength = Number(buffer.readBigUInt64BE(12));
  const bundleEnd = 20 + bundleLength;
  const encoded = Buffer.from(AITBundle.encode(bundle).finish());
  const prefix = Buffer.from(buffer.subarray(0, 12));
  const length = Buffer.alloc(8);
  length.writeBigUInt64BE(BigInt(encoded.length));
  return Buffer.concat([prefix, length, encoded, buffer.subarray(bundleEnd)]);
}

function zipCentralEntries(zip) {
  const eocd = zip.lastIndexOf(Buffer.from([80, 75, 5, 6]));
  assert.notEqual(eocd, -1, 'fixture ZIP has EOCD');
  const count = zip.readUInt16LE(eocd + 10);
  let offset = zip.readUInt32LE(eocd + 16);
  const entries = [];
  for (let index = 0; index < count; index += 1) {
    assert.equal(zip.readUInt32LE(offset), 0x02014b50, 'fixture ZIP has central entry');
    const nameLength = zip.readUInt16LE(offset + 28);
    const extraLength = zip.readUInt16LE(offset + 30);
    const commentLength = zip.readUInt16LE(offset + 32);
    const name = zip.subarray(offset + 46, offset + 46 + nameLength).toString('utf8');
    entries.push({ offset, name, nameLength, extraLength, commentLength });
    offset += 46 + nameLength + extraLength + commentLength;
  }
  return { eocd, entries };
}

function mutateZipEntry(zip, name, mutate) {
  const copy = Buffer.from(zip);
  const entry = zipCentralEntries(copy).entries.find((candidate) => candidate.name === name);
  assert.ok(entry, `fixture ZIP has ${name}`);
  mutate(copy, entry);
  return copy;
}

function addZipEntryComment(zip, name, comment) {
  const { eocd, entries } = zipCentralEntries(zip);
  const entry = entries.find((candidate) => candidate.name === name);
  assert.ok(entry, `fixture ZIP has ${name}`);
  const insertAt = entry.offset + 46 + entry.nameLength + entry.extraLength + entry.commentLength;
  const copy = Buffer.concat([zip.subarray(0, insertAt), comment, zip.subarray(insertAt)]);
  copy.writeUInt16LE(entry.commentLength + comment.length, entry.offset + 32);
  copy.writeUInt32LE(zip.readUInt32LE(eocd + 12) + comment.length, eocd + comment.length + 12);
  return copy;
}

function addZipEocdComment(zip, comment) {
  const { eocd } = zipCentralEntries(zip);
  assert.equal(zip.readUInt16LE(eocd + 20), 0, 'fixture ZIP has no EOCD comment');
  const copy = Buffer.concat([zip, comment]);
  copy.writeUInt16LE(comment.length, eocd + 20);
  return copy;
}

function jwtForRole(role) {
  const encode = (value) => Buffer.from(JSON.stringify(value)).toString('base64url');
  return `${encode({ alg: 'HS256', typ: 'JWT' })}.${encode({ role })}.synthetic-signature`;
}

function utf16be(value) {
  const littleEndian = Buffer.from(value, 'utf16le');
  for (let index = 0; index < littleEndian.length; index += 2) {
    [littleEndian[index], littleEndian[index + 1]] = [littleEndian[index + 1], littleEndian[index]];
  }
  return littleEndian;
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

    const windowsPath = join(root, 'windows-path.ait');
    const windowsEntries = validEntries();
    windowsEntries.set('C:/drive.js', Buffer.from('safe'));
    await writeAit(windowsPath, windowsEntries);
    await assert.rejects(() => verifyRelease(windowsPath), /unsafe entry path/);
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

test('rejects hidden ZIP entries and central-directory duplicate entries', async () => {
  await withTemporaryDirectory(async (root) => {
    const artifact = join(root, 'hidden.ait');
    await writeAit(artifact, validEntries());
    const original = await readFile(artifact);
    const reader = AppsInTossBundle.reader(original);
    const hiddenZip = zipSync({
      ...unzipSync(reader.readZipBlob()),
      'web/assets/hidden.js': Buffer.from('safe'),
    });
    await writeFile(artifact, replaceZip(original, Buffer.from(hiddenZip)));
    await assert.rejects(() => verifyRelease(artifact), /ZIP index/);

    const duplicate = join(root, 'zip-duplicate.ait');
    await writeAit(duplicate, validEntries());
    const duplicateOriginal = await readFile(duplicate);
    const duplicateParts = aitParts(duplicateOriginal);
    const zip = Buffer.from(duplicateOriginal.subarray(duplicateParts.zipOffset, duplicateParts.tailOffset));
    const { eocd, entries } = zipCentralEntries(zip);
    const first = entries[0];
    const firstLength = 46 + first.nameLength + first.extraLength + first.commentLength;
    const duplicateCentral = Buffer.concat([
      zip.subarray(0, eocd),
      zip.subarray(first.offset, first.offset + firstLength),
      zip.subarray(eocd),
    ]);
    const duplicateEocd = eocd + firstLength;
    duplicateCentral.writeUInt16LE(entries.length + 1, duplicateEocd + 8);
    duplicateCentral.writeUInt16LE(entries.length + 1, duplicateEocd + 10);
    duplicateCentral.writeUInt32LE(zip.readUInt32LE(eocd + 12) + firstLength, duplicateEocd + 12);
    await writeFile(duplicate, replaceZip(duplicateOriginal, duplicateCentral));
    await assert.rejects(() => verifyRelease(duplicate), /duplicate ZIP entry/);
  });
});

test('rejects central-directory size and digest mismatches', async () => {
  await withTemporaryDirectory(async (root) => {
    const sizeArtifact = join(root, 'size.ait');
    await writeAit(sizeArtifact, validEntries());
    const original = await readFile(sizeArtifact);
    const parts = aitParts(original);
    const zip = Buffer.from(original.subarray(parts.zipOffset, parts.tailOffset));
    const wrongSize = mutateZipEntry(zip, 'web/assets/app.js', (copy, entry) => {
      copy.writeUInt32LE(copy.readUInt32LE(entry.offset + 24) + 1, entry.offset + 24);
    });
    await writeFile(sizeArtifact, replaceZip(original, wrongSize));
    await assert.rejects(() => verifyRelease(sizeArtifact), /local ZIP header mismatch/);

    const digestArtifact = join(root, 'digest.ait');
    await writeAit(digestArtifact, validEntries());
    const digestOriginal = await readFile(digestArtifact);
    const bundle = AppsInTossBundle.reader(digestOriginal).bundle;
    bundle.index.find((entry) => entry.name === 'web/assets/app.js').sha256Hex = '0'.repeat(64);
    await writeFile(digestArtifact, replaceBundle(digestOriginal, bundle));
    await assert.rejects(() => verifyRelease(digestArtifact), /invalid entry digest/);
  });
});

test('rejects metadata secrets and non-anon JWT roles without echoing values', async () => {
  await withTemporaryDirectory(async (root) => {
    const metadata = join(root, 'metadata.ait');
    await writeAit(metadata, validEntries(), { metadata: { extra: { private: 'sb_secret_example' } } });
    await assert.rejects(() => verifyRelease(metadata), expectsSafeFailure(/Forbidden release marker detected/));

    const jwt = join(root, 'jwt.ait');
    const entries = validEntries();
    entries.set('web/assets/app.js', Buffer.from(jwtForRole('authenticated')));
    await writeAit(jwt, entries);
    await assert.rejects(() => verifyRelease(jwt), /Forbidden JWT role detected/);
  });
});

test('rejects secrets in deployment metadata, entry names, and ZIP comments', async () => {
  await withTemporaryDirectory(async (root) => {
    const deployment = join(root, 'deployment.ait');
    await writeAit(deployment, validEntries());
    const deploymentOriginal = await readFile(deployment);
    const deploymentBundle = AppsInTossBundle.reader(deploymentOriginal).bundle;
    deploymentBundle.deploymentId = 'sb_secret_example';
    await writeFile(deployment, replaceBundle(deploymentOriginal, deploymentBundle));
    await assert.rejects(() => verifyRelease(deployment), expectsSafeFailure(/Forbidden release marker detected/));

    const filename = join(root, 'filename.ait');
    const filenameEntries = validEntries();
    filenameEntries.set('web/assets/sb_secret_example.js', Buffer.from('safe'));
    await writeAit(filename, filenameEntries);
    await assert.rejects(() => verifyRelease(filename), expectsSafeFailure(/Forbidden release marker detected/));

    const entryComment = join(root, 'entry-comment.ait');
    await writeAit(entryComment, validEntries());
    const entryCommentOriginal = await readFile(entryComment);
    const entryCommentParts = aitParts(entryCommentOriginal);
    const entryCommentZip = entryCommentOriginal.subarray(entryCommentParts.zipOffset, entryCommentParts.tailOffset);
    await writeFile(
      entryComment,
      replaceZip(entryCommentOriginal, addZipEntryComment(entryCommentZip, 'web/assets/app.js', Buffer.from('sb_secret_example'))),
    );
    await assert.rejects(() => verifyRelease(entryComment), expectsSafeFailure(/Forbidden release marker detected/));

    const eocdComment = join(root, 'eocd-comment.ait');
    await writeAit(eocdComment, validEntries());
    const eocdCommentOriginal = await readFile(eocdComment);
    const eocdCommentParts = aitParts(eocdCommentOriginal);
    const eocdCommentZip = eocdCommentOriginal.subarray(eocdCommentParts.zipOffset, eocdCommentParts.tailOffset);
    await writeFile(
      eocdComment,
      replaceZip(eocdCommentOriginal, addZipEocdComment(eocdCommentZip, Buffer.from('sb_secret_example'))),
    );
    await assert.rejects(() => verifyRelease(eocdComment), expectsSafeFailure(/Forbidden release marker detected/));
  });
});

test('rejects local ZIP header CRC and size mismatches and data descriptors', async () => {
  await withTemporaryDirectory(async (root) => {
    for (const [label, fieldOffset] of [['crc', 14], ['compressed-size', 18], ['uncompressed-size', 22]]) {
      const artifact = join(root, `${label}.ait`);
      await writeAit(artifact, validEntries());
      const original = await readFile(artifact);
      const parts = aitParts(original);
      const zip = Buffer.from(original.subarray(parts.zipOffset, parts.tailOffset));
      const tampered = mutateZipEntry(zip, 'web/assets/app.js', (copy, entry) => {
        const localOffset = copy.readUInt32LE(entry.offset + 42);
        copy.writeUInt32LE(copy.readUInt32LE(localOffset + fieldOffset) + 1, localOffset + fieldOffset);
      });
      await writeFile(artifact, replaceZip(original, tampered));
      await assert.rejects(() => verifyRelease(artifact), /local ZIP header mismatch/);
    }

    const descriptor = join(root, 'data-descriptor.ait');
    await writeAit(descriptor, validEntries());
    const descriptorOriginal = await readFile(descriptor);
    const descriptorParts = aitParts(descriptorOriginal);
    const descriptorZip = Buffer.from(descriptorOriginal.subarray(descriptorParts.zipOffset, descriptorParts.tailOffset));
    const descriptorFlags = mutateZipEntry(descriptorZip, 'web/assets/app.js', (copy, entry) => {
      const localOffset = copy.readUInt32LE(entry.offset + 42);
      copy.writeUInt16LE(copy.readUInt16LE(entry.offset + 8) | 0x0008, entry.offset + 8);
      copy.writeUInt16LE(copy.readUInt16LE(localOffset + 6) | 0x0008, localOffset + 6);
    });
    await writeFile(descriptor, replaceZip(descriptorOriginal, descriptorFlags));
    await assert.rejects(() => verifyRelease(descriptor), /unsupported ZIP entry/);
  });
});

test('rejects odd-alignment UTF-16LE and UTF-16BE markers', async () => {
  await withTemporaryDirectory(async (root) => {
    const entries = validEntries();
    entries.set('web/assets/app.js', Buffer.concat([Buffer.from([0]), Buffer.from('NEIS_API_KEY', 'utf16le')]));
    entries.set('web/assets/app.js.map', Buffer.concat([Buffer.from([0xff]), utf16be('SUPABASE_SERVICE_ROLE_KEY')]));
    const artifact = join(root, 'utf16.ait');
    await writeAit(artifact, entries);
    await assert.rejects(() => verifyRelease(artifact), /Forbidden release marker detected/);
  });
});

test('rejects corrupt, truncated, and malformed PNG assets', async () => {
  await withTemporaryDirectory(async (root) => {
    const corrupt = validEntries();
    const crcBroken = Buffer.from(PNG);
    crcBroken[crcBroken.length - 5] ^= 1;
    corrupt.set('web/growth/level-1.png', crcBroken);
    const corruptArtifact = join(root, 'corrupt.ait');
    await writeAit(corruptArtifact, corrupt);
    await assert.rejects(() => verifyRelease(corruptArtifact), /invalid level PNG/);

    const truncated = validEntries();
    truncated.set('web/growth/level-1.png', PNG.subarray(0, 20));
    const truncatedArtifact = join(root, 'truncated.ait');
    await writeAit(truncatedArtifact, truncated);
    await assert.rejects(() => verifyRelease(truncatedArtifact), /invalid level PNG/);

    const invalidBitDepth = validEntries();
    invalidBitDepth.set('web/growth/level-1.png', validPng({ bitDepth: 0 }));
    const invalidBitDepthArtifact = join(root, 'invalid-bit-depth.ait');
    await writeAit(invalidBitDepthArtifact, invalidBitDepth);
    await assert.rejects(() => verifyRelease(invalidBitDepthArtifact), /invalid level PNG/);
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
    await assert.rejects(() => verifyWebRelease(bundle), /invalid level PNG/);
  });
});
