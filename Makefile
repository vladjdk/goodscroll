CLT_FW := /Library/Developer/CommandLineTools/Library/Developer/Frameworks
CLT_LIB := /Library/Developer/CommandLineTools/Library/Developer/usr/lib
# Command Line Tools ship swift-testing outside the default search path; Xcode doesn't need this.
TEST_FLAGS := $(if $(wildcard $(CLT_FW)/Testing.framework),-Xswiftc -F$(CLT_FW) -Xlinker -F$(CLT_FW) -Xlinker -rpath -Xlinker $(CLT_FW) -Xlinker -rpath -Xlinker $(CLT_LIB))

.PHONY: build test app install run clean

build:
	swift build

test:
	swift test $(TEST_FLAGS)

app:
	scripts/build-app.sh $(VERSION)

install: app
	-osascript -e 'quit app "GoodScroll"' 2>/dev/null
	rm -rf /Applications/GoodScroll.app
	cp -R build/GoodScroll.app /Applications/
	open /Applications/GoodScroll.app

run: build
	.build/debug/GoodScroll

clean:
	rm -rf .build build
