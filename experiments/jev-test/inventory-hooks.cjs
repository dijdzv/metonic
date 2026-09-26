// Native AST boundary and coverage report for the audited hook command graph.
// No verifier, test, subprocess from repository source, or API is executed here.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto'),cp=require('node:child_process');
const root=path.resolve(__dirname,'../..');
const out=path.join(root,'.work/jev-metonic');
const {parse,registerDynamicLanguage}=require(path.join(root,'.work/jev-ast/node_modules/@ast-grep/napi'));
registerDynamicLanguage({moonbit:{libraryPath:path.join(root,'.work/jev-ast/tree-sitter-moonbit.dll'),extensions:['mbt','mbtx']}});
const read=p=>fs.readFileSync(path.join(root,p),'utf8');
const load=n=>JSON.parse(fs.readFileSync(path.join(out,n+'.json'),'utf8'));
const sha=s=>crypto.createHash('sha256').update(s).digest('hex');
const base=load('hook-gates-27');
const defs=base.gate_definitions;
const policy=JSON.parse(read('verification.json'));
if(policy.full_gate_tasks.some(t=>!defs[t])) throw Error('Refresh gate definitions');
const scripts=new Map(),commands=[],tasks=new Set(),sourceDigests={};
const entries=new Map();
function add(t) {
  if(entries.has(t.id)) throw Error('Duplicate inventory identity '+t.id);
  entries.set(t.id,t);
}
function item(id,name,file,kind,body,extra={}) {
  return {id,name,file,kind,package:'hook-verification',index:'0',test_body:body,symbols:[],...extra};
}
// Whole script/executable checks are atomic where the runner has no individual
// case interface. Their entire body remains the coverage boundary.
function visitSource(file,via) {
  if(scripts.has(file)) {scripts.get(file).via.push(via);return;}
  if(!fs.existsSync(path.join(root,file))) throw Error('Missing referenced source '+file);
  const source=read(file);sourceDigests[file]=sha(source);
  const language=/\.mbtx?$/.test(file)?'moonbit':'JavaScript';
  const tree=parse(language,source).root();
  const row={file,via:[via],parse_errors:tree.findAll({rule:{kind:'ERROR'}}).length,process_sites:[],references:[]};
  scripts.set(file,row);
  const kind=language==='moonbit'?'apply_expression':'call_expression';
  for(const n of tree.findAll({rule:{kind}})) {
    const callee=n.children()[0]?.text()??'';
    if(/(?:process\.|run_checked|checked|expect_clean|^run$|^result$|spawn|execFile|verify)/.test(callee))
      row.process_sites.push({line:n.range().start.line+1,callee,code:n.text()});
  }
  // These references are source closure, not evidence that all branches run.
  for(const m of source.matchAll(/(?:scripts|examples|tools)\/[A-Za-z0-9_./-]+\.(?:mbtx|mjs)/g)) {
    if(fs.existsSync(path.join(root,m[0]))) {row.references.push(m[0]);visitSource(m[0],file);}
  }
  add(item('verifier:'+file,file,file,/scripts\/(?:verify-|doctor)/.test(file)?'script-verifier':'supporting-verification',source,{coverage_unit:'entire source entry including its checks and conditional branches; not independently selectable assertions'}));
}
function task(name,via) {
  if(tasks.has(name))return;
  const definition=defs[name];if(!definition)throw Error('Missing task '+name);
  tasks.add(name);
  const lines=definition.split(/\r?\n/);let array=false,found=false;
  for(let i=0;i<lines.length;i++) {
    const line=lines[i].trim();
    if(line.startsWith('depends = ')) for(const dep of JSON.parse(line.slice(10))) task(dep,name);
    let value=null;
    if(line.startsWith('run = ')) {found=true;value=line.slice(6);if(value==='['){array=true;continue;}}
    else if(array){if(line===']'){array=false;continue;}value=line.replace(/,$/,'');}
    if(value===null)continue;
    if(!/^(?:'.*'|".*")$/.test(value))throw Error('Unsupported task command '+name+': '+line);
    const command=value[0]==="'"?value.slice(1,-1):JSON.parse(value);
    const row={id:'task-command:'+name+':'+i,task:name,via,command,definition};commands.push(row);
    if(command.startsWith('mise run ')) {
      row.classification='task-container';
      const nested=command.split(/\s+/).filter(x=>defs[x]);
      if(!nested.length)throw Error('Unresolved nested task');
      for(const next of nested)task(next,name);
    } else {
      row.classification=/moon\.exe\s+(?:-C\s+\S+\s+)?(?:build|fmt|check)\b|scripts[\\/]+(?:prepare-|package-|build-)/.test(command)?'preparation-or-build':'verification';
      add(item(row.id,command,'mise.toml:'+name,'hook-command',definition,{task:name,classification:row.classification,coverage_unit:'complete command with all cases/branches; named tests linked separately'}));
    }
    for(const m of command.matchAll(/scripts[\\/]+([\w-]+\.mbtx)/g))visitSource('scripts/'+m[1],name);
    for(const m of command.matchAll(/(?:scripts|tools)[\\/]+[\w/\\.-]+\.mjs/g))visitSource(m[0].replace(/\\+/g,'/'),name);
  }
  if(!found)throw Error('Task missing run '+name);
}
for(const name of policy.full_gate_tasks)task(name,'full gate / push fallback');
// Executable paths are a second source boundary: inspect owned entry packages,
// even though they are not .mbtx scripts and have no named test blocks.
for(const row of commands) {
  const normalized=row.command.replace(/\\+/g,'/');
  const roots=[];
  for(const m of normalized.matchAll(/(?:local\/native_host\/([\w]+)\/[\w]+\.exe|tools\/([\w]+)\/[\w]+\.(?:wasm|js))/g))roots.push(m[1]?'native_host/'+m[1]:'tools/'+m[2]);
  row.entry_sources=[];
  for(const dir of roots) {
    if(!fs.existsSync(path.join(root,dir)))throw Error('Missing executable source '+dir);
    for(const f of fs.readdirSync(path.join(root,dir)).filter(f=>f.endsWith('.mbt'))) {
      const file=dir+'/'+f;row.entry_sources.push(file);visitSource(file,row.id);
    }
  }
}
for(const file of ['scripts/pre-commit.mbtx','scripts/record-commit-verification.mbtx','scripts/verify-push-recorded.mbtx','scripts/collect-verification-inputs.mbtx','scripts/plan-local-verification.mbtx','scripts/plan-native-verification.mbtx','scripts/verify-reactive-negative.mbtx','scripts/verify-types.mbtx','scripts/verify-docs.mbtx','scripts/verify-static-analysis.mbtx','scripts/verify-application-build-inputs.mbtx','scripts/verify-window-fixture-exclusion.mbtx','scripts/verify-window-production-exclusion.mbtx']) visitSource(file,'hook orchestration');
// Cover every direct invocation in the hook, including loops and conditional
// commands. The enclosing source supplies their target/condition bindings.
const hook=scripts.get('scripts/pre-commit.mbtx');
for(const site of hook.process_sites.filter(s=>s.callee==='run'||s.callee==='expect_clean'))
  add(item('hook-site:'+site.line,site.code,'scripts/pre-commit.mbtx','hook-command',site.code,{line:site.line,coverage_unit:'call site; enclosing target loop/condition in source graph'}));
