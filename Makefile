test:
	NODE_ENV=test node_modules/.bin/mocha test/**/*_spec.*

unit_test:
	NODE_ENV=test node_modules/.bin/mocha test/lib/*_spec.*

.PHONY: test

