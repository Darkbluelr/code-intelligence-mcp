const protobuf = require('protobufjs');
const fs = require('fs');

async function main() {
  try {
    const root = await protobuf.load('/tmp/scip.proto');
    const Index = root.lookupType('scip.Index');
    
    const buffer = fs.readFileSync('index.scip');
    const index = Index.decode(buffer);
    
    console.log('=== SCIP Index Summary ===');
    const toolInfo = index.metadata && index.metadata.toolInfo;
    console.log('Tool:', toolInfo ? toolInfo.name : 'unknown', toolInfo ? toolInfo.version : '');
    console.log('Project Root:', index.metadata ? index.metadata.projectRoot : '');
    console.log('Documents:', index.documents ? index.documents.length : 0);
    console.log('External Symbols:', index.externalSymbols ? index.externalSymbols.length : 0);
    
    if (index.documents && index.documents.length > 0) {
      console.log('\n=== Documents ===');
      index.documents.forEach(function(doc, i) {
        const symCount = doc.symbols ? doc.symbols.length : 0;
        const occCount = doc.occurrences ? doc.occurrences.length : 0;
        console.log((i+1) + '. ' + doc.relativePath + ' (' + symCount + ' symbols, ' + occCount + ' occurrences)');
      });
      
      const doc = index.documents[0];
      if (doc.symbols && doc.symbols.length > 0) {
        console.log('\n=== Sample Symbols with Relationships (first 15) ===');
        doc.symbols.slice(0, 15).forEach(function(sym, i) {
          console.log((i+1) + '. ' + sym.symbol);
          if (sym.relationships && sym.relationships.length > 0) {
            sym.relationships.forEach(function(rel) {
              var relType = rel.isImplementation ? 'IMPLEMENTS' : 
                            rel.isTypeDefinition ? 'TYPE_DEF' :
                            rel.isReference ? 'REFERENCE' :
                            rel.isDefinition ? 'DEFINITION' : 'RELATED';
              console.log('   -> ' + relType + ': ' + rel.symbol.slice(0, 80));
            });
          }
        });
      }
    }
    
    console.log('\n=== SUCCESS: SCIP parsing works with protobufjs! ===');
  } catch (err) {
    console.error('Error:', err.message);
    console.error(err.stack);
  }
}

main();
