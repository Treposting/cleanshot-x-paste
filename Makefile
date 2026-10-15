.PHONY: build app run install dmg clean

build:
	swift build

app:
	./scripts/build-app.sh

run: app
	open build/Marquee.app

install: app
	rm -rf /Applications/Marquee.app
	cp -R build/Marquee.app /Applications/
	open /Applications/Marquee.app

dmg:
	./scripts/make-dmg.sh

clean:
	rm -rf .build build
