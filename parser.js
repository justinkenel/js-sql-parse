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

function parserDefinition(options) {
options = options || {};
options.stringEscape=options.stringEscape || (x=>'"'+x+'"');
options.identifierEscape=options.identifierEscape || (x=>'`'+x+'`');
return {
  toSql(parsed) {
    if(!parsed) return '';
    if(!parsed.type) return '';
    const spacing=options.spacing || '';

    options = options || {};
    switch(parsed.type) {
    case 'create_view': {
      const table=this.toSql(parsed.table, options);
      const definition=this.toSql(parsed.definition, options);
      let sql='create ';
      if(parsed.replace) sql+='or replace ';
      sql+=('view ' + table + ' as '+definition);
      return sql;
    }
    case 'select': {
      let sql='(select ';
      if(parsed.top) sql+='top '+parsed.top+' ';
      if(parsed.all_distinct) sql+=this.toSql(parsed.all)+' ';
      let selection;
      if(parsed.selection.columns) selection=parsed.selection.columns.map(x=>this.toSql(x)).join(', ');
      else selection=this.toSql(parsed.selection);
      sql+=selection;
      if(parsed.table_exp) sql+=' '+this.toSql(parsed.table_exp);
      return sql+')';
    }
    case 'union': {
      const left=this.toSql(parsed.left);
      const right=this.toSql(parsed.right);
      return '(('+left+') union ('+right+'))';
    }
    case 'from': {
      let sql='from (';
      if(parsed.table_refs) sql+=parsed.table_refs.map(x=>this.toSql(x)).join(', ');
      else if(parsed.subquery) sql+=this.toSql(parsed.subquery);
      return sql+')';
    }
    case 'from_table': {
      let sql=this.toSql(parsed.from);
      if(parsed.where) sql+=' '+this.toSql(parsed.where);
      if(parsed.groupby) sql+=' '+this.toSql(parsed.groupby);
      if(parsed.having) sql+=' '+this.toSql(parsed.having);
      if(parsed.order) sql+=' '+this.toSql(parsed.order);
      return sql;
    }
    case 'all': return 'all';
    case 'distinct': return 'distinct';
    case 'group_by': {
      let sql='group by ('+this.toSql(parsed.columns)+')';
			if(parsed.with_rollup) sql+= ' with rollup';
			return sql;
    }
    case 'select_all': return '*';
    case 'column': {
      let sql='';
      if(parsed.expression) {
        sql+=this.toSql(parsed.expression);
      }
      else if(parsed.name) {
        if(parsed.table) sql+=options.identifierEscape(parsed.table)+'.';
        sql+=options.identifierEscape(parsed.name);
      }
      if(parsed.alias) sql+=' as '+this.toSql(parsed.alias);
      return sql;
    }
    case 'expr_comma_list': {
      return parsed.exprs.map(x=>this.toSql(x)).join(', ');
    }
    case 'table_ref': {
      let sql='('+this.toSql(parsed.left);
      if(parsed.side) sql+=' '+parsed.side+' ';
      sql+='join '+this.toSql(parsed.right);
      if(parsed.on) sql+=' on '+this.toSql(parsed.on);
			sql+=')';
			if(parsed.alias) sql += ' as '+this.toSql(parsed.alias);
      return sql;
    }
    case 'table': {
      let sql=options.identifierEscape(parsed.table);
      if(parsed.alias)sql+='as '+options.identifierEscape(parsed.alias);
      return sql;
    }
    case 'where': {
      let sql='where (';
      const condition=this.toSql(parsed.condition);
      sql+=condition+')';
      return sql;
    }
    case 'having': {
      let sql='having (';
      const condition=this.toSql(parsed.condition);
      sql+=condition+')';
      return sql;
    }
    case 'selection_columns': {
      return parsed.columns.map(x=>this.toSql(x)).join(', ');
    }
    case 'order': {
      let sql='order by (';
      sql+=parsed.order.map(x => this.toSql(x)).join(', ')+')';
      return sql;
    }
    case 'order_statement': {
      const value=this.toSql(parsed.value);
      sql=value;
      if(parsed.direction) sql+=' '+parsed.direction;
      return sql;
    }
    case 'operator': {
      let sql='(';
      if(parsed.operator=='not') {
        const operand=this.toSql(parsed.operand);
        sql+='not '+operand;
      } else {
        const left=this.toSql(parsed.left);
        const right=this.toSql(parsed.right);
        sql+=left+' '+parsed.operator+' '+right;
      }
      return sql+')';
    }
    case 'is_null': {
      const value=this.toSql(parsed.value);
      let sql='('+value+' is ';
      if(parsed.not) sql+='not ';
      sql+='null)';
      return sql;
    }
    case 'in': {
      const value=this.toSql(parsed.value);
      let sql='('+value+' ';
      if(parsed.not) sql+='not';
      sql+='in ';
      if(parsed.subquery) sql+='('+this.toSql(parsed.subquery)+')';
      else if(parsed.expressions) sql+='('+parsed.expressions.map(x=>this.toSql(x)).join(', ')+')';
      return sql+')';
    }
    case 'between': {
      const value=this.toSql(parsed.value);
      const lower=this.toSql(parsed.lower);
      const upper=this.toSql(parsed.upper);
      let sql='('+value+' ';
      if(parsed.not) sql+='not ';
      sql+='between '+lower+' and '+upper+')';
      return sql;
    }
    case 'like': {
      const value=this.toSql(parsed.value);
      const comparison=this.toSql(parsed.comparison);
      let sql='('+value+' ';
      if(parsed.not) sql+='not ';
      sql+='like '+comparison+')';
      return sql;
    }
    case 'exists': {
      const query=this.toSql(parsed.query);
      return '(exists '+query+')';
    }
    case 'null': return 'null';
    case 'true': return 'true';
    case 'false': return 'false';
    case 'if': {
      const condition=this.toSql(parsed.condition);
      const then=this.toSql(parsed.then);
      const elseExpr=this.toSql(parsed['else']);
      return 'if('+condition+', '+then+', '+elseExpr+')';
    }
    case 'case': {
      let sql='(case ';
      if(parsed.match) sql+= this.toSql(parsed.match)+' ';
      sql+=parsed.when_statements.map(when => this.toSql(when)).join(' ');
      if(parsed['else']) {
        sql+=' else '+this.toSql(parsed['else']);
      }
      sql+=' end)';
      return sql;
    }
    case 'when': {
      const condition=this.toSql(parsed.condition);
      const then=this.toSql(parsed.then);
      return 'when '+condition+' then '+then;
    }
    case 'convert': {
      const value=this.toSql(parsed.value);
      const using=this.toSql(parsed.using);
      return 'conver('+value+' using '+using+")";
    }
    case 'interval': {
      const value=this.toSql(parsed.value);
      const unit=this.toSql(parsed.unit);
      return 'interval '+value+ ' '+unit;
    }
    case 'cast': {
      const value=this.toSql(parsed.value);
      const type=this.toSql(parsed.data_type);
      return 'cast('+value+' as '+type+')';
    }
    case 'data_type': {
      let sql=parsed.data_type;
      if(parsed.size) sql+='('+parsed.size+')';
      else if(parsed.size1) sql+='('+parsed.size1+', '+parsed.size2+')';
      return sql;
    }
    case 'date_unit': {
      return parsed.date_unit;
    }
    case 'function_call': {
      let sql=parsed.name.value + '(';
      if(parsed.select_all) return sql+'*)';
      if(!parsed.parameters.length) return sql+')';
      if(parsed.distinct) sql += 'distinct ';
      if(parsed.all) sql += 'all ';
      sql += parsed.parameters.map(p => this.toSql(p)).join(', ');
      return sql+')';
    }
    case 'string': {
      return options.stringEscape(parsed.string);
    }
    case 'identifier': {
      return options.identifierEscape(parsed.value);
    }
    case 'decimal':{
      return parsed.value;
    }}
    return '-- Invalid sql.type: ' + parsed.type + '\n';
  },
  parse(sql) {
		sql += '\n';

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
    if(operation=='create_view') {
      createdTables=[result.table.table];
      sourceTables=Object.keys(referencedTables).filter(x => x != result.table.table);
    } else {
      sourceTables=Object.keys(referencedTables);
    }

    const returnColumns=[];
    if(operation=='select') {
      if(result.selection && result.selection.columns) {
        result.selection.columns.forEach(column => {
          const sourceColumns=[];
          walk(column.expression, n => {
            if(n.type=='column') {
              sourceColumns.push(n);
              return false;
            }
            if(n.type=='identifier') {
              sourceColumns.push(n);
              return false;
            }
          });
          let name;
          if(column.alias) name=column.alias.value;
          else name=column.expression;
          returnColumns.push({
            name: name,
            sourceColumns: sourceColumns
          });
        });
      }
    }

    return {
      referencedTables: Object.keys(referencedTables),
      createdTables: createdTables,
      sourceTables: sourceTables,
      operation: operation,
      parsed: result,
      joins: joins,
      returnColumns: returnColumns
    };
  }
};};

const basicParser=parserDefinition({});
parserDefinition.parse=function(sql){return basicParser.parse(sql);}
parserDefinition.toSql=function(parsed){return basicParser.toSql(parsed);}

module.exports=parserDefinition;
