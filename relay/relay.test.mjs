import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { test } from 'node:test';
import { limits, makeLimiter, makeServer, upstreamBody } from './relay.mjs';

const haggle = (extra = {}) => ({
  messages: [{ role: 'system', content: 'You are Sal.' }, { role: 'user', content: 'one more night?' }], ...extra,
});

test('the client cannot pick the model or the reply size', () => {
  const b = upstreamBody(haggle({ model: 'deepseek-reasoner', max_tokens: 100000, temperature: 50, stream: true }));
  assert.equal(b.model, 'deepseek-chat');
  assert.equal(b.max_tokens, limits.replyTokens);
  assert.equal(b.temperature, 1.3);
  assert.equal(b.stream, undefined);
});

test('anything that is not a haggle is refused', () => {
  assert.equal(upstreamBody({}), null);
  assert.equal(upstreamBody({ messages: [{ role: 'user', content: 'hi' }, { role: 'user', content: 'hi' }] }), null);
  assert.equal(upstreamBody(haggle({ messages: [{ role: 'system', content: 'x' }, { role: 'user', content: 'y'.repeat(limits.lineChars + 1) }] })), null);
  assert.equal(upstreamBody({ messages: Array(limits.messages + 1).fill({ role: 'system', content: 'x' }) }), null);
  assert.equal(upstreamBody({ messages: [{ role: 'system', content: 'x' }, { role: 'system', content: 'y' }] }), null);
});

test('an address is limited, and its window ends', () => {
  let t = 0; const allow = makeLimiter(() => t);
  for (let i = 0; i < limits.perAddress; i++) assert.equal(allow('a'), true);
  assert.equal(allow('a'), false);
  assert.equal(allow('b'), true);
  t = limits.windowMs; assert.equal(allow('a'), true);
});

test('the daily cap holds across addresses and resets', () => {
  let t = 0; const allow = makeLimiter(() => t);
  for (let i = 0; i < limits.perDay; i++) assert.equal(allow(`a${i}`), true);
  assert.equal(allow('fresh'), false);
  t = 24 * 3600 * 1000; assert.equal(allow('fresh'), true);
});

test('a request goes through with the key, and the key never comes back', async () => {
  let seen;
  const fake = createServer((req, res) => {
    let b = ''; req.on('data', (c) => (b += c));
    req.on('end', () => { seen = { auth: req.headers.authorization, body: JSON.parse(b) }; res.end('{"choices":[]}'); });
  });
  await new Promise((r) => fake.listen(0, r));
  const relay = makeServer({ key: 'secret', upstream: `http://127.0.0.1:${fake.address().port}/` });
  await new Promise((r) => relay.listen(0, r));
  const url = `http://127.0.0.1:${relay.address().port}`;
  const ok = await fetch(`${url}/chat`, { method: 'POST', body: JSON.stringify(haggle()) });
  assert.equal(ok.status, 200);
  assert.equal(seen.auth, 'Bearer secret');
  assert.ok(!(await ok.text()).includes('secret'));
  assert.equal((await fetch(`${url}/chat`, { method: 'POST', body: 'nope' })).status, 400);
  assert.equal((await fetch(`${url}/anything`)).status, 404);
  assert.equal(await (await fetch(`${url}/health`)).text(), 'ok');
  relay.close(); fake.close();
});
