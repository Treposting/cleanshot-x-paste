.PHONY: build app run install dmg clean

build:
	swift build

app:
	./scripts/build-app.sh

run: app
	open build/ShotPaste.app

install: app
	rm -rf /Applications/ShotPaste.app
	cp -R build/ShotPaste.app /Applications/
	open /Applications/ShotPaste.app

dmg:
	./scripts/make-dmg.sh

clean:
	rm -rf .build build
