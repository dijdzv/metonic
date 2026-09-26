// Native AST boundary. Retains all inventory identities and existing test symbols.
const fs=require('node:fs'),path=require('node:path');
const root=path.resolve(__dirname,'../..');
const {parse,registerDynamicLanguage}=require(path.join(root,'.work/jev-ast/node_modules/@ast-grep/napi'));
registerDynamicLanguage({moonbit:{libraryPath:path.join(root,'.work/jev-ast/tree-sitter-moonbit.dll'),extensions:['mbt','mbtx']}});
const input=JSON.parse(fs.readFileSync(process.argv[2],'utf8'));
const before=input.tests.map(t=>t.id),stats={source_enriched:0,corpus_enriched:0,unavailable:0};
const cache=new Map();
for(const t of input.tests) {
  if(t.symbols?.length)continue;
  if(t.kind==='parser-corpus') {
    // Expected grammar nodes describe syntax coverage, not application dependencies.
    const expected=t.test_body.split(/^\s*-{3,}\s*$/m).slice(1).join('\n');
    t.symbols=[...new Set([...expected.matchAll(/\(([a-zA-Z_][a-zA-Z_0-9]*)/g)].map(m=>'grammar:'+m[1]))].sort();
    t.symbols_origin='expected grammar node kinds; not resolved application references';
    if(t.symbols.length)stats.corpus_enriched++;else stats.unavailable++;
    continue;
  }
  if(!['script-verifier','supporting-verification'].includes(t.kind))continue;
  if(!/\.(mbt|mbtx|mjs|js)$/.test(t.file))continue;
  const absolute=path.resolve(root,t.file);
  if(!absolute.startsWith(root+path.sep))throw Error('Source outside root');
  if(!cache.has(t.file)) {
    const mb=/\.mbtx?$/.test(t.file),tree=parse(mb?'moonbit':'JavaScript',fs.readFileSync(absolute,'utf8')).root();
    if(tree.findAll({rule:{kind:'ERROR'}}).length) {cache.set(t.file,null);}
    else if(mb)cache.set(t.file,[...new Set(tree.findAll({rule:{any:[{kind:'qualified_identifier'},{kind:'qualified_type_identifier'},{kind:'method_expression'},{kind:'dot_identifier'}]}}).map(n=>n.text()))].sort());
    else cache.set(t.file,[...new Set(tree.findAll({rule:{kind:'call_expression'}}).map(n=>n.children()[0]?.text()).filter(Boolean))].sort());
  }
  const symbols=cache.get(t.file);
  if(symbols===null){t.symbols_origin='parser unavailable';stats.unavailable++;continue;}
  t.symbols=symbols;
  t.symbols_origin='syntactic references in verifier source; includes locals and shared setup';
  stats.source_enriched++;
}
if(JSON.stringify(before)!==JSON.stringify(input.tests.map(t=>t.id)))throw Error('Inventory changed');
input.symbol_enrichment=stats;
fs.writeFileSync(process.argv[3],JSON.stringify(input));
console.log(JSON.stringify({items:before.length,...stats}));
