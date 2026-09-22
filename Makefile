# Makefile — commandes uniques que les agents de code DOIVENT utiliser.
# `make check` est la porte de sortie : elle doit passer avant tout commit.

LUA ?= lua5.1
BUSTED ?= busted
LUACHECK ?= luacheck
STYLUA ?= stylua
PYTHON ?= python3

.PHONY: check lint fmt fmt-check test toc cli clean

## Porte complete (CI locale). Aucune excuse pour commiter si ca echoue.
check: fmt-check lint toc test

fmt:
	$(STYLUA) .

fmt-check:
	$(STYLUA) --check .

lint:
	$(LUACHECK) .

## Verification syntaxique Lua 5.1 == runtime du client WoW
syntax:
	@find . -name '*.lua' -not -path './libs/*' -not -path './.git/*' | while read -r f; do \
		$(LUA) -e "local c,e=loadfile('$$f'); if not c then io.stderr:write(e..'\n'); os.exit(1) end" || exit 1; \
		echo "OK $$f"; \
	done

## ETAPE 1 : tests unitaires hors jeu (logique d'appariement)
test:
	$(BUSTED)

## ETAPE 2 : coherence du .toc (directives + fichiers listes existent)
toc:
	$(PYTHON) tools/check_toc.py GideonRaid.toc

## ETAPE 4 : appariement d'un roster, executable par GIDEON
cli:
	$(LUA) tools/pairing_cli.lua < tools/sample_roster.csv

clean:
	rm -rf .release
