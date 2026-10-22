/* Completed local paths support explicit user open/reveal actions. Never include URLs. */
(function (root) {
  const MAX = Number.MAX_SAFE_INTEGER;
  function aggregate(items) {
    let receivedBytes = 0, totalBytes = 0, activeCount = 0, unknownCount = 0, pausedCount = 0;
    for (const item of items) {
      if (item.state !== 'in_progress') continue;
      if (item.paused) { pausedCount++; continue; }
      activeCount++;
      const total = item.totalBytes;
      const received = item.bytesReceived;
      if (!Number.isSafeInteger(total) || total <= 0 || !Number.isSafeInteger(received) || received < 0 || totalBytes > MAX - total) {
        unknownCount++; continue;
      }
      totalBytes += total;
      receivedBytes += Math.min(received, total);
    }
    return { receivedBytes, totalBytes, activeCount, unknownCount, pausedCount };
  }
  function tasks(items, now = Date.now()) {
    return items.filter(item => (item.state === 'in_progress' || (item.state === 'complete' && Number.isFinite(Date.parse(item.endTime)) && Date.parse(item.endTime) <= now + 2000 && now - Date.parse(item.endTime) < 30 * 60 * 1000 && item.exists !== false && String(item.filename || '').startsWith('/'))) && Number.isSafeInteger(item.id) && item.id >= 0)
      .sort((a, b) => Number(a.state === 'complete') - Number(b.state === 'complete') || (a.state === 'complete' ? b.id - a.id : a.id - b.id)).slice(0, 128).map(item => {
        const basename = String(item.filename || '').split(/[\\/]/).pop()
          .replace(/[\u0000-\u001f\u007f-\u009f\u202a-\u202e\u2066-\u2069]/g, '').trim();
        const filename = [...basename].slice(0, 255).join('') || `下载 #${item.id}`;
        const total = Number.isSafeInteger(item.totalBytes) && item.totalBytes > 0 ? item.totalBytes : 0;
        const received = Number.isSafeInteger(item.bytesReceived) && item.bytesReceived > 0 ? item.bytesReceived : 0;
        return { id: item.id, filename, receivedBytes: total ? Math.min(received, total) : received,
          totalBytes: total, paused: Boolean(item.paused),
          ...(item.state === 'complete' ? { complete: true, localPath: item.filename, completedAt: Date.parse(item.endTime) / 1000 } : {}) };
      });
  }
  root.TaskDockDownloadProgress = { aggregate, tasks };
  if (typeof module !== 'undefined') module.exports = { aggregate, tasks };
})(globalThis);
