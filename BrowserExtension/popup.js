const byId = id => document.getElementById(id);
let busy = false;
async function update(force = false) {
  if (busy) return;
  busy = true;
  try {
    const status = await chrome.runtime.sendMessage({ type: 'status', force });
    if (!status) throw new Error();
    const browser = status.browser === 'edge' ? 'Edge' : 'Chrome';
    byId('browser').textContent = browser;
    byId('connection').textContent = status.connected ? '本机通信已连接' : status.available && !status.error ? '本机组件可用' : '等待连接';
    const known = status.activeCount > 0 && status.totalBytes > 0;
    const fraction = known ? status.receivedBytes / status.totalBytes : 0;
    byId('progress').textContent = known ? `${Math.min(99, Math.floor(fraction * 100))}%` : status.activeCount ? '下载中' : '暂无下载';
    byId('bar').hidden = !known; byId('bar').value = fraction;
    byId('summary').textContent = status.activeCount
      ? `${status.activeCount} 个正在下载${status.unknownCount ? `，其中 ${status.unknownCount} 个总大小未知` : ''}${status.pausedCount ? `；另有 ${status.pausedCount} 个暂停` : ''}`
      : status.pausedCount ? `${status.pausedCount} 个下载已暂停` : '开始下载后，任务栏会显示独立的文件下载项。';
    byId('hint').textContent = status.error || (status.available
      ? '打开 TaskDock 即可逐项查看文件名和进度。完成后保留任务，可打开文件或所在文件夹；暂停保留，总大小未知时不显示百分比。'
      : `首次使用：在 TaskDock「设置 → 通用 → 浏览器下载进度」点击「连接 ${browser}」，再点下方检查连接。`);
  } catch (_) { byId('hint').textContent = '暂时无法读取扩展状态，请重新打开扩展或重新加载。'; }
  finally { busy = false; }
}
byId('retry').addEventListener('click', () => update(true));
update(true);
setInterval(update, 1000);
