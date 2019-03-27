

# @builtin "whitespace.ne"
@builtin "number.ne"

@{%
  function drill(o) {
    //if(o && o.length==1 && o[0]) return drill(o[0]);
    return o;
  }

  const reserved=require('./reserved.json');
  const valid_function_identifiers=['LEFT','RIGHT','REPLACE','MOD']
%}

main -> sql (_ ";" | _) {% d => d[0] %}

sql ->
    manipulative_statement {% d => d[0] %}
  | create_view {% d => d[0] %}

create_view ->
    CREATE (__ OR __ REPLACE __ | __) VIEW __ table __ AS __ query_spec {%
      d => ({
        type: 'create_view',
        table: d[4],
        definition: d[8],
        replace: !!d[1][1]
      })
    %}

manipulative_statement ->
     select_statement {% d => d[0] %}

select_statement ->
    query_spec {% d => d[0] %}

top_spec -> TOP __ int {% d => d[2] %}

query_spec ->
    "(" _ query_spec _ ")" {% d => d[2] %}
  | SELECT (__ top_spec | null) (__ all_distinct __ | __) selection  {%
      d => ({
        type: 'select',
        top: (d[1]||[])[1],
        all_distinct: (d[2]||[])[1],
        selection: d[3]
      })
    %}
  | SELECT (__ top_spec | null) (__ all_distinct __ | __) selection __ table_exp {%
      d => ({
        type: 'select',
        top: (d[1]||[])[1],
        all_distinct: (d[2]||[])[1],
        selection: d[3],
        table_exp: d[5]
      })
    %}
  | query_spec __ UNION __ query_spec {%
      d => ({
        type: 'union',
        left: d[0],
        right: d[4]
      })
    %}

table_exp ->
    from_clause (__ where_clause | null) (__ group_by_clause | null) (__ having_clause | null) (__ order_clause | null) (__ limit_clause | null) {%
      d => ({
        type: 'from_table',
        from: d[0],
        where: (d[1] || [])[1],
        groupby: (d[2] || [])[1],
        having: (d[3] || [])[1],
        order: (d[4] || [])[1],
				limit: (d[5] || [])[1]
      })
    %}

all_distinct ->
    ALL {% d => ({type: 'all'}) %}
  | DISTINCT {% d => ({type: 'distinct'}) %}

from_clause ->
    FROM __ table_ref_commalist {% d => ({type: 'from', table_refs: d[2].table_refs}) %}
  | FROM __ subquery {% d => ({type: 'from', subquery: d[2]}) %}

group_by_clause ->
		group_by_clause_inner {% d => d[0] %}
	| group_by_clause_inner __ WITH __ ROLLUP {% d => Object.assign({}, d[0], {with_rollup:true}) %}

group_by_clause_inner ->
    GROUP __ BY __ selection_column_comma_list {% d => ({ type: 'group_by', columns: d[4] }) %}
  | GROUP __ BY "(" _ selection_column_comma_list _ ")" {% d => ({ type: 'group_by', columns: d[6] }) %}

selection ->
    "*" {% d => ({type:'select_all'}) %}
  | selection_column_comma_list {% d => d[0] %}

selection_column_comma_list ->
    selection_column {% d => ({type: 'selection_columns', columns: [d[0]]}) %}
  | selection_column_comma_list _ "," _ selection_column {%
      d => ({
        type: 'selection_columns',
        columns: (d[0].columns||[]).concat([d[4]])
      })
    %}

selection_column ->
    expr {% d => ({type: 'column', expression: drill(d[0])}) %}
  | expr __ AS __ identifier {% d => ({type: 'column', expression: drill(d[0]), alias: d[4]}) %}

table_ref_commalist ->
    table_ref {% d => ({table_refs: [d[0]]}) %}
  | table_ref_commalist _ "," _ table_ref {% d => ({ table_refs: (d[0].table_refs||[]).concat(d[4]) }) %}

@{%
  function tableRef(d, onOffset) {
		if(!onOffset) onOffset = 0;
    const ref = {
      type: 'table_ref',
      side: ((d[1]||[])[1]),
      left: d[0],
      right: d[4],
      on: d[onOffset+8]
    };
		if(onOffset) ref.alias = d[6];
		return ref;
  }
%}

