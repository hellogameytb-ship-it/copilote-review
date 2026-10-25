SHELL := /bin/bash

DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer
export DEVELOPER_DIR

PROJECT  = Copilote.xcodeproj
SCHEME   = Copilote
DERIVED  = build/DerivedData
APP      = build/Copilote.app

.PHONY: gen build test kit-test replay ask test-wav run clean index-tool index search renders notes install

gen:
	xcodegen generate --quiet

build: gen
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release \
		-derivedDataPath $(DERIVED) -destination 'platform=macOS,arch=arm64' build -quiet
	rm -rf $(APP)
	cp -R $(DERIVED)/Build/Products/Release/Copilote.app $(APP)
	@echo "→ $(APP)"

test: gen
	@Tools/check-overlay-windows.sh
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug \
		-derivedDataPath $(DERIVED) -destination 'platform=macOS,arch=arm64' test -quiet

run: build
	open $(APP)

# ~/Applications/Copilote.app, so Spotlight finds « Copilote »: quits the running copy, replaces it, opens it
# (NO_OPEN=1: replaces it without launching).
INSTALLED = $(HOME)/Applications/Copilote.app
install: build
	@osascript -e 'tell application id "org.example.copilote" to quit' >/dev/null 2>&1 || true
	@for i in 1 2 3 4 5 6 7 8 9 10; do pgrep -f "Copilote.app/Contents/MacOS/Copilote" >/dev/null || break; sleep 0.5; done
	@if pgrep -f "Copilote.app/Contents/MacOS/Copilote" >/dev/null; then echo "Copilote tourne encore : quitte-le (menu ⚙ → Quitter) puis relance make install."; exit 1; fi
	@mkdir -p $(HOME)/Applications
	@rm -rf "$(INSTALLED)"
	@cp -R $(APP) "$(INSTALLED)"
	@echo "→ $(INSTALLED)"
	@[ -n "$(NO_OPEN)" ] || open "$(INSTALLED)"

clean:
	rm -rf build $(PROJECT)

# TDD loop: framework + unit tests only (does not build or launch the app).
kit-test: gen
	@set -o pipefail; xcodebuild -project $(PROJECT) -scheme CopiloteKit -configuration Debug \
		-derivedDataPath $(DERIVED) -destination 'platform=macOS,arch=arm64' test 2>&1 \
		| grep -E "error:|Test Case.*(passed|failed)|XCTAssert|Executed .* tests?,|TEST (SUCCEEDED|FAILED)" | sort -u

# Listening chain on a recording (VAD → transcription → topics), no app needed.
# Topic decisions: PROVIDER=codex (ChatGPT subscription via the codex CLI), Claude Haiku if
# ANTHROPIC_API_KEY is set, keywords otherwise (or REPLAY_FLAGS=--offline).
FILE ?= fixtures/three-questions.wav
replay: gen
	@xcodebuild -project $(PROJECT) -scheme copilote-replay -configuration Debug \
		-derivedDataPath $(DERIVED) -destination 'platform=macOS,arch=arm64' build -quiet 2>&1 | grep -v "^$$" || true
	@$(DERIVED)/Build/Products/Debug/copilote-replay "$(FILE)" $(if $(PROVIDER),--provider $(PROVIDER)) \
		$(if $(BASE),--base "$(BASE)" --base-dir "$(DIR)") $(if $(TODAY),--today $(TODAY)) $(REPLAY_FLAGS)

# Personal base without the app. The demo base is fictional (fixtures/base-demo); its index goes
# to build/, never to the app's. Diagrams through PROVIDER (codex by default; none = skip).
DIR ?= fixtures/base-demo
INDEX_STORE ?= build/base-index/$(notdir $(DIR))
INDEX_TOOL = $(DERIVED)/Build/Products/Debug/copilote-index
index-tool: gen
	@xcodebuild -project $(PROJECT) -scheme copilote-index -configuration Debug \
		-derivedDataPath $(DERIVED) -destination 'platform=macOS,arch=arm64' build -quiet 2>&1 | grep -v "^$$" || true

index: index-tool
	@$(INDEX_TOOL) index "$(DIR)" --store "$(INDEX_STORE)" --web Copilote/Resources/web \
		$(if $(PROVIDER),--provider $(PROVIDER)) $(INDEX_FLAGS)

# make search Q="t'étais où cet été ?" [TODAY=2026-10-19] [MODE=show|suggest|off]
search: index-tool
	@$(INDEX_TOOL) search --store "$(INDEX_STORE)" $(if $(TODAY),--today $(TODAY)) $(if $(MODE),--mode $(MODE)) "$(Q)"

# Off-screen PNGs of the fiche cards (fictional demo base; run `make index` first).
renders: gen
	@xcodebuild -project $(PROJECT) -scheme copilote-render -configuration Debug \
		-derivedDataPath $(DERIVED) -destination 'platform=macOS,arch=arm64' build -quiet 2>&1 | grep -v "^$$" || true
	@$(DERIVED)/Build/Products/Debug/copilote-render "$(INDEX_STORE)" "$(DIR)" docs/renders

# End-of-meeting notes + follow-up email from a recording: make notes FILE=fixtures/reunion.wav
# [PROVIDER=codex|anthropic] [MODE=reunion|technique|potes|presentation] [REVIEW=1]
notes: gen
	@xcodebuild -project $(PROJECT) -scheme copilote-replay -configuration Debug \
		-derivedDataPath $(DERIVED) -destination 'platform=macOS,arch=arm64' build -quiet 2>&1 | grep -v "^$$" || true
	@$(DERIVED)/Build/Products/Debug/copilote-replay notes "$(or $(FILE),fixtures/reunion.wav)" --provider $(or $(PROVIDER),codex) \
		$(if $(MODE),--mode $(MODE)) $(if $(REVIEW),--review)

# Regenerates the synthetic fixtures (macOS French voice "Thomas").
test-wav:
	python3 scripts/make_test_wav.py three-questions
	python3 scripts/make_test_wav.py follow-up
	python3 scripts/make_test_wav.py perso
	python3 scripts/make_test_wav.py reunion
	python3 scripts/make_test_wav.py pression
	python3 scripts/make_test_wav.py trois-types

# Latency of one answer: make ask PROVIDER=codex [IMAGES="a.jpg b.jpg"] [REPEAT=3] Q="question"
ask: gen
	@xcodebuild -project $(PROJECT) -scheme copilote-replay -configuration Debug \
		-derivedDataPath $(DERIVED) -destination 'platform=macOS,arch=arm64' build -quiet 2>&1 | grep -v "^$$" || true
	@$(DERIVED)/Build/Products/Debug/copilote-replay ask $(if $(PROVIDER),--provider $(PROVIDER)) \
		$(foreach image,$(IMAGES),--image $(image)) --repeat $(or $(REPEAT),1) "$(Q)"
