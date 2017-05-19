const nearley = require('nearley');
const grammar = require('./sql-parse');

let count=0;
function walk(obj, fn) {
  if(!obj) return;
  const result = fn(obj);
  if(result == false) return;
  if(typeof obj == 'object') {
    for(i in obj) {
      walk(obj[i], fn);
    }
  }
}

module.exports = {
  parse(sql, options) {
    options = options || {};

    const parser = new nearley.Parser(grammar.ParserRules, grammar.ParserStart);
    const parsed = parser.feed(sql);

    const parsedResult = parsed.results;
    if(!parsedResult.length) throw 'Invalid sql: ' + sql;
    if(parsedResult.length > 1) {
      // console.error(JSON.stringify(parsedResult, null, 2));
      throw 'SQL ambiguous: Report to developers ' + sql;
    }

    const result = parsedResult[0];

    const referencedTables = {};
    const joins = [];
    walk(result, node => {
      if(node.type == 'table') referencedTables[node.table] = node;
      if(node.type == 'table_ref' && node.on) {
        const columns = [];
        walk(node.on, n => {
          if(n.type == 'table_ref') return false;
          if(n.type == 'column') {
            columns.push(n);
            return false;
          }
        });
        joins.push({
          right: node.right,
          columns: columns
        });
      }
    });

    const operation = result.type;

    let createdTables, sourceTables;
    if(operation == 'create_view') {
      createdTables=[result.table.table];
      sourceTables=Object.keys(referencedTables).filter(x => x != result.table.table);
    } else {
      sourceTables=Object.keys(referencedTables);
    }

    return {
      referencedTables: Object.keys(referencedTables),
      createdTables: createdTables,
      sourceTables: sourceTables,
      operation: operation,
      parsed: result,
      joins: joins
    };
  }
};
