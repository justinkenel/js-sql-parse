# JS SQL Parse

## Status
Currently a work in progress: The end goal is to be able to parse and analyze
general sql queries.

## Dependencies
JS SQL Parse uses [Nearley](http://nearley.js.org/) to parse strings. The grammar
is defined in [sql.ne](./sql.ne)

## Tests
Run tests using `npm run test`

## Use
The test files in `./tests` are the best place to see examples of use. A basic example is:

```
const parser = require('js-sql-parser');
const result = parser.parse('select * from test_table');
```

The result of the `parse` method will have the following fields:

- **referencedTables**: a list of tables used in the query
- **createdTables**: a list of tables created in the query
- **sourceTables**: a list of tables sourced in subqueries and joins
- **operation**: the operation defined in the query - currently only `select` and `create_view` are supported
- **parsed**: the resulting parse tree
- **joins**: a list of joins within the query, and the columns used
