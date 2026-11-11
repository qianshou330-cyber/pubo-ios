import { randomBytes } from 'node:crypto';
import { writeFile } from 'node:fs/promises';
import { setTimeout as delay } from 'node:timers/promises';

// All calls use start-backend's loopback-only API. Credentials stay in memory.
export async function prepareNotificationChecks(api, resultPath) {
  const checks = {};
  async function fail(name) {
    await writeFile(resultPath, JSON.stringify({ status: 'FAIL', failedCheck: name, checks, productionAPIRequests: 0 }, null, 2));
    throw new Error('NOTIFICATION_CONTRACT_' + name);
  }
  async function check(name, condition) {
    if (!condition) await fail(name);
    checks[name] = true;
  }
  async function eventually(name, read, matches) {
    for (let attempt = 0; attempt < 12; attempt++) {
      const value = await read();
      if (matches(value)) { checks[name] = true; return value; }
      await delay(400);
    }
    await fail(name);
  }

  const user = name => api('signup', { username: 'notice_' + name, password: randomBytes(24).toString('hex') });
  const recipient = await user('recipient');
  const second = await user('second');
  const third = await user('third');
  const mine = (path, fields = {}) => api(path, fields, recipient.token);
  const post = async (author, fields) => (await api('notes/create', fields, author.token)).createdNote;
  const original = await post(recipient, { text: 'Notification integration original' });
  const mention = await post(second, { text: '@' + recipient.username + ' public mention' });
  const direct = await post(second, { text: 'Specified notification integration note', visibility: 'specified', visibleUserIds: [recipient.id] });

  const mentions = await mine('notes/mentions', { limit: 10 });
  await check('mentionsContainPublicAndSpecified', [mention.id, direct.id].every(id => mentions.some(note => note.id === id)));
  const specified = await mine('notes/mentions', { limit: 10, visibility: 'specified' });
  await check('specifiedOnly', specified.some(note => note.id === direct.id) && specified.every(note => note.visibility === 'specified') && !specified.some(note => note.id === mention.id));
  const outsider = await api('notes/mentions', { limit: 10, visibility: 'specified' }, third.token);
  await check('privateRecipientsIsolated', !outsider.some(note => note.id === direct.id));

  for (const actor of [second, third]) {
    await api('notes/reactions/create', { noteId: original.id, reaction: '❤️' }, actor.token);
    await post(actor, { renoteId: original.id });
  }
  const grouped = (fields = {}) => mine('i/notifications-grouped', { limit: 20, markAsRead: false, ...fields });
  const participants = users => [second.id, third.id].every(id => users.some(user => user?.id === id));
  await eventually('filteredReactionGroup', () => grouped({ includeTypes: ['reaction'] }), rows =>
    rows.length === 1 && rows[0].type === 'reaction:grouped' && rows[0].note?.id === original.id &&
    participants(rows[0].reactions.map(entry => entry.user)));
  await eventually('filteredRenoteGroup', () => grouped({ includeTypes: ['renote'] }), rows =>
    rows.length === 1 && rows[0].type === 'renote:grouped' && participants(rows[0].users));
  const all = await grouped({ limit: 1 });
  const older = await grouped({ limit: 6, untilId: all[0].id });
  await check('olderCursorAdvances', older.length > 0 && older.every(row => row.id !== all[0].id));
  const unread = () => mine('i');
  await eventually('backgroundReadPreservesBadge', unread, me => me.hasUnreadNotification && me.unreadNotificationsCount > 0);
  await grouped({ markAsRead: true });
  const isRead = me => me.hasUnreadNotification === false && me.unreadNotificationsCount === 0;
  await eventually('openingAllClearsServerBadge', unread, isRead);
  await mine('notifications/test-notification');
  await eventually('newNotificationRestoresServerBadge', unread, me => me.unreadNotificationsCount > 0);
  await mine('notifications/mark-all-as-read');
  await eventually('explicitMarkAllClearsServerBadge', unread, isRead);
  await mine('notifications/test-notification');
  await eventually('unreadReadyForNativeTab', unread, me => me.unreadNotificationsCount > 0);
  await writeFile(resultPath, JSON.stringify({ status: 'PASS', checks, productionAPIRequests: 0 }, null, 2));
  return { context: { token: recipient.token, mentionID: mention.id, directID: direct.id }, isRead: async () => isRead(await unread()) };
}
