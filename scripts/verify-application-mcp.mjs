import assert from 'node:assert/strict';
import { Client } from '@modelcontextprotocol/client';
import { StdioClientTransport } from '@modelcontextprotocol/client/stdio';

const session = process.argv[2];
if (!session) throw new Error('session path required');
for (let attempt = 0; attempt < 2; attempt++) {
  const transport = new StdioClientTransport({ command: process.execPath, args: ['tools/devtools/application-mcp.mjs', '--session', session], cwd: process.cwd(), stderr: 'pipe' });
  const client = new Client({ name: 'application-control-verifier', version: '0.0.0' });
  const timer = setTimeout(() => { void transport.close(); }, 15000);
  const call = async (name, args = {}) => {
    const result = await client.callTool({ name: `application_${name}`, arguments: args });
    assert.equal(result.isError, false, JSON.stringify(result));
    return { result, state: JSON.parse(result.content.find(item => item.type === 'text').text) };
  };
  try {
    await client.connect(transport);
    let { state } = await call('snapshot');
    assert.equal(state.application_protocol, 1);
    const input = state.controls.find(control => control.role === 'text_input');
    assert.ok(input);
    if (attempt === 0) {
      ({ state } = await call('select', { target: input.target, expected_semantic_revision: state.semantic_revision, selection_start: 0, selection_end: input.value.length }));
      ({ state } = await call('insert', { target: input.target, expected_semantic_revision: state.semantic_revision, text: 'MCPから編集' }));
    }
    assert.equal(state.controls.find(control => control.role === 'text_input').value, 'MCPから編集');
    const stale = await client.callTool({ name: 'application_insert', arguments: { target: input.target, expected_semantic_revision: 0, text: 'must not apply' } });
    assert.equal(stale.isError, true);
    const { result } = await call('capture');
    const image = result.content.find(item => item.type === 'image');
    assert.equal(image.mimeType, 'image/png');
    assert.ok(image.data.length > 100);
  } finally {
    clearTimeout(timer);
    await client.close();
  }
}
console.log('APPLICATION_MCP_OK edit stale_revision capture disconnect_reconnect');
