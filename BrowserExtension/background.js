importScripts('progress.js');

const HOST = 'com.taskdock.browser_progress';
const browserName = /Edg\//.test(navigator.userAgent) ? 'edge' : 'chrome';
let port = null, pollTimer = null, changeTimer = null, idleTimer = null;
let scanning = false, rescan = false, forceRescan = false, retryAt = 0, retryDelay = 2000;
let lastPayload = '';
const trackedPromise = chrome.storage.local.get('trackedDownloadIds').then(saved => new Set(saved.trackedDownloadIds || []));
let state = { browser: browserName, available: false, connected: false, error: '',
  receivedBytes: 0, totalBytes: 0, activeCount: 0, unknownCount: 0, pausedCount: 0, taskCount: 0 };
const profilePromise = chrome.storage.local.get('profileId').then(async saved => {
  if (typeof saved.profileId === 'string' && /^[0-9a-f-]{36}$/.test(saved.profileId)) return saved.profileId;
  const id = crypto.randomUUID();
  await chrome.storage.local.set({ profileId: id });
  return id;
});

function badge() {
  const text = state.activeCount && state.totalBytes > 0
    ? `${Math.min(99, Math.floor(state.receivedBytes / state.totalBytes * 100))}%`
    : state.activeCount ? '↓' : '';
  chrome.action.setBadgeText({ text }).catch(() => {});
  chrome.action.setBadgeBackgroundColor({ color: '#3478F6' }).catch(() => {});
}
function connection() {
  if (port) return port;
  const opened = chrome.runtime.connectNative(HOST);
  port = opened;
  opened.onMessage.addListener(message => {
    if (port !== opened) return;
    if (!message || message.version !== 1 || message.ok !== true) {
      state.error = '本机组件拒绝了进度信息，请更新 TaskDock 和扩展。';
      opened.disconnect(); port = null; state.connected = false; return;
    }
    state.available = true; state.connected = true; state.error = '';
    retryAt = 0; retryDelay = 2000;
    // No download means no reason to keep the native process / worker alive.
    if (!state.pendingCount) {
      clearTimeout(idleTimer);
      idleTimer = setTimeout(() => {
        if (port === opened && !state.pendingCount) { port = null; opened.disconnect(); state.connected = false; }
      }, 250);
    }
  });
  opened.onDisconnect.addListener(() => {
    const error = chrome.runtime.lastError; // consume the browser's disconnect error
    if (port !== opened) return;
    port = null; state.connected = false; lastPayload = '';
    state.error = error ? '尚未连接本机组件。请在 TaskDock 设置中连接此浏览器。' : '本机连接已断开，下载期间会自动重连。';
    retryAt = Date.now() + retryDelay;
    retryDelay = Math.min(30000, retryDelay * 2);
  });
  return opened;
}
async function scan(forceConnect = false) {
  if (scanning) { rescan = true; forceRescan ||= forceConnect; return; }
  scanning = true;
  clearTimeout(pollTimer); pollTimer = null;
  try {
    const tracked = await trackedPromise;
    const active = await chrome.downloads.search({ state: 'in_progress' });
    for (const item of active) tracked.add(item.id);
    const completed = (await chrome.downloads.search({ state: 'complete', limit: 128, orderBy: ['-endTime'] }))
      .filter(item => item.state === 'complete' && tracked.has(item.id) && Number.isFinite(Date.parse(item.endTime)) && Date.now() - Date.parse(item.endTime) < 30 * 60 * 1000);
    const items = [...active, ...completed];
    const retainedIds = items.map(item => item.id);
    if (JSON.stringify([...tracked].sort()) !== JSON.stringify([...retainedIds].sort())) {
      tracked.clear(); for (const id of retainedIds) tracked.add(id);
    }
    await chrome.storage.local.set({ trackedDownloadIds: [...tracked].slice(-256) });
    Object.assign(state, TaskDockDownloadProgress.aggregate(items));
    const downloads = TaskDockDownloadProgress.tasks(items);
    state.taskCount = downloads.length;
    state.pendingCount = downloads.filter(item => !item.complete).length;
    const fingerprint = JSON.stringify(downloads);
    badge();
    if (state.pendingCount) { clearTimeout(idleTimer); idleTimer = null; }
    if (port || forceConnect || ((state.pendingCount || (fingerprint !== lastPayload && (downloads.length || lastPayload))) && Date.now() >= retryAt)) {
      const profile = await profilePromise;
      const payload = { version: 3, type: 'snapshot', browser: browserName, profile,
        receivedBytes: state.receivedBytes, totalBytes: state.totalBytes,
        activeCount: state.activeCount, unknownCount: state.unknownCount, downloads };
      connection().postMessage(payload);
      lastPayload = fingerprint;
    }
  } catch (_) {
    state.error = '无法同步下载进度，请检查扩展权限和 TaskDock 本机组件。';
  } finally {
    scanning = false;
    if (rescan) { const force = forceRescan; rescan = false; forceRescan = false; clearTimeout(changeTimer); changeTimer = setTimeout(() => scan(force), 100); }
    else if (state.pendingCount) pollTimer = setTimeout(() => scan(), state.activeCount ? 1000 : 5000);
  }
}
function scheduleScan() {
  clearTimeout(changeTimer);
  changeTimer = setTimeout(() => { changeTimer = null; scan(); }, 100);
}
chrome.downloads.onCreated.addListener(item => {
  if (item && Number.isSafeInteger(item.id)) trackedPromise.then(tracked => { tracked.add(item.id); scheduleScan(); });
  else scheduleScan();
});
chrome.downloads.onChanged.addListener(scheduleScan);
chrome.downloads.onErased.addListener(scheduleScan);
chrome.alarms.onAlarm.addListener(alarm => { if (alarm.name === 'taskdock-reconcile') scan(); });
chrome.runtime.onInstalled.addListener(() => scan(true));
chrome.runtime.onStartup.addListener(() => scan());
chrome.runtime.onMessage.addListener((message, sender, respond) => {
  if (sender.id !== chrome.runtime.id || message?.type !== 'status') return;
  // A popup request checks the connection even when nothing is downloading.
  scan(message.force === true).then(() => respond({ ...state })).catch(() => respond({ ...state }));
  return true;
});
chrome.alarms.create('taskdock-reconcile', { periodInMinutes: 0.5 });
scan();
