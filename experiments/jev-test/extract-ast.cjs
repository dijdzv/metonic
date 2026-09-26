// Native AST-grep API boundary. No credentials or network access.
const fs = require('node:fs');
const path = require('node:path');
const cp = require('node:child_process');
const root = path.resolve(__dirname, '../..');
const {parse, registerDynamicLanguage} = require(path.join(root, '.work/jev-ast/node_modules/@ast-grep/napi'));
registerDynamicLanguage({moonbit: {libraryPath: path.join(root, '.work/jev-ast/tree-sitter-moonbit.dll'), extensions: ['mbt']}});
const started = performance.now();
const tracked = cp.execFileSync('git', ['ls-files', '-z', '--', '*.mbt'], {cwd: root, encoding: 'utf8'}).split('\0').filter(Boolean);
const input = process.argv[2] && process.argv[2] !== '--all' ? JSON.parse(fs.readFileSync(process.argv[2],'utf8')) : null;
const modules = {'local/p0':'','local/metonic_async':'async_runtime','local/native_host':'native_host','local/wgpu_binding_probe':'experiments/wgpu_binding','wzzc-dev/window':'.work/native-deps/sources/window-pointer-capture/modules/window'};
function sourcePath(pkg,filename) {
  const module = Object.keys(modules).find(m=>pkg===m || pkg.startsWith(m+'/'));
  if(!module) throw Error('Unmapped module: '+pkg);
  return [modules[module],pkg.slice(module.length).replace(/^\//,''),filename].filter(Boolean).join('/');
}
if(process.argv.includes('--outline')) {
  if(!input) throw Error('Outline import needs a template dossier');
  input.target=process.argv[process.argv.indexOf('--target')+1];
  input.tests=[];
  const raw=fs.readFileSync(process.argv[process.argv.indexOf('--outline')+1],'utf8');
  for(const line of raw.split(/\r?\n/)) {
    const m=line.match(/^\s*\d+\. (\S+) (\S+):(\d+) index=(\d+) name=(.*)$/);
    if(!m) {
      if(/^\s*\d+\./.test(line)) throw Error('Unrecognized outline row');
      continue;
    }
    const [,pkg,file,start,index,name]=m;
    input.tests.push({id:`${input.target}:${pkg}:${file}:${index}`,package:pkg,file:sourcePath(pkg,file),index,name:JSON.parse(name),start_line:+start,target:input.target,kind:'moon-test'});
  }
  if(!input.tests.length) throw Error('Empty outline; inspect collection status');
  input.kind='unified';
  input.coverage='Explicitly supplied successful outline only; not repository-wide completeness';
}
if(input && !['js','wasm-gc','native','wasm'].includes(input.target)) throw Error('Unsupported target');
const outline = input ? input.tests.map((t,i)=>`${i+1}. ${t.package} ${path.basename(t.file)}:${t.start_line} index=${t.index} name=${JSON.stringify(t.name)}`).join('\n') : fs.readFileSync(path.join(root,'.work/jev-metonic/outline.log'),'utf8');
const needed = new Set(outline.split(/\r?\n/).filter(l=>l.trim()).map(line => {
  const m=line.match(/^\s*\d+\. (\S+) (\S+):\d+ index=/);
  if(!m) throw Error('Unsupported outline');
  return sourcePath(m[1],m[2]);
}));
const files = process.argv.includes('--all') ? tracked : [...needed].filter(f=>fs.existsSync(path.join(root,f)));
const inventory = [];
const errors = [];
const parsed = new Map();
for (const file of files) {
  const source = fs.readFileSync(path.join(root,file),'utf8');
  const tree = parse('moonbit',source).root();
  const bad = tree.findAll({rule: {kind: 'ERROR'}});
  if (bad.length) errors.push({file, errors: bad.length});
  const tests = tree.findAll({rule: {kind: 'test_definition'}}).map(node => {
    const children = node.children();
    const body = children.find(n => n.kind() === 'block_expression');
    const symbols = body ? body.findAll({rule: {any: [{kind:'qualified_identifier'}, {kind:'qualified_type_identifier'}, {kind:'method_expression'}, {kind:'dot_identifier'}]}}).map(n => n.text()) : [];
    return {start_line:node.range().start.line+1,end_line:node.range().end.line+1,test_body:body?.text() ?? null,
      // Syntactic references include locals; these are not resolved dependencies.
      symbols:[...new Set(symbols)].sort(), file, parse_ok:bad.length === 0};
  });
  inventory.push(...tests);
  parsed.set(file,{source,tests});
}

const tests = [];
for (const line of outline.split(/\r?\n/).filter(l=>l.trim())) {
  const m = line.match(/^\s*\d+\. (\S+) (\S+):(\d+) index=(\d+) name=(.*)$/);
  if (!m) throw Error('Unsupported outline line');
  const [,pkg,filename,lineNo,index,name] = m;
  const file = sourcePath(pkg,filename);
  const info = parsed.get(file);
  const matching = info?.tests.filter(t=>t.start_line<=+lineNo && t.end_line>=+lineNo) ?? [];
  const found = matching.length===1 && matching[0].parse_ok ? matching[0] : null;
  tests.push({id:`${input?.target ?? "js"}:${pkg}:${filename}:${index}`,package:pkg,file,index,name:JSON.parse(name),
    test_body:found?.test_body ?? null,symbols:found?.symbols ?? null,source_file_text:info?.source ?? null,
    ast_status:found?'matched':'unavailable',start_line:+lineNo});
}
const summary = {source_files:files.length,ast_tests:inventory.length,parser_error_files:errors,runner_tests:tests.length,
  matched:tests.filter(t=>t.ast_status==='matched').length,elapsed_ms:Math.round(performance.now()-started)};
const out = path.join(root,'.work/jev-metonic');
if (input) {
  const byId = new Map(tests.map(t=>[t.id,t]));
  for (const t of input.tests) {
    const found = byId.get(t.id);
    t.test_body = found?.test_body ?? null;
    t.symbols = found?.symbols ?? null;
    t.ast_status = found?.ast_status ?? 'unavailable';
  }
  input.ast_summary = summary;
  fs.writeFileSync(process.argv[3], JSON.stringify(input));
} else fs.writeFileSync(path.join(out,'ast-inventory.json'),JSON.stringify({summary,inventory,tests}));
console.log(JSON.stringify(summary));