table_ref ->
    "(" _ table_ref _ ")" {% d => d[2] %}
  | table {% d => d[0] %}
  | table_ref (__ LEFT __ | __ RIGHT __ | __ INNER __ | __) JOIN __ table __ ON __ expr {% x=>tableRef(x,0) %}
  | table_ref (__ LEFT __ | __ RIGHT __ | __ INNER __ | __) JOIN __ table __ ON ("(" _ expr _ ")") {% x=>tableRef(x,0) %}
	| table_ref (__ LEFT __ | __ RIGHT __ | __ INNER __ | __) JOIN __ query_spec (AS __ | __) identifier __ ON __ expr {% x=>tableRef(x,2) %}
	| table_ref (__ LEFT __ | __ RIGHT __ | __ INNER __ | __) JOIN __ query_spec (AS __ | __) identifier __ ON ("(" _ expr _ ")") {% x=>tableRef(x,2) %}

table ->
    identifier {% d => ({type: 'table', table: d[0].value}) %}
  | identifier "." identifier {% d => ({type: 'table', table: d[0].value +'.'+ d[2].value }) %}
  | identifier ( __ AS __ | __) identifier {% d => ({type: 'table', table: d[0].value, alias: d[2].value}) %}

where_clause ->
    WHERE __ expr {% d => ({type:'where', condition: d[2]}) %}
  | WHERE "(" _ expr _ ")" {% d => ({type:'where', condition: d[3]}) %}

having_clause ->
    HAVING __ expr {% d => ({type: 'having', condition: d[2]}) %}
  | HAVING "(" _ expr _ ")" {% d => ({type: 'having', condition: d[3]}) %}

order_clause ->
    ORDER __ BY __ order_statement_comma_list {% d => ({type: 'order', order: d[4].order}) %}
  | ORDER __ BY "(" _ order_statement_comma_list _ ")" {% d => ({type: 'order', order: d[5].order}) %}

order_statement_comma_list ->
    order_statement {% d => ({order: [d[0]]}) %}
  | order_statement_comma_list _ "," _ order_statement {%
      d => ({order: (d[0].order||[]).concat(d[4])})
    %}

order_statement ->
    expr {% d => ({type:'order_statement', value:d[0]}) %}
  | expr __ ASC {% d => ({type: 'order_statement', value: d[0], direction: 'asc'}) %}
  | expr __ DESC {% d => ({type: 'order_statement', value: d[0], direction: 'desc'}) %}

limit_clause -> LIMIT __ decimal {% d => ({type: 'limit_statement', limit: d[2]}) %}

column_ref ->
    expr {% d => ({type: 'column', expression: d[0]}) %}
  | expr __ AS __ identifier {% d => ({type: 'column', expression: d[0], alias: d[4].value}) %}

@{%
function opExpr(operator) {
  return d => ({
    type: 'operator',
    operator: operator,
    left: d[0],
    right: d[2]
  });
}

function opExprWs(operator) {
  return d => ({
    type: 'operator',
    operator: operator,
    left: d[0],
    right: d[4]
  });
}


function notOp(d) {
  return {
    type: 'operator',
    operator: 'not',
    operand: d[1]
  };
}
%}

# https://dev.mysql.com/doc/refman/5.7/en/expressions.html
expr ->
    pre_expr OR post_boolean_primary {% opExpr('or') %}
  | pre_expr "||" post_boolean_primary {% opExpr('or') %}
  | pre_expr XOR post_boolean_primary {% opExpr('xor') %}
  | pre_expr AND post_boolean_primary {% opExpr('and') %}
  | pre_expr "&&" post_boolean_primary {% opExpr('and') %}
  | NOT post_boolean_primary {% notOp %}
  | "!" post_boolean_primary {% notOp %}
  | pre_boolean_primary IS (__ NOT | null) __ (TRUE | FALSE | UNKNOWN)
  | boolean_primary {% d => d[0] %}

pre_expr ->
    expr __ {% d => d[0] %}
  | "(" _ expr _ ")" {% d => d[2] %}

post_expr ->
    __ expr {% d => d[1] %}
  | "(" _ expr _ ")" {% d => d[2] %}

