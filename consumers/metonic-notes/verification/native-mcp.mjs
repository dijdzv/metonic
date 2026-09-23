import assert from 'node:assert/strict';
import path from 'node:path';
import { Client } from '@modelcontextprotocol/client';
import { StdioClientTransport } from '@modelcontextprotocol/client/stdio';

const discovery = process.argv[2];
const framework = path.resolve('.metonic/framework');
if (!discovery) throw new Error('session path required');
for (let attempt = 0; attempt < 2; attempt++) {
  const transport = new StdioClientTransport({ command: process.execPath, args: [path.join(framework, 'tools/devtools/application-mcp.mjs'), '--session', discovery], cwd: framework, stderr: 'pipe' });
  const client = new Client({ name: 'memo-verifier', version: '0.0.0' });
  const timeout = setTimeout(() => { void transport.close(); }, 20000);
  const call = async (op, args = {}) => {
    const result = await client.callTool({ name: `application_${op}`, arguments: args });
    assert.equal(result.isError, false, JSON.stringify(result));
    return { state: JSON.parse(result.content.find(item => item.type === 'text').text), result };
  };
  try {
    await client.connect(transport);
    let { state } = await call('snapshot');
    if (attempt === 0) {
      for (let retry = 0; !state.controls.some(item => item.name === 'New memo' && item.enabled); retry++) {
        assert.ok(retry < 100, 'initial load did not finish');
        await new Promise(resolve => setTimeout(resolve, 20));
        ({ state } = await call('snapshot'));
      }
      const button = state.controls.find(item => item.name === 'New memo');
      ({ state } = await call('activate', { target: button.target, expected_semantic_revision: state.semantic_revision }));
      const input = state.controls.find(item => item.role === 'text_input');
      assert.equal(input.enabled, true);
      ({ state } = await call('insert', { target: input.target, expected_semantic_revision: state.semantic_revision, text: '独立アプリから保存\nMCPの確認' }));
      const save = state.controls.find(item => item.name === 'Save all');
      await call('activate', { target: save.target, expected_semantic_revision: state.semantic_revision });
    }
    ({ state } = await call('snapshot'));
    assert.equal(state.controls.find(item => item.role === 'text_input').value, '独立アプリから保存\nMCPの確認');
    const { result } = await call('capture');
    assert.equal(result.content.find(item => item.type === 'image').mimeType, 'image/png');
  } finally {
    clearTimeout(timeout);
    await client.close();
  }
}
console.log('MEMO_MCP_OK create edit save_requested render reconnect');
