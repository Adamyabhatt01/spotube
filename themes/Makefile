DART ?= fvm dart

# The theme plugins live in themes/<id>/; the toolchain compiles them, runs
# them, validates the payload they produce and packages them into dist/.
#
#   make build     compile, validate and package every theme
#   make check     validate only, write nothing (this is the CI gate)
#   make test      the contract's tests
#   make publish   refresh the golden payloads in conformance/
#
.PHONY: deps build check test conformance install clean

deps:
	$(DART) pub get

build: deps
	$(DART) run tools/build.dart

check: deps
	$(DART) run tools/build.dart --check

test: deps
	$(DART) test

conformance: deps
	$(DART) run tools/export.dart

install: deps
	$(DART) run tools/install.dart $(ARGS)

clean:
	rm -rf build .dart_tool
