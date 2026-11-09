'use strict';
// WebUI uses only the local KernelSU/SukiSU bridge and fixed root commands.
const $ = (id) => document.getElementById(id);
const BRIDGE_PATH = '/data/adb/modules/hma_sukisu/webui-api.sh';
const COMMANDS = new Set(['status', 'install', 'start', 'stop', 'logs']);
const ACTION_IDS = ['refresh', 'install', 'start', 'stop', 'logs'];
const STATUS_MAP = {
  manager: { yes: ['已安装', 'positive'], no: ['未安装', 'warning'] },
  reboot: { ready: ['已就绪', 'positive'], pending: ['需要重启', 'warning'] },
  injection: {
    verified: ['已验证', 'positive'],
    not_verified: ['未验证', 'neutral'],
    failed_this_system_server: ['注入失败', 'error']
  },
  autostart: { enabled: ['已启用', 'positive'], disabled: ['未启用', 'neutral'] }
};
let pending = false;
let confirming = false;
let seq = 0;
let state = null;
let snackbarTimer = null;
const output = $('output');
const themeQuery = window.matchMedia ? window.matchMedia('(prefers-color-scheme: dark)') : null;

function currentTheme() {
  try { return localStorage.getItem('hma-md3-theme') || 'system'; }
  catch (_) { return 'system'; }
}
function setTheme(mode, save) {
  if (!['system', 'light', 'dark'].includes(mode)) mode = 'system';
  const dark = mode === 'dark' || (mode === 'system' && themeQuery && themeQuery.matches);
  document.documentElement.setAttribute('data-theme', dark ? 'dark' : 'light');
  document.querySelectorAll('[data-theme-option]').forEach(button => {
    button.setAttribute('aria-pressed', String(button.dataset.themeOption === mode));
  });
  if (save) { try { localStorage.setItem('hma-md3-theme', mode); } catch (_) {} }
}
setTheme(currentTheme(), false);
if (themeQuery) {
  const changed = () => { if (currentTheme() === 'system') setTheme('system', false); };
  if (themeQuery.addEventListener) themeQuery.addEventListener('change', changed);
  else if (themeQuery.addListener) themeQuery.addListener(changed);
}
document.querySelectorAll('[data-theme-option]').forEach(button =>
  button.addEventListener('click', () => setTheme(button.dataset.themeOption, true))
);

