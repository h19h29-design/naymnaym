import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, readFile, stat, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { prepareConfiguration } from './prepare.mjs';

test('prepares private disabled configuration without overwriting an existing file', async () => {
  const directory=await mkdtemp(join(tmpdir(),'meal-coach-config-test-'));
  try {
    const path=await prepareConfiguration(directory);
    const original=await readFile(path,'utf8');
    const values=JSON.parse(original);
    assert.equal(values.apiKey,'');
    assert.equal(values.enabled,false);
    assert.ok(values.clientToken.length>=32);
    assert.equal((await stat(path)).mode&0o077,0);
    await prepareConfiguration(directory);
    assert.equal(await readFile(path,'utf8'),original);
  } finally {await rm(directory,{recursive:true,force:true});}
});
