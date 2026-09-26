// Native AST boundary: audited hook files, with static literal loop expansion.
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '../..');
const {parse} = require(path.join(root,'.work/jev-ast/node_modules/@ast-grep/napi'));
const input = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const tests = [];
const files = ['browser-observation','moonbit-session','session-failure','mcp-result'].map(n=>'tools/devtools/'+n+'.test.mjs');
for(const file of files) {
const source = fs.readFileSync(path.join(root, file), 'utf8');
const tree = parse('JavaScript', source).root();
if(tree.findAll({rule:{kind:'ERROR'}}).length) throw Error('Parse failure');
const imports = tree.findAll({rule:{kind:'import_statement'}}).map(n=>n.text());
const names = new Set();
for(const node of tree.findAll({rule:{kind:'call_expression'}})) {
  if(node.children()[0]?.text() !== 'test') continue;
  const match = /^test\('([^'\\]+)',/.exec(node.text());
  let variants = match ? [{name:match[1],context:''}] : [];
  if(!match) {
    const template = /^test\(`([^`]+)`,/.exec(node.text());
    let ancestor = node.parent();
    while(ancestor && ancestor.kind() !== 'for_in_statement') ancestor=ancestor.parent();
    const loop = ancestor && /^for\s*\(const (\w+) of \[([^\]]+)\]\)/.exec(ancestor.text());
    if(!template || !loop || !/^'[^'\\]*'(?:,\s*'[^'\\]*')*$/.test(loop[2])) throw Error('Unsupported dynamic test name in '+file);
    variants = [...loop[2].matchAll(/'([^']*)'/g)].map(m=>({name:template[1].replaceAll('${'+loop[1]+'}',m[1]),context:'Loop binding: '+loop[1]+' = '+JSON.stringify(m[1])}));
  }
  for(const {name,context} of variants) {
  if(name.includes('${') || names.has(name)) throw Error('Unresolved or duplicate test name');
  names.add(name);
  const pattern = '^'+name.replace(/[.*+?^${}()|[\]\\]/g,'\\$&')+'$';
  tests.push({id:'node:'+file+':'+name, file, name, index:String(tests.length),
    package:'node:'+path.basename(file),kind:'node-integration-test',
    test_body:imports.join('\n')+'\n'+context+'\n'+node.text(),
    symbols:[...new Set(node.findAll({rule:{kind:'call_expression'}}).map(n=>n.children()[0]?.text()).filter(Boolean))],
    command:['node','--test','--test-name-pattern='+pattern,file],
    parent_gate:file.includes('browser-observation')?'gate:browser:headless':'gate:devtools:test'});
  }
}
}
input.tests=tests;
// Keep the mixed-runner guard: these are not moon test indices.
input.kind='unified';
input.coverage='Four hook node:test files, static AST discovery including literal parameter loops; not repository-wide completeness';
fs.writeFileSync(process.argv[3],JSON.stringify(input));
console.log(JSON.stringify({files:files.length,tests:tests.length}));
