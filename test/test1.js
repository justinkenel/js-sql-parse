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
  }
];

const parser = require('../parser');

describe('parse', function() {
  tests.map(t => {
    describe(t.sql.slice(0,100), function() {
      const parsed = parser.parse(t.sql);

      for(let e in t.expected) {
        it(e + " = " + JSON.stringify(t.expected[e]), function() {
          assert.deepEqual(t.expected[e], parsed[e]);
        });
      }
    });
  })
});