mid_expr ->
    "(" _ expr _ ")" {% d => d[2] %}
  | __ "(" _ expr _ ")" {% d => d[3] %}
  | "(" _ expr _ ")" __ {% d => d[2] %}
  | __ expr __ {% d => d[1] %}

boolean_primary ->
    pre_boolean_primary IS (__ NOT | null) __ NULLX {% d => ({type: 'is_null', not: d[2], value:d[0]}) %}
  | boolean_primary "<=>" predicate {% opExpr('<=>') %}
  | boolean_primary _ comparison_type _ predicate {% d => (opExpr(d[2]))([d[0], null, d[4]]) %}
  | boolean_primary _ comparison_type _ (ANY | ALL) subquery
  | predicate {% d => d[0] %}

pre_boolean_primary ->
    "(" _ boolean_primary _ ")" {% d => d[2] %}
  | boolean_primary __ {% d => d[0] %}

post_boolean_primary ->
    "(" _ boolean_primary _ ")" {% d => d[2] %}
  | __ boolean_primary {% d => d[1] %}

comparison_type ->
    "=" {% d => d[0] %}
  | "<>" {% d => d[0] %}
  | "<" {% d => d[0] %}
  | "<=" {% d => d[0] %}
  | ">" {% d => d[0] %}
  | ">=" {% d => d[0] %}
  | "!=" {% d => d[0] %}

predicate ->
    in_predicate {% d => d[0] %}
  | between_predicate {% d => d[0] %}
  | like_predicate {% d => d[0] %}
  | bit_expr {% d => d[0] %}

in_predicate ->
    pre_bit_expr (NOT __ | null) IN _ subquery {% d => ({
      type:'in',
      value: d[0],
      not: d[1],
      subquery: d[4]
    }) %}
  | pre_bit_expr (NOT __ | null) IN _ "(" _ expr_comma_list _ ")" {% d => ({
      type: 'in',
      value: d[0],
      not: d[1],
      expressions: (d[6].expressions || [])
    }) %}

between_predicate ->
    pre_bit_expr (NOT __ | null) BETWEEN mid_bit_expr AND post_bit_expr {%
      d => ({
        type: 'between',
        value: d[0],
        not: d[1],
        lower: d[3],
        upper: d[5]
      })
    %}

mid_bit_expr ->
    "(" _ bit_expr _ ")" {% d => d[2] %}
  | __ "(" _ bit_expr _ ")" {% d => d[3] %}
  | "(" _ bit_expr _ ")" __ {% d => d[2] %}
  | __ bit_expr __ {% d => d[1] %}

like_predicate ->
    pre_bit_expr (NOT __ | null) LIKE post_bit_expr {%
      d => ({
        type: 'like',
        not: d[1],
        value: d[0],
        comparison: d[3]
      })
    %}

bit_expr ->
    bit_expr _ "|" _ simple_expr {% opExprWs('|') %}
  | bit_expr _ "&" _ simple_expr {% opExprWs('&') %}
  | bit_expr _ "<<" _ simple_expr {% opExprWs('<<') %}
  | bit_expr _ ">>" _ simple_expr {% opExprWs('>>') %}
  | bit_expr _ "+" _ simple_expr {% opExprWs('+') %}
  | bit_expr _ "-" _ simple_expr {% opExprWs('-') %}
  | bit_expr _ "*" _ simple_expr {% opExprWs('*') %}
  | bit_expr _ "/" _ simple_expr {% opExprWs('/') %}
  | pre_bit_expr DIV post_simple_expr {% opExpr('DIV') %}
  | pre_bit_expr MOD post_simple_expr {% opExpr('MOD') %}
  | bit_expr _ "%" _ simple_expr {% opExprWs('%') %}
  | bit_expr _ "^" _ simple_expr {% opExprWs('^') %}
  | bit_expr _ "+" _ interval_expr {% opExprWs('+') %}
  | bit_expr _ "-" _ interval_expr {% opExprWs('-') %}
  | interval_expr {% d => d[0] %}
  | simple_expr {% d => d[0] %}

pre_bit_expr ->
    bit_expr __ {% d => d[0] %}
  | "(" _ bit_expr _ ")" {% d => d[2] %}

post_bit_expr ->
    __ bit_expr {% d => d[1] %}
  | "(" _ bit_expr _ ")" {% d => d[2] %}

