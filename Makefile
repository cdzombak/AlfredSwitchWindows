SHELL:=/usr/bin/env bash
VERSION:=$(shell ./.version.sh)

# Xcode build settings
XCODE_PROJECT:=EnumWindows.xcodeproj
XCODE_SCHEME:=EnumWindows
XCODE_CONFIG:=Release

default: help
.PHONY: help  # via https://marmelab.com/blog/2016/02/29/auto-documented-makefile.html
help: ## Print help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

.PHONY: all
all: clean build package ## Clean, build, and package

.PHONY: clean
clean: ## Remove all build outputs
	rm -rf .pkg
	rm -rf out
	rm -rf build

.PHONY: build
build: ## Build the EnumWindows universal binary
	mkdir -p out
	# Build for arm64
	xcodebuild -project $(XCODE_PROJECT) \
		-scheme $(XCODE_SCHEME) \
		-configuration $(XCODE_CONFIG) \
		-arch arm64 \
		-derivedDataPath ./build/arm64 \
		ONLY_ACTIVE_ARCH=NO \
		BUILD_DIR=./build/arm64 \
		clean build
	# Build for x86_64
	xcodebuild -project $(XCODE_PROJECT) \
		-scheme $(XCODE_SCHEME) \
		-configuration $(XCODE_CONFIG) \
		-arch x86_64 \
		-derivedDataPath ./build/x86_64 \
		ONLY_ACTIVE_ARCH=NO \
		BUILD_DIR=./build/x86_64 \
		clean build
	# Create universal binary
	lipo -create \
		./build/arm64/Release/EnumWindows \
		./build/x86_64/Release/EnumWindows \
		-output ./out/EnumWindows
	# Verify universal binary
	lipo -info ./out/EnumWindows

.PHONY: package
package: ## Package the workflow for distribution
	rm -rf ./.pkg
	mkdir -p ./.pkg
	# Copy binary
	cp -v ./out/EnumWindows ./.pkg/EnumWindows
	chmod +x ./.pkg/EnumWindows
	# Copy workflow resources
	cp -v ./AlfredWorkflow/info.plist ./.pkg/info.plist
	cp -v ./AlfredWorkflow/icon.png ./.pkg/icon.png
	cp -v ./AlfredWorkflow/switch.png ./.pkg/switch.png
	# Update version in info.plist
	/usr/libexec/PlistBuddy -c "Set :version $(VERSION)" ./.pkg/info.plist
	# Create .alfredworkflow (zip archive)
	mkdir -p ./out
	cd ./.pkg && zip -r workflow.zip * && mv -v workflow.zip "../out/AlfredSwitchWindows-$(VERSION).alfredworkflow"

.PHONY: lint
lint: ## Lint all source files in this repository (requires nektos/act: https://nektosact.com)
	act --artifact-server-path /tmp/artifacts -j lint

.PHONY: update-lint
update-lint: ## Pull updated images supporting the lint target (may fetch >10 GB!)
	docker pull catthehacker/ubuntu:full-latest
