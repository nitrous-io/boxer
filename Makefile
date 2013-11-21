test:
	sudo -E NODE_ENV=test node_modules/.bin/mocha test/**/*_spec.*

unit_test:
	sudo -E NODE_ENV=test node_modules/.bin/mocha test/lib/*_spec.*

.PHONY: test

