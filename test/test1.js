const assert = require('assert');

const tests = [
  {
    sql: 'select * from test',
    expected: {
      referencedTables: ['test'],
      operation: 'select',
    }
  },
  {
    sql: 'create or replace view test as select * from x',
    expected: {
      referencedTables: ['test', 'x'],
      operation: 'create_view',
      createdTables: ['test'],
      sourceTables: ['x']
    }
  },
  {
    sql: 'create or replace view test as select * from x left join y on x.a=y.a',
    expected: {
      referencedTables: ['test', 'x', 'y'],
      operation: 'create_view',
      createdTables: ['test'],
      sourceTables: ['x', 'y']
    }
  },
  {
    sql: 'select case when x=1 then "hello" else "bye" end',
    expected: {
      referencedTables: []
    }
  },
  {
    sql: 'select case when x=1 then "x" when x=2 then "y" end'
  },
  {
    sql: 'select case when (x=1) then "x" when x = 2 then "y" end'
  },
  {
    sql: 'select case when true then case when true then 1 end end as `v` from `test_table`'
  },
  {
    sql: 'select x, sum(1) AS `count` from y left join x on (a.foo=b.foo)'
  },
  {
    sql: 'select x from ((test))',
    expected:  {
      referencedTables: ['test']
    }
  },
  {
    sql: 'select x and y and z from l'
  },
  {
    sql: 'select x + y + z from l'
  },
  {
    sql: "select replace(substr('test',10), 'a', '') AS `testing`"
  },
  {
    sql: "select sum(if(`this`.`name`=`mapping`, 0, 1))"
  },
  {
    sql: 'select (select * from x) as x'
  },
  {
    sql: 'select (x is not null) as y'
  },
  {
    sql: 'select cast(x as date)'
  },
  {
    sql: 'select length(x)>0 and a.b is not null'
  }
];

const parser = require('../parser');

describe('parse', function() {
  tests.map(t => {
    describe(t.sql.slice(0,100), function() {
      try {
        const parsed = parser.parse(t.sql);
        it('parse', function() { });

        for(let e in t.expected) {
          it(e + " = " + JSON.stringify(t.expected[e]), function() {
            assert.deepEqual(t.expected[e], parsed[e]);
          });
        }
      } catch(e) {
        it('parse', function() { assert.fail(e); });
      }
    });
  })
});
