# Convenience targets. Real work happens in the scripts and in `swift build` / `swift test`.
.PHONY: build test test-core test-app test-cli coverage app dmg release install clean

build:
	swift build

test:
	AIRDROP2X_NO_HELPER_RESET=1 swift test 2>&1 | grep -E 'error|Executed|Suite .*(passed|failed)'

test-core:
	AIRDROP2X_NO_HELPER_RESET=1 swift test --filter AirDrop2xCoreTests

test-app:
	AIRDROP2X_NO_HELPER_RESET=1 swift test --filter AirDrop2xAppTests

test-cli:
	AIRDROP2X_NO_HELPER_RESET=1 swift test --filter airdrop2xCLITests

coverage:
	AIRDROP2X_NO_HELPER_RESET=1 swift test --enable-code-coverage >/dev/null 2>&1 || true
	@xcrun llvm-cov report \
	  "$$(find .build -name airdrop2xPackageTests.xctest -type d | head -1)/Contents/MacOS/airdrop2xPackageTests" \
	  -instr-profile "$$(find .build -name default.profdata | head -1)" \
	  -ignore-filename-regex='Tests/|\.build/'

app:
	./build-app.sh

dmg:
	./make-dmg.sh

release:
	./release.sh

install: app
	pkill -x AirDrop2X || true
	rm -rf /Applications/AirDrop2X.app
	cp -R dist/AirDrop2X.app /Applications/
	open /Applications/AirDrop2X.app

clean:
	rm -rf .build dist
