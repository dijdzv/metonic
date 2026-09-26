// AST-grep native API boundary; never loads .env or executes verifier code.
const fs = require('node:fs');
const path = require('node:path');
const cp = require('node:child_process');
const root = path.resolve(__dirname, '../..');
const {parse,registerDynamicLanguage} = require(path.join(root,'.work/jev-ast/node_modules/@ast-grep/napi'));
registerDynamicLanguage({moonbit:{libraryPath:path.join(root,'.work/jev-ast/tree-sitter-moonbit.dll'),extensions:['mbt','mbtx']}});
const input = JSON.parse(fs.readFileSync(process.argv[2],'utf8'));
const complete = process.argv.includes('--complete');
if(input.kind !== 'integration-gates') throw Error('Expected gate dossier');
const tracked = cp.execFileSync('git',['ls-files','-z'],{cwd:root,encoding:'utf8'}).split('\0').filter(Boolean);
const allowed = new Set(tracked.filter(f=>/^(scripts|tools|native_host|browser_host|examples|async_runtime)\/.+\.(mbt|mbtx|mjs|js)$/.test(f)));
const cache = new Map();
const references = text => {
  const found = new Set();
  text = text.replace(/\\\\+/g,'/');
  for(const m of text.matchAll(/(?:scripts|tools|native_host|browser_host|examples|async_runtime)\/[a-zA-Z0-9_./-]+/g)) {
    const p=m[0].replace(/[./]+$/,'');
    if(allowed.has(p)) found.add(p);
    else if(!path.extname(p)) for(const f of allowed) if(f.startsWith(p+'/') && /\.mbt$/.test(f)) found.add(f);
  }
  // Native artifacts identify the entry package even when the build script
  // constructs its source path dynamically from an environment variable.
  for(const m of text.matchAll(/local\/native_host\/([a-zA-Z0-9_]+)\/[a-zA-Z0-9_]+\.exe/g)) {
    const prefix='native_host/'+m[1]+'/';
    for(const f of allowed) if(f.startsWith(prefix) && /\.mbt$/.test(f)) found.add(f);
  }
  return [...found];
};
function inspect(file) {
  if(cache.has(file))return cache.get(file);
  const source=fs.readFileSync(path.join(root,file),'utf8');
  const mb=/\.mbtx?$/.test(file);
  const tree=parse(mb?'moonbit':'JavaScript',source).root();
  const errors=tree.findAll({rule:{kind:'ERROR'}}).length;
  const entries=[];
  for(const node of tree.findAll({rule:{kind:mb?'apply_expression':'call_expression'}})) {
    const callee=node.children()[0]?.text()??'';
    if(!/(?:assert|expect)/i.test(callee)) continue;
    const text=node.text();
    entries.push({line:node.range().start.line+1,callee,code:complete?text:text.slice(0,400),excerpt:!complete && text.length>400});
  }
  const result={file,parse_errors:errors,entries,references:references(source)};
  cache.set(file,result);return result;
}
const started=performance.now();
const summary=[];
for(const item of input.tests) {
  const queue=references(item.test_body), seen=new Set(), evidence=[];
  let omitted=0,chars=0;
  for(let i=0;i<queue.length;i++) {
    const file=queue[i]; if(seen.has(file))continue;seen.add(file);
    const data=inspect(file);
    for(const ref of data.references)if(!seen.has(ref))queue.push(ref);
    if(data.parse_errors){evidence.push({file,parse_errors:data.parse_errors});continue;}
    for(const entry of data.entries){
      const row={file,...entry}; const size=JSON.stringify(row).length;
      if(!complete && chars+size>12000){omitted++;continue;}
      evidence.push(row);chars+=size;
    }
  }
  const contract={task_definition:item.test_body,observations:evidence,coverage:'best-effort syntactic extraction; dynamic imports, generated artifacts and runtime paths may be missing',omitted_entries:omitted,visited_files:[...seen]};
  item.required = omitted > 0 || evidence.length === 0 || evidence.some(e=>e.parse_errors > 0 || e.excerpt);
  item.evidence_status = item.required ? 'incomplete' : 'syntactic-evidence';
  item.test_body=JSON.stringify(contract);
  item.symbols=[...new Set(evidence.map(e=>e.callee).filter(Boolean))];
  summary.push({id:item.id,files:seen.size,observations:evidence.length,omitted});
}
input.gate_evidence={elapsed_ms:Math.round(performance.now()-started),parsed_files:cache.size,summary};
fs.writeFileSync(process.argv[3],JSON.stringify(input));
console.log(JSON.stringify(input.gate_evidence));