simple_expr ->
    literal {% d => d[0] %}
  | identifier {% d => d[0] %}
  | function_call {% d => d[0] %}
  # | simple_expr COLLATE
  | "(" _ expr_comma_list _ ")" {% d => d[2] %}
  | subquery {% d => d[0] %}
  | EXISTS _ subquery {% d => ({type: 'exists', query: d[2]}) %}
  | case_statement {% d => d[0] %}
  | if_statement {% d => d[0] %}
  | cast_statement {% d => d[0] %}
  | convert_statement {% d => d[0] %}
  | identifier "." identifier {% d => ({type: 'column', table: d[0].value, name: d[2].value}) %}

post_simple_expr ->
    __ simple_expr {% d => d[1] %}
  | "(" _ simple_expr _ ")" {% d => d[2] %}

literal ->
    string {% d => d[0] %}
  | decimal {% d => ({type: 'decimal', value: d[0]}) %}
  | NULLX {% d => ({type: 'null'}) %}
  | TRUE {% d => ({type: 'true'}) %}
  | FALSE {% d => ({type: 'false'}) %}

expr_comma_list ->
    expr {% d => ({type:'expr_comma_list', exprs: [d[0]]}) %}
  | expr_comma_list _ "," _ expr {% d => ({type:'expr_comma_list', exprs: (d[0].exprs||[]).concat(d[4])}) %}

if_statement ->
    IF _ "(" _ expr _ "," _ expr _ "," _ expr _ ")" {%
      d => ({
        type: 'if',
        condition: d[4],
        then: d[8],
        'else': d[12]
      })
    %}



case_statement ->
    CASE (__ | mid_expr) when_statement_list (__ ELSE __ expr __ | __) END {%
      d => ({
        type: 'case',
        match: d[1][0],
        when_statements: d[2].statements,
        'else': (d[3]||[])[3]
      })
    %}

when_statement_list ->
    when_statement {% d => ({statements: [d[0]]}) %}
  | when_statement_list __ when_statement {% d => ({
      statements: (d[0].statements||[]).concat([d[2]])
    })
  %}

when_statement ->
    WHEN __ expr __ THEN __ expr {%
      d => ({
        type: 'when',
        condition: d[2],
        then: d[6]
      })
    %}

subquery ->
    "(" _ query_spec _ ")" {% d => d[2] %}

convert_statement ->
    CONVERT _ "(" expr __ USING __ identifier ")" {%
      d => ({
        type: 'convert',
        value: d[2],
        using: d[4]
      })
    %}

interval_expr ->
    INTERVAL __ expr __ date_unit {%
      d => ({
        type: 'interval',
        value: d[2],
        unit: d[4]
      })
    %}

cast_statement ->
    CAST _ "(" _ expr __ AS __ data_type _ ")" {%
      d => ({
        type: 'cast',
        value: d[4],
        data_type: d[8]
      })
    %}

@{%
function dataType(data_type, size) {
  return {
    type: 'data_type',
    data_type: data_type,
    size: size && size[1]
  }
}
%}

DECIMAL -> D E C I M A L

data_type ->
    B I N A R Y  ("(" int  ")" | null ) {% d => dataType('binary', d[6]) %}
  | C H A R  ("(" int  ")" | null ) {% d => dataType('char', d[4]) %}
  | D A T E {% d => dataType('date') %}
  | DECIMAL {% d => dataType('decimal') %}
  | DECIMAL "(" (__|null) int (__|null) ")" {% d => dataType('decimal', [0,d[3]]) %}
  | DECIMAL "(" (__|null) int (__|null) "," (__|null) int  ")" {% d => ({
      type: 'data_type',
      data_type: 'decimal',
      size1: d[3],
      size2: d[7]
    }) %}
  | F L O A T {% d => dataType('float') %}
  | N C H A R {% d => dataType('nchar') %}
  | S I G N E D {% d => dataType('signed') %}
  | T I M E {% d => dataType('time') %}
  | U N S I G N E D {% d => dataType('unsigned') %}


date_unit ->
  date_unit_internal {% d => ({type: 'date_unit', date_unit: d[0].join('')}) %}

