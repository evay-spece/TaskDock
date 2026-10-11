#!/bin/zsh
set -euo pipefail

project_root='/Users/chenhuang/Documents/Codex/2026-10-06/taskdock-continuation/work/taskbar-minimize-animation'
cd "$project_root"

if ! code="$(./scripts/beta-code issue)"; then
  print '发码失败。请把上面的错误信息发给我。'
  [[ "${TASKDOCK_ISSUER_NO_WAIT:-}" == 1 ]] || read -r '?按回车关闭窗口…'
  exit 1
fi

if [[ "$code" != TD7.* ]]; then
  print '发码失败：生成的内容不是 TaskDock 内测码。'
  [[ "${TASKDOCK_ISSUER_NO_WAIT:-}" == 1 ]] || read -r '?按回车关闭窗口…'
  exit 1
fi

if [[ "${TASKDOCK_ISSUER_NO_CLIPBOARD:-}" != 1 ]]; then
  print -rn -- "$code" | pbcopy
fi

print ''
print '✅ 已生成一枚新的 TaskDock 7 天内测码，并复制到剪贴板。'
print '在小红书聊天框按 Command + V，即可发给用户。'
print ''
print -- "$code"
print ''
[[ "${TASKDOCK_ISSUER_NO_WAIT:-}" == 1 ]] || read -r '?按回车关闭窗口…'
