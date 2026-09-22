# Makefile — single commands that code agents MUST use.
# `make check` is the exit gate: it must pass before any commit.

LUA ?= lua5.1
BUSTED ?= busted
LUACHECK ?= luacheck
STYLUA ?= stylua
PYTHON ?= python3

.PHONY: check lint fmt fmt-check test toc cli inter plan clean

## Full gate (local CI). No excuse for committing if it fails.
check: fmt-check lint toc test

fmt:
	$(STYLUA) .

fmt-check:
	$(STYLUA) --check .

lint:
	$(LUACHECK) .

## Lua 5.1 syntax check == the WoW client runtime
syntax:
	@find . -name '*.lua' -not -path './libs/*' -not -path './.git/*' | while read -r f; do \
		$(LUA) -e "local c,e=loadfile('$$f'); if not c then io.stderr:write(e..'\n'); os.exit(1) end" || exit 1; \
		echo "OK $$f"; \
	done

## STEP 1: out-of-game unit tests (pairing logic + intermission)
test:
	$(BUSTED)

## STEP 2: .toc consistency (directives + listed files exist)
toc:
	$(PYTHON) tools/check_toc.py GideonRaid.toc

## STEP 4: pairing of a roster, runnable by GIDEON
cli:
	$(LUA) tools/pairing_cli.lua < tools/sample_roster.csv

## STEP 3: out-of-game preview of the Intermission Coach (convention + macros)
inter:
	$(LUA) tools/intermission_cli.lua all

## Pre-pull view of a player, from the reference assignment block
plan:
	$(LUA) tools/intermission_cli.lua plan Velna

clean:
	rm -rf .release
