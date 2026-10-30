# Release build with testing enabled: the bot and difficulty tests run whole
# games and are ~20x slower in debug.
test:
	swift test -c release -Xswiftc -enable-testing

cli:
	swift build -c release --product skee

balance: cli
	.build/release/skee balance --runs 100

.PHONY: test cli balance