date_unit_internal ->
    M I C R O S E C O N D
  | S E C O N D
  | M I N U T E
  | H O U R
  | D A Y
  | W E E K
  | M O N T H
  | Q U A R T E R
  | Y E A R
  | S E C O N D "_" M I C R O S E C O N D
  | M I N U T E "_" M I C R O S E C O N D
  | M I N U T E "_" S E C O N D
  | H O U R "_" M I C R O S E C O N D
  | H O U R "_" S E C O N D
  | H O U R "_" M I N U T E
  | D A Y "_" M I C R O S E C O N D
  | D A Y "_" S E C O N D
  | D A Y "_" M I N U T E
  | D A Y "_" H O U R
  | Y E A R "_" M O N T H

function_call ->
    function_identifier _ "(" _ "*" _ ")" {% d => ({
      type:'function_call',
      name: d[0],
      select_all: true
    }) %}
  | function_identifier _ "(" _ DISTINCT __ column _ ")" {% d => ({
      type: 'function_call',
      name: d[0],
      distinct: true,
      parameters: [d[6]]
    })%}
  | function_identifier _ "(" _ ALL post_expr _ ")" {% d => ({
      type: 'function_call',
      name: d[0],
      all: true,
      parameters: [d[5]]
    })%}
  | function_identifier _ "()" {% d => ({
      type: 'function_call',
      name: d[0],
      parameters: []
    })%}
  | function_identifier _ "(" _ expr_comma_list _ ")" {% d => ({
      type: 'function_call',
      name: d[0],
      parameters: (d[4].exprs)
    })%}

string ->
    dqstring {% d => ({type: 'string', string: d[0]}) %}
  | sqstring {% d => ({type: 'string', string: d[0]}) %}

column ->
    identifier {% d => ({type: 'column', name: d[0].value}) %}
  | identifier __ AS __ identifier {% d => ({type: 'column', name: d[0].value, alias: d[2].value}) %}

identifier ->
    btstring {% d => ({type: 'identifier', value:d[0]}) %}
  | "[" ([^\]] | "\\]"):+ "]" {% d => ({type: 'identifier', value: d[1].map(x => x[0]).join('')}) %}
  | [a-zA-Z_] [a-zA-Z0-9_]:* {% (d,l,reject) => {
    const value = d[0] + d[1].join('');
    if(reserved.indexOf(value.toUpperCase()) != -1) return reject;
    return {type: 'identifier', value: value};
  } %}

function_identifier ->
    btstring {% d => ({value:d[0]}) %}
  | [a-zA-Z_] [a-zA-Z0-9_]:* {% (d,l,reject) => {
    const value = d[0] + d[1].join('');
    if(reserved.indexOf(value.toUpperCase()) != -1 && valid_function_identifiers.indexOf(value.toUpperCase()) == -1) return reject;
    return {value: value};
  } %}

### Copied & modified from builtin