for(const n of ['root-only-dossier','hook-node-dossier','browser-async-dossier','native-async-dossier','native-host-dossier','wgpu-dossier']) {
  for(const t of load(n).tests)add({...t,inventory_source:n});
}
const windows=load('window-dep-dossier').tests;
const windowsSelected=windows.filter(t=>/^(minimum|owned windows retain capture|pointer cancellation)/.test(t.name));
if(windowsSelected.length!==5)throw Error('Window selector changed');
for(const t of windowsSelected)add({...t,inventory_source:'build-native window-probe filters'});
const contracts=load('contract-dossier');
for(const t of [...contracts.tests,...contracts.scope_exclusions])add({...t,conditional_scope:t.conditional?'reactive_contracts_changed':'all',inventory_source:'contract tables'});
for(const platform of ['NATIVE','BROWSER']) for(const entry of ['../outside','/absolute','app//main','--help',''])
  add(item('application-input:'+platform+':'+entry,platform+' rejects '+JSON.stringify(entry),'scripts/verify-application-build-inputs.mbtx','contract-case',JSON.stringify({platform,entry,expected:'nonzero exit; path/required diagnostic; no dependency preparation'})));
for(const [name,expected] of [['invalid','parser rejects'],['memo-bad',1],['memo-concise-bad',1],['memo-good',0],['memo-nested-good',0]])
  add(item('static-fixture:'+name,name,'tools/static_analysis/fixtures/'+name+'.mbt.txt','static-analysis-case',JSON.stringify({source:read('tools/static_analysis/fixtures/'+name+'.mbt.txt'),expected})));
