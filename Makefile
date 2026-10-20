.PHONY: app build check checks clean dmg docs-check docs-impact icon open release run

build:
	swift build

release:
	swift build -c release

run:
	swift run SpaceInvadersArcade

checks:
	swift run SpaceInvadersChecks

check:
	./scripts/check.sh

docs-check:
	python3 scripts/check_docs.py

docs-impact:
	python3 scripts/check_docs.py --changed

app:
	./scripts/build_app.sh

open: app
	open "dist/SPACE INVADERS.app"

dmg: app
	hdiutil create -volname "SPACE INVADERS" -srcfolder "dist/SPACE INVADERS.app" -ov -format UDZO "dist/SPACE-INVADERS-1.0.dmg"

icon:
	python3 scripts/make_icon.py

clean:
	swift package clean
	rm -rf dist
