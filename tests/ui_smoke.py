"""Real browser smoke test using temporary data only. Requires Python Playwright + Chromium."""
import json
import os
from pathlib import Path
import socket
import subprocess
import tempfile
import time
import urllib.error
import urllib.request
from playwright.sync_api import sync_playwright, expect

PROJECT = Path(__file__).resolve().parents[1]
ARTIFACTS = PROJECT / 'artifacts'
ARTIFACTS.mkdir(exist_ok=True)
with tempfile.TemporaryDirectory(prefix='dayproof-ui-') as directory:
    temp = Path(directory)
    with socket.socket() as sock:
        sock.bind(('127.0.0.1', 0))
        port = sock.getsockname()[1]
    base = f'http://127.0.0.1:{port}'
    env = dict(os.environ, PORT=str(port), DATA_DIR=str(temp / 'data'), EVIDENCE_ROOT=directory)
    with (temp / 'server.log').open('w') as logfile:
        server = subprocess.Popen([str(PROJECT / 'node_modules/.bin/tsx'), 'src/server/index.ts'], cwd=PROJECT, env=env, stdout=logfile, stderr=logfile)
        try:
            for _ in range(100):
                try:
                    urllib.request.urlopen(base + '/api/session', timeout=1).close()
                    break
                except (urllib.error.URLError, OSError):
                    if server.poll() is not None:
                        raise RuntimeError((temp / 'server.log').read_text())
                    time.sleep(.1)
            with sync_playwright() as p:
                browser = p.chromium.launch(headless=True, executable_path=os.environ.get('CHROMIUM_EXECUTABLE'))
                page = browser.new_page(viewport={'width': 1440, 'height': 1080}, device_scale_factor=1)
                errors = []
                page.on('pageerror', lambda error: errors.append(str(error)))
                page.goto(base)
                page.wait_for_load_state('networkidle')
                expect(page.get_by_text('给今天一个清晰的开始')).to_be_visible()
                page.screenshot(path=str(ARTIFACTS / 'empty-desktop.png'), full_page=True)

                page.get_by_role('button', name='新建任务', exact=True).click()
                dialog = page.get_by_role('dialog')
                dialog.get_by_label('任务名称').fill('完成 Claude Code 订阅（验收演示）')
                dialog.get_by_label('怎样才算完成？').fill('演示状态文件中的订阅状态为 active；不是实际账户查询')
                dialog.get_by_label('截止时间').fill('2026-10-19T18:00')
                dialog.get_by_label('优先级').select_option('high')
                dialog.get_by_label('任务来源').fill('Claude Code')
                dialog.get_by_label('完成验收方式').select_option('json_equals')
                dialog.get_by_label('证据文件路径').fill('subscription-demo.json')
                dialog.get_by_role('button', name='加入计划', exact=True).click()
                expect(dialog).not_to_be_visible()
                card = page.locator('.task-card').filter(has_text='完成 Claude Code 订阅（验收演示）')
                expect(card).to_be_visible()
                page.get_by_role('button', name='检查 完成 Claude Code 订阅（验收演示）', exact=True).click()
                expect(card.get_by_text('等待证据', exact=True)).to_be_visible()
                (temp / 'subscription-demo.json').write_text(json.dumps({'subscription': {'active': True}}))
                page.get_by_role('button', name='检查 完成 Claude Code 订阅（验收演示）', exact=True).click()
                expect(card.get_by_text('验收通过', exact=True)).to_be_visible()
                expect(card).to_have_class('task-card completed')
                page.reload()
                page.wait_for_load_state('networkidle')
                expect(page.get_by_role('button', name='重新打开 完成 Claude Code 订阅（验收演示）', exact=True)).to_be_visible()

                page.get_by_role('button', name='开始规划', exact=True).click()
                dialog = page.get_by_role('dialog')
                dialog.get_by_label('今天想完成什么？').fill('整理项目需求与验收清单\n接入 Codex 并同步今日计划\n下班前留出半小时复盘')
                dialog.get_by_role('button', name='一行一任务', exact=True).click()
                assert '整理项目需求' in dialog.locator('.code-textarea').input_value()
                dialog.get_by_role('button', name='确认并加入计划').click()
                expect(dialog).not_to_be_visible()
                expect(page.locator('.task-card')).to_have_count(4)
                page.get_by_role('button', name='完成 整理项目需求与验收清单', exact=True).click()
                expect(page.get_by_role('button', name='重新打开 整理项目需求与验收清单', exact=True)).to_be_visible()
                page.get_by_role('button', name='重新打开 整理项目需求与验收清单', exact=True).click()
                page.get_by_role('button', name='编辑 整理项目需求与验收清单', exact=True).click()
                dialog = page.get_by_role('dialog')
                dialog.get_by_label('怎样才算完成？').fill('输出一份包含范围、优先级与验收标准的需求文档')
                dialog.get_by_label('预计用时 / 分钟').fill('60')
                dialog.get_by_role('button', name='保存修改', exact=True).click()
                expect(dialog).not_to_be_visible()
                page.screenshot(path=str(ARTIFACTS / 'dashboard-desktop.png'), full_page=True)

                page.get_by_role('button', name='验收记录', exact=True).click()
                expect(page.locator('.activity-list')).to_contain_text('已达到预期值')
                page.get_by_role('button', name='工具接入').click()
                expect(page.locator('.connection-card')).to_have_count(3)
                expect(page.locator('.connection-card').first.locator('pre')).to_contain_text(str(PROJECT))
                expect(page.locator('.connection-card').first.locator('pre')).to_contain_text(str(temp / 'data'))
                expect(page.locator('.connection-card').first.locator('pre')).to_contain_text('DAYPROOF_URL=' + base)
                generic_config = json.loads(page.locator('.connection-card').last.locator('pre').inner_text())
                assert generic_config['mcpServers']['dayproof']['env']['DAYPROOF_URL'] == base
                page.screenshot(path=str(ARTIFACTS / 'connections-desktop.png'), full_page=True)
                page.get_by_role('button', name='模型与设置').click()
                expect(page.get_by_label('模型名称')).to_be_visible()
                with page.expect_download() as download_info:
                    page.get_by_text('导出任务与验收记录', exact=True).click()
                exported = download_info.value
                exported.save_as(str(temp / 'export.json'))
                assert len(json.loads((temp / 'export.json').read_text())['tasks']) == 4
                page.get_by_role('button', name='每日计划').click()
                page.set_viewport_size({'width': 390, 'height': 844})
                page.screenshot(path=str(ARTIFACTS / 'dashboard-mobile.png'), full_page=True)
                assert page.evaluate('document.documentElement.scrollWidth <= window.innerWidth'), 'Mobile page overflows'
                page.get_by_role('button', name='新建任务', exact=True).click()
                expect(page.get_by_role('dialog')).to_be_visible()
                page.get_by_role('button', name='关闭窗口', exact=True).click()
                page.set_viewport_size({'width': 1440, 'height': 1080})
                page.get_by_role('button', name='编辑 下班前留出半小时复盘', exact=True).click()
                dialog = page.get_by_role('dialog')
                dialog.get_by_role('button', name='删除任务', exact=True).click()
                dialog.get_by_role('button', name='再次点击删除', exact=True).click()
                expect(page.locator('.task-card')).to_have_count(3)
                assert not errors, errors
                browser.close()
                print('UI smoke passed: create, evidence pending/pass, persistence, batch plan, manual completion/reopen, edit, audit, MCP config, settings, export, mobile, delete; no browser errors.')
        finally:
            server.terminate()
            try:
                server.wait(timeout=10)
            except subprocess.TimeoutExpired:
                server.kill()
                server.wait()
