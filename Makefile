.SUFFIXES:

.PHONY: all lint test test-ci clean

all: lint test

test: # runs all the test files.
	@nvim --version | head -n 1 && echo ''
	@nvim --headless --noplugin -u ./scripts/minimal_init.lua \
		-c "lua require('mini.test').setup()" \
		-c "lua MiniTest.run({ execute = { reporter = MiniTest.gen_reporter.stdout({ group_depth = 2 }) } })"

deps: # installs `mini.nvim`, used for both the tests and documentation.
	@git clone --depth 1 https://github.com/echasnovski/mini.nvim deps/mini.nvim

test-ci: deps test # installs deps before running tests, useful for the CI.

lint: # performs a lint check and fixes issue if possible, following the config in `stylua.toml`.
	@stylua . --check -g '*.lua' -g '!deps/'

clean: # cleans the `deps/` folder
	@rm -rf deps