function notify(message) {
  const bar = $('snackbar');
  bar.textContent = message;
  bar.hidden = false;
  clearTimeout(snackbarTimer);
  snackbarTimer = setTimeout(() => { bar.hidden = true; }, 3500);
}
function bridgeRun(command) {
  if (!COMMANDS.has(command)) return Promise.reject(new Error('不支持的命令'));
  return new Promise((resolve, reject) => {
    if (!window.ksu || typeof window.ksu.exec !== 'function') {
      reject(new Error('未找到 KernelSU / SukiSU WebUI 接口。请从模块管理器中打开此页面。'));
      return;
    }
    const callback = '__hmaMd3Exec' + (++seq);
    let done = false;
    let watchdog;
    function cleanup() { delete window[callback]; clearTimeout(watchdog); }
    function finish(code, stdout, stderr) {
      if (done) return;
      done = true;
      cleanup();
      resolve({ code: Number(code), stdout: String(stdout || ''), stderr: String(stderr || '') });
    }
    window[callback] = finish;
    watchdog = setTimeout(() => {
      if (done) return;
      done = true;
      cleanup();
      reject(new Error('模块命令响应超时，请检查日志后重试。'));
    }, command === 'start' ? 140000 : 45000);
    try {
      const result = window.ksu.exec('sh ' + BRIDGE_PATH + ' ' + command, callback);
      if (typeof result === 'string') finish(0, result, '');
    } catch (error) {
      if (done) return;
      done = true;
      cleanup();
      reject(error);
    }
  });
}
function readFields(raw) {
  const result = Object.create(null);
  for (const line of raw.split(/\r?\n/)) {
    const cut = line.indexOf('=');
    if (cut > 0) result[line.slice(0, cut)] = line.slice(cut + 1);
  }
  return result;
}
function setMetric(id, value) {
  const def = STATUS_MAP[id][value] || ['未知', 'neutral'];
  $(id).textContent = def[0];
  $(id + '-card').dataset.tone = def[1];
}
function setNotice(message, tone) {
  $('action-notice-text').textContent = message;
  $('action-notice').dataset.tone = tone;
}
function renderStatus(data) {
  state = data;
  $('version').textContent = data.version || 'EXPERIMENTAL';
  setMetric('manager', data.installed);
  setMetric('reboot', data.reboot);
  setMetric('injection', data.injection);
  setMetric('autostart', data.autostart);
  const pid = data.server_pid && data.server_pid !== 'unknown' ? data.server_pid : '未知';
  $('device').textContent = 'system_server PID ' + pid + '  ·  模块' + (data.module === 'disabled' ? '已禁用' : '已启用');
  $('start-label').textContent = data.autostart === 'enabled' ? '检查 / 恢复注入' : '测试注入并启用';

  let summary = ['等待启用', '管理器和系统服务就绪后，可以进行注入测试。', 'neutral'];
  if (data.module === 'disabled') {
    summary = ['模块已停用', '请先在 SukiSU / KernelSU 模块管理页启用此模块。', 'warning'];
    setNotice('模块当前处于禁用状态，无法执行注入。', 'warning');
  } else if (data.reboot === 'pending') {
    summary = ['等待重新启动', '安装或迁移之后需要一次 Android 重启。', 'warning'];
    setNotice('重启要求尚未解除，请先重启系统再执行注入。', 'warning');
  } else if (data.injection === 'failed_this_system_server') {
    summary = ['注入未成功', '当前 system_server 已被安全锁定，需重启框架后恢复。', 'error'];
    setNotice('此进程的注入已失败，重复附加已被阻止。请查看下方日志。', 'error');
  } else if (data.injection === 'verified') {
    summary = ['原生后端已就绪', 'HMAService 已在当前 system_server 中完成验证。', 'positive'];
    setNotice('当前后端已通过健康检测。已配置应用的规则按需生效。', 'positive');
  } else if (data.autostart === 'enabled') {
    summary = ['等待后端恢复', '自动启动已开启，正在等待当前进程完成注入验证。', 'neutral'];
    setNotice('自动恢复监测已启用。若长时间未验证，请读取诊断日志。', 'neutral');
  } else {
    setNotice('首次安装后请重启，再执行一次注入测试。', 'neutral');
  }
  $('summary-title').textContent = summary[0];
  $('summary-desc').textContent = summary[1];
  $('status-hero').dataset.tone = summary[2];
  syncButtons();
}
function syncButtons() {
  const disabled = !state || state.module === 'disabled';
  const locked = pending || confirming;
  ACTION_IDS.forEach(id => { $(id).disabled = locked; });
  $('install').disabled = locked || disabled || (state && state.bundled !== 'yes');
  $('start').disabled = locked || disabled || (state && state.reboot === 'pending') ||
    (state && state.injection === 'failed_this_system_server');
  $('stop').disabled = locked || disabled || !state || state.autostart !== 'enabled';
  $('copy').disabled = locked || !output.textContent.trim();
}
function showOutput(text) {
  output.textContent = text || '命令已执行，未返回输出。';
}
async function refreshStatus() {
  const response = await bridgeRun('status');
  if (response.code !== 0) throw new Error(response.stderr || response.stdout || '无法获取模块状态');
  renderStatus(readFields(response.stdout));
}
function requestConfirmation(title, description) {
  return new Promise(resolve => {
    confirming = true;
    syncButtons();
    const backdrop = $('confirm-backdrop');
    const accept = $('confirm-accept');
    const cancel = $('confirm-cancel');
    const dialog = backdrop.querySelector('.confirm-dialog');
    const oldFocus = document.activeElement;
    $('confirm-title').textContent = title;
    $('confirm-body').textContent = description;
    backdrop.hidden = false;
    function finish(yes) {
      accept.removeEventListener('click', acceptClick);
      cancel.removeEventListener('click', cancelClick);
      backdrop.removeEventListener('click', outside);
      document.removeEventListener('keydown', keydown);
      backdrop.hidden = true;
      confirming = false;
      syncButtons();
      if (oldFocus && oldFocus.focus) oldFocus.focus();
      resolve(yes);
    }
    const acceptClick = () => finish(true);
    const cancelClick = () => finish(false);
    const outside = event => { if (event.target === backdrop) finish(false); };
    const keydown = event => {
      if (event.key === 'Escape') { event.preventDefault(); finish(false); }
      if (event.key === 'Tab') {
        const target = document.activeElement;
        if (event.shiftKey && target === cancel) { event.preventDefault(); accept.focus(); }
        else if (!event.shiftKey && target === accept) { event.preventDefault(); cancel.focus(); }
      }
    };
    accept.addEventListener('click', acceptClick);
    cancel.addEventListener('click', cancelClick);
    backdrop.addEventListener('click', outside);
    document.addEventListener('keydown', keydown);
    dialog.focus();
    cancel.focus();
  });
}
async function perform(command) {
  if (pending || confirming) return;
  const prompts = {
    install: ['安装管理器 APK', '将使用模块自带的签名 APK 更新管理器；签名不一致时不会删除现有应用或数据。'],
    start: ['启动原生后端', '将对当前 system_server 执行实验性注入。请确认设备已经完成重启。']
  };
  if (prompts[command]) {
    const yes = await requestConfirmation(prompts[command][0], prompts[command][1]);
    if (!yes) return;
  }
  pending = true;
  syncButtons();
  try {
    if (command === 'status') {
      await refreshStatus();
      notify('已刷新模块状态');
      return;
    }
    showOutput('正在执行 ' + command + '，请勿重复点击…');
    const response = await bridgeRun(command);
    const result = [response.stdout, response.stderr].filter(Boolean).join('\n').trim();
    showOutput((response.code !== 0 ? '执行失败（退出码 ' + response.code + '）\n' : '') + (result || '执行完毕'));
    if (response.code === 0) notify('操作已完成');
    else notify('操作失败，请查看日志');
    try { await refreshStatus(); }
    catch (error) { notify('操作完成，但状态刷新失败'); }
  } catch (error) {
    showOutput('错误：' + (error && error.message || String(error)));
    notify('无法完成操作');
  } finally {
    pending = false;
    syncButtons();
  }
}
async function copyLog() {
  const text = output.textContent;
  if (!text.trim()) return;
  try {
    if (navigator.clipboard && navigator.clipboard.writeText) {
      await navigator.clipboard.writeText(text);
    } else {
      const input = document.createElement('textarea');
      input.value = text;
      input.style.position = 'fixed';
      input.style.opacity = '0';
      document.body.appendChild(input);
      input.select();
      try {
        if (!document.execCommand('copy')) throw new Error('不支持复制');
      } finally {
        input.remove();
      }
    }
    notify('日志已复制到剪贴板');
  } catch (_) {
    notify('复制失败，请长按日志内容选择复制');
  }
}
ACTION_IDS.forEach(id => $(id).addEventListener('click', () => perform(id === 'refresh' ? 'status' : id)));
$('copy').addEventListener('click', copyLog);
syncButtons();
refreshStatus().catch(error => {
  showOutput('状态读取失败：' + (error && error.message || String(error)));
  $('summary-title').textContent = '连接管理器失败';
  $('summary-desc').textContent = '请在支持 WebUI 的 SukiSU / KernelSU 管理器中打开。';
  $('status-hero').dataset.tone = 'error';
  notify('未能读取模块状态');
});
