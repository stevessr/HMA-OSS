#!/usr/bin/env node
'use strict';
// Dependency-free WebUI contract/runtime regression; runs in GitHub Actions.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const root = path.resolve(__dirname, '../module/webroot');
const html = fs.readFileSync(path.join(root, 'index.html'), 'utf8');
const css = fs.readFileSync(path.join(root, 'style.css'), 'utf8');
const app = fs.readFileSync(path.join(root, 'app.js'), 'utf8');
const ids = [...html.matchAll(/\bid="([^"]+)"/g)].map(m => m[1]);
assert.equal(new Set(ids).size, ids.length, 'HTML IDs must be unique');
for (const id of ['refresh', 'manager', 'manager-card', 'reboot', 'reboot-card',
  'injection', 'injection-card', 'autostart', 'autostart-card', 'device',
  'start', 'start-label', 'stop', 'install', 'logs', 'copy', 'output',
  'version', 'status-hero', 'summary-title', 'summary-desc', 'action-notice',
  'action-notice-text', 'confirm-backdrop', 'confirm-cancel', 'confirm-accept',
  'confirm-title', 'confirm-body', 'snackbar']) {
  assert(ids.includes(id), 'Missing accessible UI element: ' + id);
}
assert.match(html, /role="dialog".*aria-modal="true"/);
assert.match(html, /aria-live="polite"/);
assert.match(html, /viewport-fit=cover/);
for (const token of ['--md-primary', '--md-on-primary', '--md-primary-container',
  '--md-surface-container-low', '--md-surface-container-high',
  '--md-on-surface', '--md-outline', '--md-error-container',
  '--shape-xl', 'prefers-reduced-motion', 'focus-visible']) {
  assert(css.includes(token), 'Missing Material Design 3 design token: ' + token);
}
// An inline SVG xmlns="http://www.w3.org/2000/svg" is a namespace,
 // not a network request. Only forbid external resources and CSS imports.
assert(!/<(?:script|link)[^>]*(?:src|href)="https?:\/\//i.test(html) &&
       !/@import\b|url\(\s*['"]?https?:\/\//i.test(css),
  'WebUI resources must remain offline and self-contained');
assert(!/innerHTML\s*=/.test(app), 'Do not inject root shell output as HTML');

function element() {
  return {
    textContent: '', dataset: {}, disabled: false, hidden: false, attributes: {},
    listeners: new Map(),
    addEventListener(type, fn) { this.listeners.set(type, fn); },
    removeEventListener(type) { this.listeners.delete(type); },
    setAttribute(key, value) { this.attributes[key] = value; },
    focus() {},
    querySelector() { return dialog; },
    click() { return this.listeners.get('click')?.({target: this}); }
  };
}
const elements = Object.fromEntries(ids.map(id => [id, element()]));
const dialog = element();
const modes = ['system', 'light', 'dark'].map(name => {
  const button = element();
  button.dataset.themeOption = name;
  return button;
});
const document = {
  documentElement: element(), activeElement: element(),
  getElementById: id => elements[id],
  querySelectorAll: selector => selector === '[data-theme-option]' ? modes : [],
  addEventListener() {}, removeEventListener() {}
};
let response = 'version=0.1.5-alpha\ninstalled=yes\nbundled=yes\nmodule=enabled\n' +
  'server_pid=4101\nreboot=ready\ninjection=not_verified\nautostart=disabled\n';
const calls = [];
const context = {
  window: {
    matchMedia: () => ({ matches: false, addEventListener() {} }),
    ksu: {
      exec(cmd) {
        calls.push(cmd);
        assert.match(cmd, /^sh \/data\/adb\/modules\/hma_sukisu\/webui-api\.sh (status|install|start|stop|logs)$/);
        if (cmd.endsWith(' status')) return response;
        if (cmd.endsWith(' logs')) return 'service started\nboot recovered';
        return 'Success';
      }
    }
  },
  document,
  navigator: { clipboard: { async writeText(text) { assert(text.includes('service started')); } } },
  localStorage: { getItem: () => null, setItem() {} },
  setTimeout: () => 1, clearTimeout() {}, console,
  Promise, Set
};
vm.createContext(context);
vm.runInContext(app, context, {filename: 'webroot/app.js'});
const wait = () => new Promise(resolve => setImmediate(resolve));

async function main() {
  await wait();
  assert.equal(elements.manager.textContent, '已安装');
  assert.equal(elements.reboot.textContent, '已就绪');
  assert.equal(elements['summary-title'].textContent, '等待启用');
  assert.equal(elements.start.disabled, false);
  assert.equal(elements.stop.disabled, true);

  // Consent dialog is MD3-styled, single-instance and fail-closed. Cancel
  // must not run a root command, and duplicate clicks must not race.
  const cancelled = elements.start.click();
  assert.equal(elements['confirm-backdrop'].hidden, false);
  assert.equal(elements.start.disabled, true);
  await elements['confirm-cancel'].click();
  await cancelled;
  assert.equal(calls.filter(cmd => cmd.endsWith(' start')).length, 0);
  const accepted = elements.start.click();
  assert.equal(elements.start.disabled, true);
  await elements['confirm-accept'].click();
  await accepted;
  assert.equal(calls.filter(cmd => cmd.endsWith(' start')).length, 1);

  modes[2].click();
  assert.equal(document.documentElement.attributes['data-theme'], 'dark');
  assert.equal(modes[2].attributes['aria-pressed'], 'true');
  modes[1].click();
  assert.equal(document.documentElement.attributes['data-theme'], 'light');

  response = response.replace('injection=not_verified', 'injection=verified')
    .replace('autostart=disabled', 'autostart=enabled');
  elements.refresh.click();
  await wait();
  assert.equal(elements.injection.textContent, '已验证');
  assert.equal(elements['status-hero'].dataset.tone, 'positive');
  assert.equal(elements.stop.disabled, false);
  assert.equal(elements['start-label'].textContent, '检查 / 恢复注入');

  elements.logs.click();
  await wait();
  assert.match(elements.output.textContent, /boot recovered/);
  elements.copy.click();
  await wait();

  response = response.replace('reboot=ready', 'reboot=pending');
  elements.refresh.click();
  await wait();
  assert.equal(elements.start.disabled, true, 'Injection must not start before reboot');
  assert.equal(elements['status-hero'].dataset.tone, 'warning');

  response = response.replace('reboot=pending', 'reboot=ready')
    .replace('injection=verified', 'injection=failed_this_system_server');
  elements.refresh.click();
  await wait();
  assert.equal(elements.start.disabled, true, 'Failed target must stay locked');
  assert.equal(elements['status-hero'].dataset.tone, 'error');
  assert.equal(calls.filter(cmd => cmd.endsWith(' status')).length, 6);
  console.log('Material 3 WebUI design + status/command/theme/permission regression passed');
}
main().catch(err => { console.error(err); process.exitCode = 1; });