dqstring -> "\"" dstrchar:* "\"" {% function(d) {return d[1].join(""); } %}
sqstring -> "'"  sstrchar:* "'"  {% function(d) {return d[1].join(""); } %}
btstring -> "`"  [^`]:*    "`"  {% function(d) {return d[1].join(""); } %}

dstrchar -> [^\\"\n] {% id %}
    | "\\" strescape {%
      function(d) {
        return JSON.parse("\""+d.join("")+"\"");
      }
      %}

sstrchar -> [^\\'\n] {% id %}
    | "\\" strescape {%
      function(d) {
        return JSON.parse("\""+d.join("")+"\"");
      } %}
    | "\\'"
        {% function(d) {return "'"; } %}

strescape -> ["\\/bfnrt] {% id %}
    | "u" [a-fA-F0-9] [a-fA-F0-9] [a-fA-F0-9] [a-fA-F0-9] {%
    function(d) {
        return d.join("");
    }
%}

### Keywords

ROLLUP -> R O L L U P
WITH -> W I T H

AND -> [Aa] [Nn] [Dd]
ANY -> [Aa] [Nn] [Yy]
ALL -> [Aa] [Ll] [Ll]
AS -> [Aa] [Ss]
ASC -> [Aa] [Ss] [Cc]

BETWEEN -> [Bb] [Ee] [Tt] [Ww] [Ee] [Ee] [Nn]
BY -> [Bb] [Yy]

CASE -> [Cc] [Aa] [Ss] [Ee]
CAST -> [Cc] [Aa] [Ss] [Tt]
CONVERT -> [Cc] [Oo] [Nn] [Vv] [Ee] [Rr] [Tt]
CREATE -> [Cc] [Rr] [Ee] [Aa] [Tt] [Ee]

DESC -> [Dd] [Ee] [Ss] [Cc]
DISTINCT -> [Dd] [Ii] [Ss] [Tt] [Ii] [Nn] [Cc] [Tt]
DIV -> [Dd] [Ii] [Vv]

ELSE -> [Ee] [Ll] [Ss] [Ee]
END -> [Ee] [Nn] [Dd]
EXISTS -> [Ee] [Xx] [Ii] [Ss] [Tt] [Ss]

FALSE -> [Ff] [Aa] [Ll] [Ss] [Ee]
FROM -> [Ff] [Rr] [Oo] [Mm]

GROUP -> [Gg] [Rr] [Oo] [Uu] [Pp]

HAVING -> [Hh] [Aa] [Vv] [Ii] [Nn] [Gg]

IF -> [Ii] [Ff]
IN -> [Ii] [Nn]
INNER -> [Ii] [Nn] [Nn] [Ee] [Rr] {% d => 'inner' %}
INTERVAL -> [Ii] [Nn] [Tt] [Ee] [Rr] [Vv] [Aa] [Ll]
IS -> [Ii] [Ss]

JOIN -> [Jj] [Oo] [Ii] [Nn]

LEFT -> [Ll] [Ee] [Ff] [Tt] {% d => 'left' %}
LIKE -> [Ll] [Ii] [Kk] [Ee]
LIMIT -> L I M I T

MOD -> [Mm] [Oo] [Dd]

NOT -> [Nn] [Oo] [Tt]
NULLX -> [Nn] [Uu] [Ll] [Ll] [Xx]
  | [Nn] [Uu] [Ll] [Ll]

ON -> [Oo] [Nn]
OR -> [Oo] [Rr]
ORDER -> [Oo] [Rr] [Dd] [Ee] [Rr]

REPLACE -> [Rr] [Ee] [Pp] [Ll] [Aa] [Cc] [Ee]
RIGHT -> [Rr] [Ii] [Gg] [Hh] [Tt] {% d => 'right' %}

SELECT -> [Ss] [Ee] [Ll] [Ee] [Cc] [Tt]
SOME -> [Ss] [Oo] [Mm] [Ee]

THEN -> [Tt] [Hh] [Ee] [Nn]
TOP -> T O P
TRUE -> [Tt] [Rr] [Uu] [Ee]

UNION -> [Uu] [Nn] [Ii] [Oo] [Nn]
UNKNOWN -> [Uu] [Kk] [Oo] [Ww] [Nn]
USING -> [Uu] [Ss] [Ii] [Nn] [Gg]

VIEW -> [Vv] [Ii] [Ee] [Ww]

WHEN -> [Ww] [Hh] [Ee] [Nn]
WHERE -> [Ww] [Hh] [Ee] [Rr] [Ee]

XOR -> [Xx] [Oo] [Rr]

A -> "A" | "a"
B -> "B" | "b"
C -> "C" | "c"
D -> "D" | "d"
E -> "E" | "e"
F -> "F" | "f"
G -> "G" | "g"
H -> "H" | "h"
I -> "I" | "i"
J -> "J" | "j"
K -> "K" | "k"
L -> "L" | "l"
M -> "M" | "m"
N -> "N" | "n"
O -> "O" | "o"
P -> "P" | "p"
Q -> "Q" | "q"
R -> "R" | "r"
S -> "S" | "s"
T -> "T" | "t"
U -> "U" | "u"
V -> "V" | "v"
W -> "W" | "w"
X -> "X" | "x"
Y -> "Y" | "y"
Z -> "Z" | "z"

# Replacing whitespace.ne - need to in order to support comments
# Whitespace: `_` is optional, `__` is mandatory.
_  ->
		wschar:* {% function(d) {return null;} %}
	| wschar:* comment {% function(d) {return null;} %}
__ ->
		wschar:+ {% function(d) {return null;} %}
	| wschar:+ comment {% function(d) {return null;} %}

comment ->
	("#" | "--" wschar) [^\n]:+ ([\n]) {% x => null %}

wschar -> [ \t\n\v\f] {% id %}
