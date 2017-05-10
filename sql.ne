

@builtin "whitespace.ne"
@builtin "number.ne"
@builtin "string.ne"

@{%
  function drill(o) {
    if(o && o.length==1 && o[0]) return drill(o[0]);
    return o;
  }

  const keywords=['HAVING', 'WHERE', 'GROUP', 'BY', 'VIEW', 'CREATE', 'OR',
    'REPLACE', 'ALL', 'DISTINCT', 'IF', 'CASE', 'WHEN', 'THEN', 'ELSE',
    'END', 'OR', 'NOT', 'IS', 'IN', 'ANY', 'SOME', 'EXISTS', 'NULLX',
    'BETWEEN', 'SELECT', 'FROM', 'AS', 'AND', 'LIKE', 'RIGHT', 'LEFT', 'INNER',
    'JOIN', 'ON', 'UNION' ];
%}

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

query_spec ->
    "(" _ query_spec _ ")" {% d => d[2] %}
  | SELECT (__ all_distinct __ | __) selection  {%
      d => ({
        type: 'select',
        all_distinct: d[2],
        selection: d[3]
      })
    %}
  | SELECT (__ all_distinct __ | __) selection __ table_exp {%
      d => ({
        type: 'select',
        all_distinct: d[1],
        selection: d[2],
        table_exp: d[4]
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
		from_clause (__ where_clause | null) (__ group_by_clause | null) (__ having_clause | null) (__ order_clause | null) {%
      d => ({
        type: 'from_table',
        from: drill(d[0]),
        where: (d[1] || [])[1],
        groupby: (d[2] || [])[1],
        having: (d[3] || [])[1],
        order: (d[4] || [])[1]
      })
    %}

all_distinct ->
    ALL
	|	DISTINCT

from_clause ->
		FROM __ table_ref_commalist {% d => d[2] %}
  | FROM __ "(" _ table_ref_commalist _ ")" {% d => d[4] %}
  | FROM __ subquery {% d => d[2] %}

group_by_clause ->
    GROUP __ BY __ selection_column_comma_list {%
      d => ({
        type: 'group_by',
        columns: d[4]
      })
    %}

selection ->
	  "*" {% d => ({type:'select_all'}) %}
	| selection_column_comma_list {% d => d[0] %}

selection_column_comma_list ->
    selection_column {% d => ({columns: [d[0]]}) %}
  | selection_column_comma_list _ "," _ selection_column {%
      d => ({
        columns: (d[0].columns||[]).concat([d[4]])
      })
    %}

selection_column ->
    scalar_exp {% d => ({type: 'column', expression: drill(d[0])}) %}
  | scalar_exp __ AS __ name {% d => ({type: 'column', expression: drill(d[0]), alias: d[4]}) %}

table_ref_commalist ->
		table_ref
	|	table_ref_commalist _ "," _ table_ref

table_ref ->
		table
	|	table __ range_variable
  | table_ref (__ LEFT __ | __ RIGHT __ | __ INNER __ | __) JOIN __ table __ ON __ predicate {%
      d => ({
        type: 'join',
        side: ((d[1]||[])[1]),
        left: d[0],
        right: d[4],
        on: d[8]
      })
    %}

table ->
		name {% d => ({type: 'table', table: d[0].value}) %}
	|	name "." name {% d => ({type: 'table', table: d[0].value +'.'+ d[2].value }) %}
  | name ( __ AS __ | __) name {% d => ({type: 'table', table: d[0].value, alias: d[2].value}) %}

where_clause ->
	  WHERE __ search_condition {% d => ({type:'where', condition: d[2]}) %}

having_clause ->
    HAVING __ search_condition {% d => ({type: 'having', condition: d[2]}) %}

order_clause ->
    ORDER __ BY __ order_statement_comma_list {% d => ({type: 'order', order: d[4].order}) %}

order_statement_comma_list ->
    order_statement {% d => ({order: d[0]}) %}
  | order_statement_comma_list _ "," _ order_statement {%
      d => ({order: (d[0].order||[]).concat(d[4])})
    %}

order_statement ->
    scalar_exp
  | scalar_exp __ ASC
  | scalar_exp __ DESC

search_condition ->
	  search_condition __ OR __ search_condition
	|	search_condition __ AND __ search_condition
	|	NOT __ search_condition
	|	"(" _ search_condition _ ")"
	|	predicate

predicate ->
		comparison_predicate
	|	between_predicate
	|	like_predicate
	|	test_for_null
	|	in_predicate
	|	all_or_any_predicate
	|	existence_test
  | atom

comparison_predicate ->
		scalar_exp _ comparison _ scalar_exp {% d => ({type:'comparison_predicate', left: d[0], right: d[4], operator: d[2].type}) %}
	|	scalar_exp _ comparison _ subquery

between_predicate ->
		scalar_exp __ NOT __ BETWEEN __ scalar_exp __ AND __ scalar_exp
	|	scalar_exp __ BETWEEN __ scalar_exp __ AND __ scalar_exp

like_predicate ->
		scalar_exp __ NOT __ LIKE __ atom
	|	scalar_exp __ LIKE __ atom

test_for_null ->
		scalar_exp __ IS __ NOT __ NULLX
	|	scalar_exp __ IS __ NULLX

in_predicate ->
		scalar_exp __ NOT __ IN _ "(" _ subquery _ ")"
	|	scalar_exp __ IN _ "(" _ subquery _ ")"
	|	scalar_exp NOT __ IN _ "(" _ atom_commalist _ ")"
	|	scalar_exp __ IN __ "(" atom_commalist ")"

atom_commalist ->
		atom
	|	atom_commalist _ "," _ atom

all_or_any_predicate ->
		scalar_exp _ comparison _ any_all_some __ subquery

comparison ->
    comparison_type {% d => ({type: "comparison", type: d[0][0]}) %}

comparison_type ->
    "="
  | "<>"
  | "<"
  | "<="
  | ">"
  | ">="
  | "+"
  | "!="

any_all_some ->
		ANY
	|	ALL
	|	SOME

existence_test ->
		EXISTS __ subquery

subquery ->
		"(" _ query_spec _ ")" {% d => d[2] %}

column_ref ->
    scalar_exp {% d => ({type: 'column', expression: d[0]}) %}
  | scalar_exp __ AS __ name {% d => ({type: 'column', expression: d[0], alias: d[4].value}) %}

scalar_exp ->
		scalar_exp _ "+" _ scalar_exp
	|	scalar_exp _ "-" _ scalar_exp
	|	scalar_exp _ "*" _ scalar_exp
  | scalar_exp _ "/" _ scalar_exp
	|	atom
	|	function_ref
	|	"(" scalar_exp ")"
  | if_statement
  | case_statement
  | interval_statement
  | cast_statement

interval_statement ->
    INTERVAL __ scalar_exp __ date_unit {%
      d => ({
        type: 'interval',
        value: d[2],
        unit: d[4]
      })
    %}

cast_statement ->
    CAST _ "(" _ scalar_exp __ AS __ data_type _ ")" {%
      d => ({
        type: 'cast',
        value: d[4],
        type: d[8]
      })
    %}

data_type ->
    "BINARY" ("[" int "]" | null)
  | "CHAR" ("[" int "]" | null)
  | "DATE"
  | "DECIMAL" ("[" int "]" | null)
  | "NCHAR"
  | "SIGNED"
  | "TIME"
  | "UNSIGNED"

date_unit ->
    "MICROSECOND" | "SECOND" | "MINUTE" | "HOUR" | "DAY" | "WEEK" | "MONTH" | "QUARTER" | "YEAR" |
    "SECOND_MICROSECOND" | "MINUTE_MICROSECOND" | "MINUTE_SECOND" | "HOUR_MICROSECOND" |
    "HOUR_SECOND" | "HOUR_MINUTE" | "DAY_MICROSECOND" | "DAY_SECOND" | "DAY_MINUTE" |
    "DAY_HOUR" | "YEAR_MONTH"

if_statement ->
    IF _ "(" _ scalar_exp _ "," _ scalar_exp _ ("," scalar_exp _ | _) ")" {%
      d => ({
        type: 'if',
        condition: d[4],
        then: d[8],
        'else': (d[10]||[])[1]
      })
    %}

case_statement ->
    CASE __ when_statement_list (__ ELSE __ scalar_exp __ | __) END {%
      d => ({
        type: 'case',
        when_statements: d[2],
        'else': (d[3]||[])[3]
      })
    %}

when_statement_list ->
    when_statement {% d => ({statements: [d[0]]}) %}
  | when_statement_list __ when_statement {% d => ({
      columns: (d[0].statements||[]).concat([d[2]])
    })
  %}

when_statement ->
    WHEN __ predicate __ THEN __ scalar_exp {%
      d => ({
        type: 'when',
        condition: d[2],
        then: d[6]
      })
    %}

atom ->
    variable
	| literal

variable ->
    name {% d => ({type: 'variable', value: d[0]}) %}
  | name "." name {% d => ({type: 'variable', value: d[1], parent: d[0]}) %}

function_ref ->
		name _ "(" _ "*" _ ")"
	|	name _ "(" _ "DISTINCT" __ column _ ")"
	|	name _ "(" _ "ALL" __ scalar_exp _ ")"
	|	name _ "(" _ scalar_exp_comma_list _ ")" {%
    d => ({
      type: 'function',
      name: d[0],
      parameters: (d[4].expressions||[]).map(drill)
    })
  %}

scalar_exp_comma_list ->
    scalar_exp {% d => ({expressions: [d[0]]}) %}
  | scalar_exp_comma_list _ "," _ scalar_exp {%
      d => ({
        expressions: (d[0].expressions||[]).concat([d[4]])
      })
    %}

string ->
    dqstring {% d => ({type: 'string', string: d[0]}) %}
  | sqstring {% d => ({type: 'string', string: d[0]}) %}

literal ->
		string
	|	INTNUM

INTNUM ->
    decimal {% d => ({type: 'decimal', value: d[0]}) %}

column ->
    name {% d => ({type: 'column', name: d[0].value}) %}
  | name __ AS __ name {% d => ({type: 'column', name: d[0].value, alias: d[2].value}) %}

parameter -> name

range_variable ->	name

user ->	name

name ->
    btstring {% d => ({ type: 'name', value: d[0] }) %}
  | "[" [^\]]:* "]" {% d => ({ type: 'name', value: d[1].join('') }) %}
  | [a-z] [a-zA-Z0-9_]:* {% (d,l,reject) => {
    const value = d[0] + d[1].join('');
    // ensure that the name is not a keyword
    if(keywords.indexOf(value.toUpperCase()) != -1) return reject;
    return {type: 'name', value: value};
  } %}

CAST -> [Cc] [Aa] [Ss] [Tt]
CONVERT -> [Cc] [Oo] [Nn] [Vv] [Ee] [Rr] [Tt]
USING -> [Uu] [Ss] [Ii] [Nn] [Gg]

INTERVAL -> [Ii] [Nn] [Tt] [Ee] [Rr] [Vv] [Aa] [Ll]

LEFT -> [Ll] [Ee] [Ff] [Tt] {% d => 'left' %}
RIGHT -> [Rr] [Ii] [Gg] [Hh] [Tt] {% d => 'right' %}
INNER -> [Ii] [Nn] [Nn] [Ee] [Rr] {% d => 'inner' %}
JOIN -> [Jj] [Oo] [Ii] [Nn]
ON -> [Oo] [Nn]
UNION -> [Uu] [Nn] [Ii] [Oo] [Nn]

HAVING -> [Hh] [Aa] [Vv] [Ii] [Nn] [Gg]

WHERE -> [Ww] [Hh] [Ee] [Rr] [Ee]

ASC -> [Aa] [Ss] [Cc]
DESC -> [Dd] [Ee] [Ss] [Cc]

ORDER -> [Oo] [Rr] [Dd] [Ee] [Rr]
GROUP -> [Gg] [Rr] [Oo] [Uu] [Pp]
BY -> [Bb] [Yy]

VIEW -> [Vv] [Ii] [Ee] [Ww]
CREATE -> [Cc] [Rr] [Ee] [Aa] [Tt] [Ee]

REPLACE -> [Rr] [Ee] [Pp] [Ll] [Aa] [Cc] [Ee]

ALL -> [Aa] [Ll] [Ll]
DISTINCT -> [Dd] [Ii] [Ss] [Tt] [Ii] [Nn] [Cc] [Tt]

IF -> [Ii] [Ff]
CASE -> [Cc] [Aa] [Ss] [Ee]
WHEN -> [Ww] [Hh] [Ee] [Nn]
THEN -> [Tt] [Hh] [Ee] [Nn]
ELSE -> [Ee] [Ll] [Ss] [Ee]
END -> [Ee] [Nn] [Dd]

OR -> [Oo] [Rr]
NOT -> [Nn] [Oo] [Tt]
IS -> [Ii] [Ss]
IN -> [Ii] [Nn]

ANY -> [Aa] [Nn] [Yy]
SOME -> [Ss] [Oo] [Mm] [Ee]

EXISTS -> [Ee] [Xx] [Ii] [Ss] [Tt] [Ss]

NULLX -> [Nn] [Uu] [Ll] [Ll] [Xx]

BETWEEN -> [Bb] [Ee] [Tt] [Ww] [Ee] [Ee] [Nn]
SELECT -> [Ss] [Ee] [Ll] [Ee] [Cc] [Tt]
FROM -> [Ff] [Rr] [Oo] [Mm]
AS -> [Aa] [Ss]
AND -> [Aa] [Nn] [Dd]

LIKE -> [Ll] [Ii] [Kk] [Ee]
