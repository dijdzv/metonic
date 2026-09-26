// AST-grep native boundary for the two audited contract-case tables.
const fs=require('node:fs');
const path=require('node:path');
const root=path.resolve(__dirname,'../..');
const {parse,registerDynamicLanguage}=require(path.join(root,'.work/jev-ast/node_modules/@ast-grep/napi'));
registerDynamicLanguage({moonbit:{libraryPath:path.join(root,'.work/jev-ast/tree-sitter-moonbit.dll'),extensions:['mbtx']}});
const input=JSON.parse(fs.readFileSync(process.argv[2],'utf8'));
const tests=[],excluded=[];
const reactiveChanged=input.changed.some(p=>p.startsWith('core/reactive/')||p.startsWith('tools/reactive_negative/')||['scripts/verify-reactive-negative.mbtx','scripts/pre-commit.mbtx','toolchain.json','moon.mod','moon.lock'].includes(p));
for(const [file,expected,conditional] of [
  ['scripts/verify-types.mbtx',5,false],
  ['scripts/verify-reactive-negative.mbtx',7,true],
]) {
  const source=fs.readFileSync(path.join(root,file),'utf8');
  const tree=parse('moonbit',source).root();
  if(tree.findAll({rule:{kind:'ERROR'}}).length) throw Error('Contract parser error');
  const cases=tree.findAll({rule:{kind:'tuple_expression'}}).map(n=>{
    const m=/^\(\s*("(?:[^"\\]|\\.)*")\s*,\s*("(?:[^"\\]|\\.)*")\s*,?\s*\)$/.exec(n.text());
    if(!m) throw Error('Unsupported case table');
    return {name:JSON.parse(m[1]),evidence:JSON.parse(m[2]),line:n.range().start.line+1};
  });
  if(cases.length!==expected) throw Error('Case table changed; re-audit hook mapping');
  for(const target of ['js','wasm-gc','native']) for(const c of cases) {
    const entry={id:`contract:${file}:${target}:${c.name}`,name:c.name,file,package:'hook-contracts',index:String(c.line),target,kind:'contract-case',
      symbols:[],test_body:JSON.stringify({scenario:c.name,target,evidence:c.evidence,expected:conditional?'process fails with the named rejecting frame':c.name==='valid'?'check and build succeed':'check fails and diagnostics contain type mismatch',verifier:file}),
      parent_verifier:file,conditional,individually_executable:false};
    if(conditional&&!reactiveChanged) excluded.push({...entry,exclusion_reason:'pre-commit reactive_contracts_changed condition is false for supplied changed paths'});
    else tests.push(entry);
  }
}
input.tests=tests;
input.kind='unified';
input.scope='pre-commit type and conditional reactive contract tables only';
input.scope_exclusions=excluded;
input.coverage='Two audited tables; not all hook checks. Diff changed paths must represent the staged commit range.';
fs.writeFileSync(process.argv[3],JSON.stringify(input));
console.log(JSON.stringify({included:tests.length,condition_excluded:excluded.length}));
