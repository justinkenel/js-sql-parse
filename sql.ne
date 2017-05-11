

@builtin "whitespace.ne"
@builtin "number.ne"

@{%
  function drill(o) {
    //if(o && o.length==1 && o[0]) return drill(o[0]);
    return o;
  }

  const reserved=require('./reserved.json');
  const valid_function_identifiers=['LEFT','RIGHT','REPLACE']
%}

main -> sql (_ ";" | null) {% d => d[0] %}

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
  | DISTINCT

from_clause ->
    FROM __ table_ref_commalist {% d => d[2] %}
  | FROM __ subquery {% d => d[2] %}

group_by_clause ->
    GROUP __ BY __ selection_column_comma_list {% d => ({ type: 'group_by', columns: d[4] }) %}
  | GROUP __ BY "(" _ selection_column_comma_list _ ")" {% d => ({ type: 'group_by', columns: d[6] }) %}

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
    expr {% d => ({type: 'column', expression: drill(d[0])}) %}
  | expr __ AS __ identifier {% d => ({type: 'column', expression: drill(d[0]), alias: d[4]}) %}

table_ref_commalist ->
    table_ref
  | table_ref_commalist _ "," _ table_ref

@{%
  function tableRef(d) {
    return {
      type: 'join',
      side: ((d[1]||[])[1]),
      left: d[0],
      right: d[4],
      on: d[8]
    };
  }
%}

table_ref ->
    "(" _ table_ref _ ")" {% d => d[2] %}
  | table
  | table_ref (__ LEFT __ | __ RIGHT __ | __ INNER __ | __) JOIN __ table __ ON __ expr {% tableRef %}
  | table_ref (__ LEFT __ | __ RIGHT __ | __ INNER __ | __) JOIN __ table __ ON ("(" _ expr _ ")") {% tableRef %}

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
    order_statement {% d => ({order: d[0]}) %}
  | order_statement_comma_list _ "," _ order_statement {%
      d => ({order: (d[0].order||[]).concat(d[4])})
    %}

order_statement ->
    expr
  | expr __ ASC
  | expr __ DESC

column_ref ->
    expr {% d => ({type: 'column', expression: d[0]}) %}
  | expr __ AS __ identifier {% d => ({type: 'column', expression: d[0], alias: d[4].value}) %}

# https://dev.mysql.com/doc/refman/5.7/en/expressions.html
expr ->
    pre_expr OR post_boolean_primary
  | pre_expr "||" post_boolean_primary
  | pre_expr XOR post_boolean_primary
  | pre_expr AND post_boolean_primary
  | pre_expr "&&" post_boolean_primary
  | NOT post_boolean_primary
  | "!" post_boolean_primary
  | pre_boolean_primary IS (__ NOT | null) __ (TRUE | FALSE | UNKNOWN)
  | boolean_primary

pre_expr ->
    expr __
  | "(" _ expr _ ")"

post_expr ->
    __ expr
  | "(" _ expr _ ")"

boolean_primary ->
    pre_boolean_primary IS (__ NOT | null) __ NULLX
  | boolean_primary "<=>" predicate
  | boolean_primary _ comparison_type _ predicate
  | boolean_primary _ comparison_type _ (ANY | ALL) subquery
  | predicate

pre_boolean_primary ->
    "(" _ boolean_primary _ ")"
  | boolean_primary __

post_boolean_primary ->
    "(" _ boolean_primary _ ")"
  | __ boolean_primary

comparison_type ->
    "="
  | "<>"
  | "<"
  | "<="
  | ">"
  | ">="
  | "!="

predicate ->
    in_predicate
  | between_predicate
  | like_predicate
  | bit_expr

in_predicate ->
    pre_bit_expr (NOT __ | null) IN _ subquery
  | pre_bit_expr (NOT __ | null) IN _ "(" _ expr_comma_list _ ")"

between_predicate ->
    pre_bit_expr (NOT __ | null) BETWEEN mid_bit_expr AND post_bit_expr

mid_bit_expr ->
    "(" _ bit_expr _ ")"
  | __ "(" _ bit_expr _ ")"
  | "(" _ bit_expr _ ")" __
  | __ bit_expr __

like_predicate ->
    pre_bit_expr (NOT __ | null) LIKE post_bit_expr

bit_expr ->
    bit_expr _ "|" _ simple_expr
  | bit_expr _ "&" _ simple_expr
  | bit_expr _ "<<" _ simple_expr
  | bit_expr _ ">>" _ simple_expr
  | bit_expr _ "+" _ simple_expr
  | bit_expr _ "-" _ simple_expr
  | bit_expr _ "*" _ simple_expr
  | bit_expr _ "/" _ simple_expr
  | pre_bit_expr DIV post_simple_expr
  | pre_bit_expr MOD post_simple_expr
  | bit_expr _ "%" _ simple_expr
  | bit_expr _ "^" _ simple_expr
  | bit_expr _ "+" _ interval_expr
  | bit_expr _ "-" _ interval_expr
  | simple_expr

pre_bit_expr ->
    bit_expr __
  | "(" _ bit_expr _ ")"

post_bit_expr ->
    __ bit_expr
  | "(" _ bit_expr _ ")"

simple_expr ->
    literal
  | identifier
  | function_call
  # | simple_expr COLLATE
  | "(" _ expr_comma_list _ ")"
  | subquery
  | EXISTS _ subquery
  | case_statement
  | if_statement
  | cast_statement
  | convert_statement
  | identifier "." identifier

post_simple_expr ->
    __ simple_expr
  | "(" _ simple_expr _ ")"

literal ->
    string
  | decimal
  | NULLX
  | TRUE
  | FALSE

expr_comma_list ->
    expr
  | expr_comma_list _ "," _ expr

if_statement ->
    IF _ "(" _ expr _ "," _ expr _ "," _ expr _ ")" {%
      d => ({
        type: 'if',
        condition: d[4],
        then: d[8],
        'else': (d[10]||[])[1]
      })
    %}

case_statement ->
    CASE __ when_statement_list (__ ELSE __ expr __ | __) END {%
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
        type: d[8]
      })
    %}

data_type ->
    B I N A R Y  ("[" int  "]" | null )
  | C H A R  ("[" int  "]" | null )
  | D A T E
  | D E C I M A L  ("[" int  "]" | null )
  | N C H A R
  | S I G N E D
  | T I M E
  | U N S I G N E D

date_unit ->
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
    function_identifier _ "(" _ "*" _ ")"
  | function_identifier _ "(" _ DISTINCT __ column _ ")"
  | function_identifier _ "(" _ ALL post_expr _ ")"
  | function_identifier _ "()"
  | function_identifier _ "(" _ expr_comma_list _ ")" {%
    d => ({
      type: 'function',
      name: d[0],
      parameters: (d[4].expressions||[]).map(drill)
    })
  %}

string ->
    dqstring {% d => ({type: 'string', string: d[0]}) %}
  | sqstring {% d => ({type: 'string', string: d[0]}) %}

column ->
    identifier {% d => ({type: 'column', name: d[0].value}) %}
  | identifier __ AS __ identifier {% d => ({type: 'column', name: d[0].value, alias: d[2].value}) %}

identifier ->
    btstring {% d => ({value:d[0]}) %}
  | [a-z] [a-zA-Z0-9_]:* {% (d,l,reject) => {
    const value = d[0] + d[1].join('');
    if(reserved.indexOf(value.toUpperCase()) != -1) return reject;
    return {value: value};
  } %}

function_identifier ->
    btstring {% d => ({value:d[0]}) %}
  | [a-z] [a-zA-Z0-9_]:* {% (d,l,reject) => {
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
