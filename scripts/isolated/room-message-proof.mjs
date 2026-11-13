// Exact real-response filtering. Never synthesizes a successful receipt from input.
export function validRoomMessageNonce(nonce) {
  return typeof nonce === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(nonce);
}
export function roomMessageReceipt(rows, {roomId, userId, nonce}) {
  if (!validRoomMessageNonce(nonce) || typeof roomId !== 'string' || !roomId || typeof userId !== 'string' || !userId || !Array.isArray(rows)) {
    throw new TypeError('Invalid room receipt parameters');
  }
  return {roomId, messageIds: rows.filter(row => row && row.fromUserId === userId && row.text === 'Native room message proof ' + nonce && typeof row.id === 'string' && row.id.length > 0).map(row => row.id)};
}
