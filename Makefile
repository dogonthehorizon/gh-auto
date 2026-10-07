.PHONY: build app run once publish uninstall clean

build:
	swift build -c release

# Dev bundle in the repo; `make publish` is what installs it for real.
app:
	scripts/bundle.sh .

run: app
	pkill -x gh-auto || true
	open gh-auto.app

once: build
	.build/release/GhAuto --once

publish:
	scripts/publish.sh

uninstall:
	pkill -x gh-auto || true
	rm -rf $(HOME)/Applications/gh-auto.app

clean:
	rm -rf .build gh-auto.app
