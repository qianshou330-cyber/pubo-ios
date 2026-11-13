import test from 'node:test';
import assert from 'node:assert/strict';
import {roomMessageReceipt, validRoomMessageNonce} from './room-message-proof.mjs';
const nonce = '00112233-4455-6677-8899-aabbccddeeff';
const scope = {roomId: 'seeded-room', userId: 'alice', nonce};
const real = {id: 'new-message', fromUserId: 'alice', text: 'Native room message proof ' + nonce};
test('nonce validation rejects malformed input', () => {
  assert.equal(validRoomMessageNonce(nonce), true);
  for (const invalid of ['', null, 123, 'old', nonce+'\n', nonce+'x']) {
    assert.equal(validRoomMessageNonce(invalid), false);
    assert.throws(() => roomMessageReceipt([], {...scope, nonce: invalid}));
  }
});
test('only exact author, full nonce text and actual nonempty ID produce receipts; duplicates remain detectable', () => {
  const stale = [ {...real, text: 'Native room message proof'}, {...real, fromUserId: 'bob'}, {...real, text: real.text.replace('00112233','99112233')}, {...real, id: ''}, null ];
  assert.deepEqual(roomMessageReceipt(stale, scope), {roomId:'seeded-room',messageIds:[]});
  assert.deepEqual(roomMessageReceipt([...stale, real], scope), {roomId:'seeded-room',messageIds:['new-message']});
  assert.deepEqual(roomMessageReceipt([real, real], scope).messageIds, ['new-message','new-message']);
});