// Patch introduces exactly the six tests selected by the named-pipe verifier.
const patch=read('experiments/async_named_pipe/windows-named-pipe.patch');
const pipeNames=[...patch.matchAll(/^\+async test "([^"]+)"/gm)].map(m=>m[1]);
if(pipeNames.length!==6)throw Error('Named pipe test inventory changed');
for(const name of pipeNames)add(item('pipe:'+name,name,'experiments/async_named_pipe/windows-named-pipe.patch','dependency-test',name,{target:'native',via:'scripts/verify-named-pipe.mbtx'}));
// Parser corpus is checked on preparation cache misses. Retain all cases as a
// conditional group rather than dropping tests on a warm local cache.
const corpus='.work/jev-metonic/parser-corpus';
function walk(dir){return fs.readdirSync(path.join(root,dir),{withFileTypes:true}).flatMap(e=>e.isDirectory()?walk(dir+'/'+e.name):[dir+'/'+e.name]);}
let corpusCount=0;
for(const file of walk(corpus).filter(f=>f.endsWith('.txt'))) {
  const source=read(file);sourceDigests[file]=sha(source);
  const headings=[...source.matchAll(/^={3,}\r?\n([^\r\n]+)\r?\n(?:[^=\r\n][^\r\n]*\r?\n)*={3,}\r?\n/gm)];
  if(!headings.length)throw Error('Unrecognized corpus '+file);
  for(let i=0;i<headings.length;i++) {
    const h=headings[i];corpusCount++;
    add(item('corpus:'+file+':'+i,h[1],file,'parser-corpus',source.slice(h.index,headings[i+1]?.index??source.length),{conditional_scope:'static parser preparation cache miss'}));
  }
}
// Record immutable source fingerprints and the explicit boundary of completeness.
for(const f of ['.githooks/pre-commit','.githooks/pre-push','mise.toml','verification.json'])sourceDigests[f]=sha(read(f));
const coverage={scope:'Union of pre-commit, pre-push remainder and missing-record full fallback in this worktree, including conditional cases',granularity:'named runner tests plus complete verifier/command units; commands and their children are not additive independent test counts',tasks:[...tasks],commands,sources:[...scripts.values()],sourceDigests,windows_selected:windowsSelected.length,named_pipe_cases:pipeNames.length,parser_cases:corpusCount,unresolved_task_commands:0,exclusions:['opt-in native:window-display','repository tests not reachable from installed hooks'],not_proven:'Runtime success, arbitrary dynamic call-graph completeness, and exact selection for a particular staged diff are not proven by this static catalog'};
const dossier={...base,tests:[...entries.values()],kind:'unified',scope:coverage.scope,coverage};
const tracked=cp.execFileSync('git',['ls-files','-z','--','*.mbt'],{cwd:root,encoding:'utf8'}).split('\0').filter(Boolean);
const assigned=new Set([...entries.values()].map(t=>t.file+':'+t.start_line));
const outside=[];let definitionCount=0;
for(const file of tracked) {
  const source=read(file),tree=parse('moonbit',source).root();
  if(tree.findAll({rule:{kind:'ERROR'}}).length)throw Error('Source audit parse error '+file);
  for(const node of tree.findAll({rule:{kind:'test_definition'}})) {
    definitionCount++;const line=node.range().start.line+1;
    if(!assigned.has(file+':'+line)) {
      if(!file.startsWith('consumers/'))throw Error('Unassigned hook-owned test '+file+':'+line);
      outside.push({file,line,declaration:node.text().split('\n')[0],reason:'consumer module is not invoked by any installed hook moon test command'});
    }
  }
  sourceDigests[file]=sha(source);
}
coverage.tracked_moonbit_definitions=definitionCount;
coverage.outside_hook_tests=outside;
coverage.unassigned_hook_owned_definitions=0;
const testInvokingScripts=[...scripts.values()].filter(s=>s.file.startsWith('scripts/')&&/"test"|node --test/.test(read(s.file))).map(s=>s.file);
const reviewedInvocations={
 'scripts/pre-commit.mbtx':'root/all targets and async runtime inventories',
 'scripts/verify.mbtx':'root/all targets, native_host and async runtime inventories',
 'scripts/build-native.mbtx':'five window constraint/capture cases, notes-probe condition',
 'scripts/verify-wgpu-binding.mbtx':'13 wgpu binding cases',
 'scripts/verify-named-pipe.mbtx':'six patch-defined named pipe cases',
 'scripts/prepare-static-analysis.mbtx':'all parser corpus cases, cache-miss condition',
 'scripts/plan-native-verification.mbtx':'28 native_host cases; change-dependent package selection',
 'scripts/prepare-native-deps.mbtx':'test import configuration only; no test execution',
};
for(const file of testInvokingScripts)if(!reviewedInvocations[file])throw Error('Unreviewed test invocation '+file);
coverage.test_invocation_mapping=reviewedInvocations;
coverage.revision=cp.execFileSync('git',['rev-parse','HEAD'],{cwd:root,encoding:'utf8'}).trim();
coverage.working_tree_changes=cp.execFileSync('git',['diff','--name-only'],{cwd:root,encoding:'utf8'}).trim().split('\n').filter(Boolean);
const escaped=s=>String(s??'').replaceAll('|','\\|').replaceAll('\n',' ');
const report=['# Hook inventory','',`Snapshot: ${coverage.revision} plus the recorded worktree changes.`,
 '','Scope: union of pre-commit, pre-push and full fallback. Conditional cases remain in the inventory.',
 '','Rows include commands, their supporting checks, and named child tests. Do not sum them as independent test executions.',
 '','| Kind | ID | Name | Source |','|---|---|---|---|',
 ...dossier.tests.map(t=>`| ${escaped(t.kind)} | ${escaped(t.id)} | ${escaped(t.name)} | ${escaped(t.file)} |`),
 '','## Outside installed hook test selection','',
 ...outside.map(t=>`- ${t.file}:${t.line}: ${t.declaration}`),''];
fs.writeFileSync(path.join(out,'hook-inventory.md'),report.join('\n'));
fs.writeFileSync(path.join(out,'hook-inventory.json'),JSON.stringify(dossier));
fs.writeFileSync(path.join(out,'hook-inventory-coverage.json'),JSON.stringify(coverage,null,2));
console.log(JSON.stringify({items:entries.size,tasks:tasks.size,task_commands:commands.length,sources:scripts.size,parser_cases:corpusCount}));
