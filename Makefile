.PHONY: build app run install clean

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

clean:
	rm -rf .build build
