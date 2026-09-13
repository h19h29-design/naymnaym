import test from 'node:test';
import assert from 'node:assert/strict';
import { developmentSettings } from './install-development.mjs';

test('development app settings contain only the separate client token and loopback endpoint', () => {
  const privateConfig={apiKey:'synthetic-provider-only',clientToken:'synthetic-client-token-for-local-install-only'};
  const ios=developmentSettings(privateConfig,'ios');
  assert.deepEqual(ios,{endpoint:'http://127.0.0.1:64918/v1/meal-coach',accessToken:privateConfig.clientToken});
  assert.equal(JSON.stringify(ios).includes(privateConfig.apiKey),false);
  assert.equal(developmentSettings(privateConfig,'android').endpoint,'http://10.0.2.2:64918/v1/meal-coach');
  assert.throws(()=>developmentSettings({...privateConfig,clientToken:privateConfig.apiKey},'ios'));
  assert.throws(()=>developmentSettings(privateConfig,'production'));
  assert.throws(()=>developmentSettings({...privateConfig,clientToken:'short'},'ios'));
});
