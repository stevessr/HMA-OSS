'use strict';
// KernelSU injects "ksu" in its WebView. No remote scripts or external APIs.
const $ = (id) => document.getElementById(id);
const bridge = '/data/adb/modules/hma_sukisu/webui-api.sh';
const buttons = ['refresh','install','start','stop','logs'];
let sequence = 0;
const output = $('output');
function write(text) {
  output.textContent = text || '命令完成，无输出。';
}
function run(command) {
  return new Promise((resolve, reject) => {
    if (!window.ksu || typeof window.ksu.exec !== 'function') {
      reject(new Error('未找到 KernelSU WebUI root bridge。请从支持 WebUI 的管理器打开模块。'));
      return;
    }
    const callbackName = '__hmaResult' + (++sequence);
    let handled = false;
    window[callbackName] = (code, stdout, stderr) => {
      if (handled) return;
      handled = true;
      delete window[callbackName];
      resolve({code: Number(code), stdout: String(stdout || ''), stderr: String(stderr || '')});
    };
    try {
      const result = window.ksu.exec('sh ' + bridge + ' ' + command, callbackName);
      // Older WebUI engines expose only a synchronous string result.
      if (typeof result === 'string' && result.length) {
        handled = true;
        delete window[callbackName];
        resolve({code: 0, stdout: result, stderr: ''});
      }
    } catch (err) {
      delete window[callbackName];
      reject(err);
    }
  });
}
function value(data, key) {
  return data.split('\n').find(line => line.startsWith(key + '='))?.slice(key.length + 1) || 'unknown';
}
async function refresh() {
  const result = await run('status');
  if (result.code) throw new Error(result.stderr || result.stdout || '状态获取失败');
  const v = result.stdout;
  $('manager').textContent = value(v, 'installed') === 'yes' ? '已安装' : '未安装';
  $('reboot').textContent = value(v, 'reboot') === 'ready' ? '已就绪' : '需要重启';
  const state = value(v, 'injection');
  $('injection').textContent = state === 'verified' ? '已验证' : state === 'failed_this_system_server' ? '本次启动已失败' : '未验证';
  $('autostart').textContent = value(v, 'autostart') === 'enabled' ? '已启用' : '未启用';
  $('device').textContent = '版本 ' + value(v, 'version') + ' · system_server PID ' + value(v, 'server_pid') + ' · 模块 ' + value(v, 'module');
}
async function operation(action, confirmText = '') {
  if (confirmText && !window.confirm(confirmText)) return;
  for (const id of buttons) $(id).disabled = true;
  write('正在执行 ' + action + ' …');
  try {
    const result = await run(action);
    write((result.stdout + '\n' + result.stderr).trim() || ('退出状态：' + result.code));
    if (result.code !== 0) write('操作失败（exit ' + result.code + '）\n' + output.textContent);
    await refresh();
  } catch (error) {
    write(String(error && error.message || error));
  } finally {
    for (const id of buttons) $(id).disabled = false;
  }
}
$('refresh').addEventListener('click', () => operation('status'));
$('install').addEventListener('click', () => operation('install', '使用模块自带 APK 安装或更新 HMA 管理器？已有数据不会主动清除。'));
$('start').addEventListener('click', () => operation('start', '将尝试向 system_server 注入实验性后端。仅在已经重启后操作，继续吗？'));
$('stop').addEventListener('click', () => operation('stop'));
$('logs').addEventListener('click', () => operation('logs'));
refresh().catch(e => write(String(e.message || e)));
