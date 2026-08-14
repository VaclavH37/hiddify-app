# .ONESHELL:
include dependencies.properties

# --- Shell guard (Windows) ---
# GNU make defaults SHELL to an unqualified `sh.exe`. Launched from cmd.exe or
# PowerShell — where Git's sh is not on PATH — make silently falls back to
# cmd.exe, and the first POSIX recipe dies with the useless
# `! was unexpected at this time`. Most recipes here are POSIX (`if [ ! -f ]`,
# `ls`, `unzip`, `tar`, `$$VAR`), so fail immediately with a message that says
# what to do. WSL leaves OS unset, so core builds are unaffected.
# The probe is `echo $$0`: a POSIX shell expands it to its own name (sh/bash),
# cmd.exe has no such variable and echoes the literal `$0` — and does so without
# printing an "unrecognized command" error, so the guard stays quiet.
ifeq ($(OS),Windows_NT)
ifeq (,$(findstring sh,$(shell echo $$0)))
$(error Run make from Git Bash (MINGW64) — cmd.exe/PowerShell have no POSIX shell, which these recipes require. Native core builds run in WSL; see CORE_BUILD.md)
endif
endif

# --- Log Colors ---
blue   := \033[1;34m
green  := \033[1;92m
yellow := \033[1;33m
reset  := \033[0m
# --- Log helpers ---
# Usage: $(BLUE) <text> $(DONE)
BLUE   := echo -e "$(blue)
GREEN  := echo -e "$(green)
YELLOW := echo -e "$(yellow)
DONE := $(reset)"

MKDIR := mkdir -p
RM  := rm -rf
SEP :=/

ifeq ($(OS),Windows_NT)
    ifeq ($(IS_GITHUB_ACTIONS),)
		# MKDIR := -mkdir
		RM := rmdir /s /q
		# SEP:=\\
	endif
endif


# Define sed command based on the OS
ifeq ($(OS),Windows_NT)
    # Windows (Assume Git Bash or similar sed is available, or standard syntax)
    SED := sed -i
else
	ifeq ($(shell uname),Darwin) # macOS
    	SED :=sed -i ''
	else # Linux
    	SED :=sed -i
	endif
endif

# fastforge ships only as fastforge.bat on Windows (dart pub global activate
# does not generate a no-extension wrapper), and GNU make on Windows uses
# CreateProcess for simple recipes which won't auto-resolve PATHEXT. Call the
# .bat explicitly on Windows; fall back to the bare name elsewhere.
ifeq ($(OS),Windows_NT)
    FASTFORGE := fastforge.bat
else
    FASTFORGE := fastforge
endif

# Override fastforge's pubspec-name default ("hiddify") for the rebrand. The
# Dart package name in pubspec.yaml stays "hiddify" so package: imports keep
# working; only the artifact filename changes. Mustache template — see
# flutter_app_packager/lib/src/api/make_config.dart for available variables.
FF_ARTIFACT_NAME := RaynVPN-{{build_name}}+{{build_number}}-{{platform}}.{{ext}}


BINDIR=hiddify-core$(SEP)bin
ANDROID_OUT=android$(SEP)app$(SEP)libs
IOS_OUT=ios$(SEP)Frameworks
DESKTOP_OUT=hiddify-core$(SEP)bin
GEO_ASSETS_DIR=assets$(SEP)core

CORE_PRODUCT_NAME=hiddify-core
CORE_NAME=hiddify-lib
LIB_NAME=hiddify-core

ifeq ($(CHANNEL),prod)
	CORE_URL=https://github.com/hiddify/hiddify-next-core/releases/download/v$(core.version)
else
	CORE_URL=https://github.com/hiddify/hiddify-next-core/releases/download/draft
endif

ifeq ($(CHANNEL),prod)
	TARGET=lib/main_prod.dart
else
	TARGET=lib/main.dart
endif

BUILD_ARGS=
DISTRIBUTOR_ARGS=--skip-clean --build-target $(TARGET) --artifact-name=$(FF_ARTIFACT_NAME)

# Dart AOT obfuscation for shipped artifacts. Strips class/method/field names
# from the snapshot, so the rayn:// key-derivation code can't be located by
# name — the layer that makes the masked key tables worth having. `--obfuscate`
# requires `--split-debug-info`; nothing consumes the symbol files (Sentry was
# removed) and .gitignore already covers `app.*.symbols` / `app.*.map.json`.
#
# fastforge forwards these to its internal `flutter build`: bare names become
# `--flag`, `k=v` pairs become `--k v`.
FF_OBFUSCATE=--flutter-build-args=obfuscate,split-debug-info=build/symbols

# Opt-in dart-defines, empty by default. Exists so a RELEASE build can carry a
# diagnostic affordance that is otherwise compiled out — TestFlight rejects debug
# builds (`get-task-allow`), and with the build host in the cloud and no USB path
# to the device, a kDebugMode-only gate is unreachable on the one topology that
# needs it. See IOS_BUILD.md -> "Producing a diagnostic build".
#
#   make ios-release CHANNEL=prod \
#     FF_DART_DEFINES=--build-dart-define=RAYN_DIAGNOSTICS=true
#
# Never set this for a shipping build.
FF_DART_DEFINES=



get:	
	flutter pub get

# Pigeon FIRST, and it is not optional on a fresh clone. Pigeon is a standalone
# CLI, not a build_runner builder, so `build_runner build` never produces its
# output — and that output, lib/features/auth/payment/data/rayn_billing.g.dart,
# matches the `**/*.g.dart` gitignore rule and is therefore absent from every
# fresh checkout. Its Kotlin twin RaynBilling.g.kt IS tracked (the ignore rule
# covers .g.dart only), which is why Android kept building and nobody noticed
# that a clean clone could not compile the Dart at all:
#
#   lib/features/auth/payment/.../purchase_notifier.dart: 'RaynOffer' isn't a type
#   ...: The getter 'BillingConnState' isn't defined
#
# Before build_runner, because build_runner analyses all of lib/ and the files
# importing the missing glue would otherwise be full of errors.
gen:
	dart run pigeon --input pigeons/rayn_billing.dart
	dart run build_runner build --delete-conflicting-outputs

translate:
	dart run slang

# Regenerates lib/utils/rayn_link_key_data.dart — the masked material the
# rayn://import/ AES-256-GCM key is reconstructed from. Reads RAYN_LINK_SECRET
# from the ENVIRONMENT (never argv, which CI runners echo) and hard-fails when
# it is unset, so a release can never ship the committed development key.
#
# The recipe is `@`-prefixed so make doesn't echo it; GitHub Actions masks
# registered secrets in its own output but not values make prints back.
#
# Every release target depends on this. Make runs a phony prerequisite once per
# invocation, so `make windows-release` regenerates once, not three times.
.PHONY: rayn-link-key rayn-link-key-dev
rayn-link-key:
	@dart run tool/gen_rayn_link_key.dart --require-secret

# Restores the committed development key file. Use after a release build so a
# local `flutter run` keeps working with the dev key.
#
# --dev is load-bearing: this runs right after a release build, in the same
# shell, where RAYN_LINK_SECRET is still exported. Without the flag the
# generator would pick that up and write a PRODUCTION key file under the name
# "restore the dev key".
rayn-link-key-dev:
	@dart run tool/gen_rayn_link_key.dart --dev



prepare:
	@echo use the following commands to prepare the library for each platform:
	@echo    make android-prepare
	@echo    make windows-prepare
	@echo    make linux-prepare 
	@echo    make macos-prepare
	@echo    make ios-prepare

common-prepare:  get gen translate
windows-prepare: common-prepare windows-libs
	
ios-prepare: common-prepare ios-libs 
	cd ios; pod repo update; pod install;echo "done ios prepare"
	
macos-prepare: common-prepare macos-libs
linux-prepare: common-prepare linux-amd64-libs


linux-amd64-prepare: common-prepare linux-amd64-libs
linux-arm64-prepare: common-prepare linux-arm64-libs
linux-amd64-musl-prepare: common-prepare linux-amd64-musl-libs
linux-arm64-musl-prepare: common-prepare linux-arm64-musl-libs


linux-appimage-prepare:linux-prepare
linux-rpm-prepare:linux-prepare
linux-deb-prepare:linux-prepare

android-prepare:common-prepare android-libs	
android-apk-prepare:android-prepare
android-aab-prepare:android-prepare

.PHONY: generate_kotlin_protos
generate_kotlin_protos: 
	# Run protoc to generate Kotlin files
	# protoc \
	# 	--proto_path=hiddify-core/ \
	# 	--java_out=./android/app/src/main/java/ \
	# 	--grpc-java_out=./android/app/src/main/java/ \
	# 	$(shell find hiddify-core/v2 hiddify-core/extension -name "*.proto")
	rsync -av --delete \
		--include='*/' \
		--include='*.proto' \
		--exclude='*' \
		hiddify-core/v2 hiddify-core/extension ./android/app/src/main/protos/
	# # Find .proto files and update package declarations
	# find "./android/app/src/main/java/com/hiddify/hiddify/protos" -type f -name "*.java" | while read -r proto_file; do \
	#     if grep -q "^package " "$$proto_file"; then \
	#         $(SED) 's/^package \([\w\.]*\)/package com.raynlabs.app.protos.\1/g' "$$proto_file"; \
	#     fi \
	# done

generate_go_protoc:
	make -C hiddify-core -f Makefile protos
	echo "SED: $(SED)"
generate_dart_protoc:
	mkdir -p lib/hiddifycore/generated
	protoc --dart_out=grpc:lib/hiddifycore/generated --proto_path=hiddify-core/  $(shell find hiddify-core/v2 hiddify-core/extension -name "*.proto") 	google/protobuf/timestamp.proto ; \

.PHONY: protos
protos: generate_go_protoc generate_kotlin_protos generate_dart_protoc
	
	
	

macos-install-deps:
	brew install create-dmg tree 
	npm install -g appdmg
	dart pub global activate fastforge

ios-install-deps: 
	if [ "$(flutter)" = "true" ]; then \
		curl -L -o ~/Downloads/flutter_macos_3.19.3-stable.zip https://storage.googleapis.com/flutter_infra_release/releases/stable/macos/flutter_macos_3.22.3-stable.zip; \
		mkdir -p ~/develop; \
		cd ~/develop; \
		unzip ~/Downloads/flutter_macos_3.22.3-stable.zip; \
		export PATH="$$PATH:$$HOME/develop/flutter/bin"; \
		echo 'export PATH="$$PATH:$$HOME/develop/flutter/bin"' >> ~/.zshrc; \
		export PATH="$PATH:$HOME/develop/flutter/bin"; \
		echo 'export PATH="$PATH:$HOME/develop/flutter/bin"' >> ~/.zshrc; \
		curl -sSL https://rvm.io/mpapis.asc | gpg --import -; \
		curl -sSL https://rvm.io/pkuczynski.asc | gpg --import -; \
		curl -sSL https://get.rvm.io | bash -s stable; \
		brew install openssl@1.1; \
		PKG_CONFIG_PATH=$(brew --prefix openssl@1.1)/lib/pkgconfig rvm install 2.7.5; \
		sudo gem install cocoapods -V; \
	fi
	brew install create-dmg tree 
	npm install -g appdmg
	
	dart pub global activate fastforge
	

android-install-deps: 
	dart pub global activate fastforge
android-apk-install-deps: android-install-deps
android-aab-install-deps: android-install-deps
# loads the package list from linux_deps.list
LINUX_DEPS = $(shell grep -vE '^\s*#|^\s*$$' linux_deps.list)
# reads the Flutter version from pubspec.yaml
REQUIRED_VER = $(shell sed -n '/environment:/,/flutter:/ s/.*flutter:[[:space:]]*//p' pubspec.yaml | tr -d " '^\"")

linux-amd64-install-deps:linux-install-deps
linux-amd64-musl-install-deps:linux-install-deps
linux-arm64-install-deps:linux-install-deps
linux-arm64-musl-install-deps:linux-install-deps

linux-install-deps:
	@$(BLUE)Installing Debian/Ubuntu dependencies...$(DONE)
	sudo apt-get update -y
	sudo apt-get install -y $(LINUX_DEPS)
#	loading fuce kernel module
	@$(BLUE)Loading fuce kernel module$(DONE)
	sudo modprobe fuse
# 	tools for appimage
	@$(BLUE)Installing appimagetool$(DONE)
	if [ "$$(uname -m)" = "aarch64" ]; then \
		wget -O /tmp/appimagetool "https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-aarch64.AppImage"; \
	else \
		wget -O /tmp/appimagetool "https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage"; \
	fi
	chmod +x /tmp/appimagetool
	sudo mv /tmp/appimagetool /usr/local/bin/
#   cloning flutter sdk
	@$(BLUE)Cloning Flutter SDK$(DONE); \
	mkdir -p ~/develop; \
	cd ~/develop; \
	\
	if [ ! -d "flutter/.git" ]; then \
		$(BLUE)Flutter not found. cloning stable channel$(DONE); \
		rm -rf flutter; \
		git clone https://github.com/flutter/flutter.git -b stable flutter; \
	fi; \
	\
	git config --global --add safe.directory $$HOME/develop/flutter; \
	\
	export PATH="$$HOME/develop/flutter/bin:$$PATH"; \
	if ! grep -q 'flutter/bin' ~/.bashrc; then \
		echo 'export PATH="$$HOME/develop/flutter/bin:$$PATH"' >> ~/.bashrc; \
	fi
# 	syncing flutter version
	$(MAKE) linux-flutter-sync
# 	installing fastforge https://pub.dev/packages/fastforge
	@$(BLUE)Installing fastforge$(DONE); \
	export PATH="$$HOME/develop/flutter/bin:$$HOME/.pub-cache/bin:$$PATH"; \
	if ! grep -q '.pub-cache/bin' ~/.bashrc; then \
		echo 'export PATH="$$HOME/.pub-cache/bin:$$PATH"' >> ~/.bashrc; \
	fi; \
	dart pub global activate fastforge; \
	dart pub global activate protoc_plugin; \
	echo ""; \
	echo "============================================================"; \
	echo "NOTE: After first setup, use the following command to update the PATH"; \
	echo "source ~/.bashrc"; \
	echo "============================================================"

# 	syncing 'flutter sdk' version with pubspec.yaml flutter version
linux-flutter-sync:
	@$(BLUE)Syncing Flutter version with pubspec.yaml flutter version$(DONE); \
	export PATH="$$HOME/develop/flutter/bin:$$PATH"; \
	$(BLUE)Downloading Flutter SDK components...$(DONE); \
	flutter --version > /dev/null; \
	\
	$(BLUE)Checking Flutter version...$(DONE); \
	CURRENT_VER=$$(flutter --version | head -n 1 | awk '{print $$2}'); \
	$(BLUE)Target: $(REQUIRED_VER) | Current: $$CURRENT_VER$(DONE); \
	\
	if [ "$$CURRENT_VER" != "$(REQUIRED_VER)" ]; then \
		$(BLUE)Version mismatch! switching to $(REQUIRED_VER)...$(DONE); \
		cd ~/develop/flutter; \
		git fetch --tags; \
		git checkout $(REQUIRED_VER); \
		$(BLUE)Switched to $(REQUIRED_VER)$(DONE); \
		flutter doctor; \
	else \
		$(GREEN)Flutter SDK is ready.$(DONE); \
	fi

windows-install-deps:
	dart pub global activate fastforge
# 	choco install innosetup -y
	
gen_translations: #generating missing translations using google translate
	cd .github && bash sync_translate.sh
	make translate

android-release: android-apk-release android-aab-release

android-apk-release: check-rulesets-fresh rayn-link-key
	$(FASTFORGE) package \
	  --platform android \
	  --targets apk \
	  --skip-clean \
	  --artifact-name=$(FF_ARTIFACT_NAME) \
	  --build-target=$(TARGET) \
	  $(FF_OBFUSCATE) \
	  --build-target-platform=android-arm,android-arm64,android-x64
	ls -R build/app/outputs

android-aab-release: check-rulesets-fresh rayn-link-key
	$(FASTFORGE) package \
	  --platform android \
	  --targets aab \
	  --skip-clean \
	  --artifact-name=$(FF_ARTIFACT_NAME) \
	  --build-target=$(TARGET) \
	  $(FF_OBFUSCATE) \
	  --build-dart-define=release=google-play

windows-release: windows-zip-release windows-exe-release windows-msix-release

windows-zip-release: check-rulesets-fresh rayn-link-key
	$(FASTFORGE) package \
	  --platform windows \
	  --targets zip \
	  --skip-clean \
	  --artifact-name=$(FF_ARTIFACT_NAME) \
	  --build-target=$(TARGET) \
	  $(FF_OBFUSCATE) \
	  --build-dart-define=portable=true
	@FULL_PATH=$$(ls dist/*/*.zip | head -n 1); \
	ZIP_DIR=$$(dirname "$$FULL_PATH"); \
	ZIP_FILE=$$(basename "$$FULL_PATH"); \
	FILE_NAME=$${ZIP_FILE%.*}; \
	$(YELLOW)Post-processing Windows portable$(DONE); \
	cd "$$ZIP_DIR"; \
	$(BLUE)Extracting and Repacking...$(DONE); \
	mkdir -p RaynVPN; \
	unzip -q "$$ZIP_FILE" -d RaynVPN/; \
	rm "$$ZIP_FILE"; \
	tar -a -cf "$$FILE_NAME.zip" RaynVPN; \
	rm -rf RaynVPN; \
	$(GREEN)Successful$(DONE)

windows-exe-release: check-rulesets-fresh rayn-link-key
	$(FASTFORGE) package \
	  --platform windows \
	  --targets exe \
	  --skip-clean \
	  --artifact-name=$(FF_ARTIFACT_NAME) \
	  --build-target=$(TARGET) \
	  $(FF_OBFUSCATE)

windows-msix-release: check-rulesets-fresh rayn-link-key
	$(FASTFORGE) package \
	  --platform windows \
	  --targets msix \
	  --skip-clean \
	  --artifact-name=$(FF_ARTIFACT_NAME) \
	  --build-target=$(TARGET) \
	  $(FF_OBFUSCATE)

linux-release: linux-deb-release linux-appimage-release

linux-amd64-release: linux-release
linux-arm64-release: linux-release
linux-amd64-musl-release: linux-release 
linux-arm64-musl-release: linux-release


linux-deb-release: check-rulesets-fresh rayn-link-key
	$(FASTFORGE) package \
	--platform linux \
	--targets deb \
	--skip-clean \
	--artifact-name=$(FF_ARTIFACT_NAME) \
	--build-target=$(TARGET) \
	$(FF_OBFUSCATE)


# ==============================================================================
# REFERENCE: MANUAL LIBRARY BUNDLING (INJECTION)
# ==============================================================================
# Use this method only if you need to manually force specific shared libraries 
# (e.g., libcurl.so.4) into the AppImage bundle.
#
# IMPLEMENTATION STEPS:
#
# 1. PRE-BUILD SCRIPT (Add to Makefile before build command):
#    Create a temporary directory and copy the target library there.
#    ---------------------------------------------------------------------------
#    mkdir -p linux/bundled_libs
#    cp /usr/lib/x86_64-linux-gnu/libcurl.so.4 linux/bundled_libs/
#    ---------------------------------------------------------------------------
#
# 2. CMAKE CONFIGURATION (Add to linux/CMakeLists.txt):
#    Instruct CMake to include the copied file in the final bundle.
#    ---------------------------------------------------------------------------
#    install(FILES "${CMAKE_CURRENT_SOURCE_DIR}/bundled_libs/libcurl.so.4"
#       DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
#       COMPONENT Runtime)
#    ---------------------------------------------------------------------------
#
# ! WARNING !
# This approach is generally DISCOURAGED. Manually bundling libraries can lead to
# "Dependency Hell," where bundled libs conflict with system libraries or have
# their own unresolved dependencies. It increases maintenance cost and may cause
# runtime instability. Use only for specific edge cases where standard linking fails.
# ==============================================================================
linux-appimage-release: check-rulesets-fresh rayn-link-key
	$(FASTFORGE) package \
	--platform linux \
	--targets appimage \
	--skip-clean \
	--artifact-name=$(FF_ARTIFACT_NAME) \
	--build-target=$(TARGET) \
	$(FF_OBFUSCATE)
	@$(YELLOW)Post-processing AppImage$(DONE); \
	$(BLUE)Extracting AppImage$(DONE); \
	cd dist/* && ./*.AppImage --appimage-extract > /dev/null; \
	$(BLUE)Replacing AppRun$(DONE); \
	cp ../../linux/packaging/appimage/AppRun squashfs-root/AppRun; \
	$(BLUE)Granting permissions$(DONE); \
	chmod +x squashfs-root/AppRun; \
	$(BLUE)Renaming desktop file: hiddify.desktop -> RaynVPN.desktop$(DONE); \
	mv squashfs-root/hiddify.desktop squashfs-root/RaynVPN.desktop; \
	$(BLUE)Adding StartupWMClass to RaynVPN.desktop$(DONE); \
	sed -i '/^\[Desktop Entry\]/a StartupWMClass=com.raynlabs.app' "squashfs-root/RaynVPN.desktop"; \
	$(BLUE)Removing old AppImage$(DONE); \
	rm *.AppImage; \
	$(BLUE)Deleting bundled libstdc++ to fix Arch Linux compatibility...$(DONE); \
	find squashfs-root/usr/lib -name "libstdc++.so.6" -delete; \
	$(BLUE)Rebuilding AppImage$(DONE); \
	ARCH=x86_64 appimagetool --no-appstream squashfs-root RaynVPN.AppImage > /dev/null; \
	$(BLUE)Cleaning up squashfs$(DONE); \
	rm -rf squashfs-root; \
	$(YELLOW)Creating Portable Package$(DONE); \
	PKG_DIR_NAME="RaynVPN-linux-appimage"; \
	$(BLUE)Creating dir: $$PKG_DIR_NAME$(DONE); \
	mkdir -p "$$PKG_DIR_NAME"; \
	$(BLUE)Moving RaynVPN.AppImage$(DONE); \
	cp -p "RaynVPN.AppImage" "$$PKG_DIR_NAME/RaynVPN.AppImage"; \
	$(BLUE)Creating Portable Home directory$(DONE); \
	mkdir -p "$$PKG_DIR_NAME/RaynVPN.AppImage.home"; \
	$(BLUE)Compressing to .tar.gz$(DONE); \
	tar -czf "$$PKG_DIR_NAME.tar.gz" -C . "$$PKG_DIR_NAME"; \
	$(BLUE)Removing intermediate directory$(DONE); \
	rm -rf "$$PKG_DIR_NAME"; \
	$(GREEN)Successful$(DONE)

DOCKER_IMAGE_NAME := hiddify-linux-builder
DOCKER_FLUTTER_VOL := hiddify-flutter-sdk-cache
DOCKER_PUB_VOL := hiddify-pub-cache

ifeq ($(OS),Windows_NT)
    FIX_OWNERSHIP := echo \"Windows detected: Skipping chown\"
else
    FIX_OWNERSHIP := chown -R $(shell id -u):$(shell id -g) /host/dist_docker
endif

DOCKER_CMD := \
	set -e; \
	echo '** Copying source code to container...'; \
	mkdir -p /app; \
	cp -r /host/. /app/; \
	cd /app; \
	make linux-flutter-sync; \
	make linux-prepare; \
	echo '** Building Release (linux-release)...'; \
	make linux-release; \
	echo '** Copying artifacts to host...'; \
	rm -rf /host/dist_docker; \
	if [ -d \"dist\" ]; then \
		cp -r dist /host/dist_docker; \
		echo '** Fixing permissions for dist_docker...'; \
		$(FIX_OWNERSHIP); \
	else \
		echo 'Error: dist folder not found!'; \
		exit 1; \
	fi;

linux-docker-release:
	@$(BLUE)Cleaning main project to reduce context size$(DONE)
	flutter clean
	
	@$(BLUE)Building docker image (Cached)$(DONE)
	docker build -t $(DOCKER_IMAGE_NAME) -f Dockerfile .
	
	@$(BLUE)Ensuring cache volumes exist$(DONE)
	docker volume create $(DOCKER_FLUTTER_VOL) || true
	docker volume create $(DOCKER_PUB_VOL) || true

	@$(YELLOW)Running build inside container$(DONE)
	@docker run --rm \
		-v "$(CURDIR)://host" \
		-v $(DOCKER_FLUTTER_VOL)://root/develop/flutter \
		-v $(DOCKER_PUB_VOL)://root/.pub-cache \
		-e APPIMAGE_EXTRACT_AND_RUN=1 \
		$(DOCKER_IMAGE_NAME) \
		//bin/bash -c "$(DOCKER_CMD)"

	@$(GREEN)Successful. Output is in 'dist_docker' folder.$(DONE)

macos-release: check-rulesets-fresh rayn-link-key
	$(FASTFORGE) package --platform macos --targets dmg,pkg $(DISTRIBUTOR_ARGS) $(FF_OBFUSCATE)

ios-release: check-rulesets-fresh rayn-link-key #not tested
	$(FASTFORGE) package --platform ios --targets ipa --build-export-options-plist  ios/exportOptions.plist $(DISTRIBUTOR_ARGS) $(FF_OBFUSCATE) $(FF_DART_DEFINES)

# Ad-hoc build for the fast device loop (ios-remote-mac-fast-testing-guide.md).
# Depends on rayn-link-key for the same reason ios-release does: without it the
# artifact carries the COMMITTED DEVELOPMENT rayn:// key and a live token will
# not decrypt, so token import cannot be tested. Exporting from Xcode's Organizer
# skips this and produces exactly that broken build.
#
# Not obfuscated: this never ships, and readable symbols make a crash log useful.
# Named -adhoc so it can never be mistaken for a store artifact.
ios-adhoc: check-rulesets-fresh rayn-link-key
	$(FASTFORGE) package --platform ios --targets ipa \
	  --build-export-options-plist ios/exportOptions-adhoc.plist \
	  --skip-clean --build-target $(TARGET) \
	  --artifact-name=RaynVPN-{{build_name}}+{{build_number}}-adhoc.{{ext}} \
	  $(FF_DART_DEFINES)

android-libs:
	$(MKDIR) $(ANDROID_OUT) || echo Folder already exists. Skipping...
	curl -L $(CORE_URL)/$(CORE_NAME)-android.tar.gz | tar xz -C $(ANDROID_OUT)/

android-apk-libs: android-libs
android-aab-libs: android-libs

windows-libs:
	$(MKDIR) $(DESKTOP_OUT) || echo Folder already exists. Skipping...
	curl -L $(CORE_URL)/$(CORE_NAME)-windows-amd64.tar.gz | tar xz -C $(DESKTOP_OUT)/
	ls $(DESKTOP_OUT) || dir $(DESKTOP_OUT)/
	

linux-amd64-libs:
	mkdir -p $(DESKTOP_OUT)
	curl -L $(CORE_URL)/$(CORE_NAME)-linux-amd64.tar.gz | tar xz -C $(DESKTOP_OUT)/

linux-arm64-libs:
	mkdir -p $(DESKTOP_OUT)
	curl -L $(CORE_URL)/$(CORE_NAME)-linux-arm64.tar.gz | tar xz -C $(DESKTOP_OUT)/

linux-amd64-musl-libs:
	mkdir -p $(DESKTOP_OUT)
	curl -L $(CORE_URL)/$(CORE_NAME)-linux-amd64-musl.tar.gz | tar xz -C $(DESKTOP_OUT)/

linux-arm64-musl-libs:
	mkdir -p $(DESKTOP_OUT)
	curl -L $(CORE_URL)/$(CORE_NAME)-linux-arm64-musl.tar.gz | tar xz -C $(DESKTOP_OUT)/


macos-libs:
	mkdir -p  $(DESKTOP_OUT) 
	curl -L $(CORE_URL)/$(CORE_NAME)-macos.tar.gz | tar xz -C $(DESKTOP_OUT)

ios-libs: #not tested
	mkdir -p $(IOS_OUT)
	rm -rf $(IOS_OUT)/RaynCore.xcframework
	curl -L $(CORE_URL)/$(CORE_NAME)-ios.tar.gz | tar xz -C "$(IOS_OUT)"

get-geo-assets:
	echo ""
	# curl -L https://github.com/SagerNet/sing-geoip/releases/latest/download/geoip.db -o $(GEO_ASSETS_DIR)/geoip.db
	# curl -L https://github.com/SagerNet/sing-geosite/releases/latest/download/geosite.db -o $(GEO_ASSETS_DIR)/geosite.db

# CN routing rule-sets are bundled into the AAB so they're available on first
# launch inside the GFW (where raw.githubusercontent.com is unreachable). The
# Dart extractor in lib/core/rulesets/ copies these from assets/ to the Go
# core's BasePath on first launch / app update. See RULESETS.md for the human
# workflow.
RULESETS_DIR := assets$(SEP)rulesets
RULESETS_GEOSITE_BASE := https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set
RULESETS_GEOIP_BASE := https://raw.githubusercontent.com/SagerNet/sing-geoip/rule-set
# Blocklists come from hiddify-geo rather than SagerNet. SagerNet publishes
# geosite-category-ads-all but it is the small upstream v2fly list (~900 rules,
# 8 KB); hiddify-geo's is a merged list with 42,619 domain suffixes. It also
# carries malware/phishing/cryptominer sets that SagerNet's rule-set branch does
# not have at all. Build-time dependency only — the client never fetches these.
RULESETS_BLOCK_BASE := https://raw.githubusercontent.com/hiddify/hiddify-geo/rule-set/block

.PHONY: fetch-rulesets check-rulesets-fresh

fetch-rulesets:
	@$(BLUE)Fetching CN routing rule-sets from SagerNet$(DONE)
	$(MKDIR) $(RULESETS_DIR)
	# Bundled files are saved under neutral names so the region they target is not
	# revealed by `strings libcore.so` or the AAB asset listing. The upstream
	# source name is on the left of each line; the local name (matching the Go
	# rule-set tag in builder.go) is the -o target on the right:
	#   geosite-private        -> direct-private
	#   geosite-apple@cn       -> direct-apple
	#   geosite-cn             -> direct-regional-sites
	#   geoip-cn               -> direct-regional-ips
	#
	# DO NOT re-add geosite-geolocation-!cn -> fakeip-remote-sites. It was only
	# ever consumed by the FakeIP DNS path, which was removed (the hub runs
	# domainStrategy:AsIs and needs real IPs). Nothing in builder.go references
	# the tag any more, and at 167 KB it was 61% of the whole rule-set bundle.
	curl -fSL $(RULESETS_GEOSITE_BASE)/geosite-private.srs           -o $(RULESETS_DIR)/direct-private.srs
	curl -fSL "$(RULESETS_GEOSITE_BASE)/geosite-apple@cn.srs"        -o $(RULESETS_DIR)/direct-apple.srs
	curl -fSL $(RULESETS_GEOSITE_BASE)/geosite-cn.srs                -o $(RULESETS_DIR)/direct-regional-sites.srs
	curl -fSL $(RULESETS_GEOIP_BASE)/geoip-cn.srs                    -o $(RULESETS_DIR)/direct-regional-ips.srs
	@$(BLUE)Fetching blocklist rule-sets$(DONE)
	# Gated at runtime by the `block-ads` option, but always bundled so enabling it
	# costs no network. Local names match the Tag/Path literals in builder.go's
	# BlockAds branch:
	#   geosite-category-ads-all -> block-ads
	#   geosite-malware          -> block-malware
	#   geosite-phishing         -> block-phishing
	#   geosite-cryptominers     -> block-cryptominers
	#   geoip-malware            -> block-malware-ips
	#   geoip-phishing           -> block-phishing-ips
	curl -fSL $(RULESETS_BLOCK_BASE)/geosite-category-ads-all.srs    -o $(RULESETS_DIR)/block-ads.srs
	curl -fSL $(RULESETS_BLOCK_BASE)/geosite-malware.srs             -o $(RULESETS_DIR)/block-malware.srs
	curl -fSL $(RULESETS_BLOCK_BASE)/geosite-phishing.srs            -o $(RULESETS_DIR)/block-phishing.srs
	curl -fSL $(RULESETS_BLOCK_BASE)/geosite-cryptominers.srs        -o $(RULESETS_DIR)/block-cryptominers.srs
	curl -fSL $(RULESETS_BLOCK_BASE)/geoip-malware.srs               -o $(RULESETS_DIR)/block-malware-ips.srs
	curl -fSL $(RULESETS_BLOCK_BASE)/geoip-phishing.srs              -o $(RULESETS_DIR)/block-phishing-ips.srs
	@$(BLUE)Regenerating MANIFEST$(DONE)
	bash scripts/regen_rulesets_manifest.sh
	@$(GREEN)Rule-sets refreshed. Commit assets/rulesets/ before cutting a release.$(DONE)

# Soft warning hook for release builds — does not fail the build, just nags if
# the bundled rule-sets look stale (>30 days since last `make fetch-rulesets`).
# Two tiers, because the bundle mixes two rates of decay. The CN routing sets
# (geosite-cn / geoip-cn) move slowly. The blocklists do not: ad, phishing and
# malware domains churn continuously, and a months-old block-ads.srs keeps loading
# cleanly while quietly blocking less and less. A single 30-day threshold was set
# when only the CN sets were bundled.
RULESETS_STALE_NOTICE_DAYS := 14
RULESETS_STALE_WARN_DAYS   := 30

# Soft by design — warns, never fails. A hotfix must never be blocked by a stale
# blocklist. Age comes from the MANIFEST's own `fetched_at`, NOT the file's mtime:
# a fresh clone or a branch switch rewrites mtime to "now", which is exactly the
# case where the committed rule-sets are most likely to be months old and the
# warning most needed. Falls back gracefully when the timestamp can't be parsed
# (BSD and GNU `date` disagree on how to read one).
check-rulesets-fresh:
	@MANIFEST="$(RULESETS_DIR)/MANIFEST"; \
	if [ ! -f "$$MANIFEST" ]; then \
	  $(YELLOW)WARNING: $$MANIFEST missing — run 'make fetch-rulesets' before release$(DONE); \
	  exit 0; \
	fi; \
	FETCHED=$$(sed -n 's/.*"fetched_at"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$$MANIFEST" | head -n1); \
	THEN=$$(date -u -d "$$FETCHED" +%s 2>/dev/null \
	     || date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$$FETCHED" +%s 2>/dev/null \
	     || echo ""); \
	if [ -z "$$THEN" ]; then \
	  $(YELLOW)WARNING: could not read fetched_at from $$MANIFEST — run 'make fetch-rulesets' if in doubt$(DONE); \
	  exit 0; \
	fi; \
	AGE=$$(( ( $$(date -u +%s) - $$THEN ) / 86400 )); \
	if [ "$$AGE" -ge $(RULESETS_STALE_WARN_DAYS) ]; then \
	  $(YELLOW)WARNING: rule-sets are $$AGE days old (>= $(RULESETS_STALE_WARN_DAYS)) — run 'make fetch-rulesets' before shipping. Blocklists this old have measurably degraded.$(DONE); \
	elif [ "$$AGE" -ge $(RULESETS_STALE_NOTICE_DAYS) ]; then \
	  $(YELLOW)NOTICE: rule-sets are $$AGE days old — consider 'make fetch-rulesets' before release$(DONE); \
	fi

# Extra Go build tags for the core, forwarded to hiddify-core/Makefile where they
# are APPENDED to the required tag list rather than replacing it:
#
#   make build-windows-libs EXTRA_TAGS=raynconfigdump
#
# raynconfigdump makes the core write the full built config (outbounds plus our
# routing, DNS and balancer groups) to data/debug-built-config.json in plaintext
# — the only way to inspect it, since no runtime flag can be trusted for this
# (see v2/hcore/configdump.go). NEVER ship a core built with it.
EXTRA_TAGS=

build-headers:
	make -C hiddify-core -f Makefile headers && mv $(BINDIR)/$(CORE_NAME)-headers.h $(BINDIR)/hiddify-core.h

build-android-libs:
	make -C hiddify-core -f Makefile android EXTRA_TAGS="$(EXTRA_TAGS)"
	# Rayn rebrand (audit C1): the android target now emits rayn-core.aar
	# (librayn-core.so inside), not $(LIB_NAME).aar.
	mv $(BINDIR)/rayn-core.aar $(ANDROID_OUT)/

build-windows-libs:
	make -C hiddify-core -f Makefile windows-amd64 EXTRA_TAGS="$(EXTRA_TAGS)"

build-linux-libs:
	make -C hiddify-core -f Makefile linux-amd64 EXTRA_TAGS="$(EXTRA_TAGS)"

build-macos-libs:
	make -C hiddify-core -f Makefile macos EXTRA_TAGS="$(EXTRA_TAGS)"

build-ios-libs:
	rm -rf $(IOS_OUT)/RaynCore.xcframework
	make -C hiddify-core -f Makefile ios EXTRA_TAGS="$(EXTRA_TAGS)"
	mv $(BINDIR)/RaynCore.xcframework $(IOS_OUT)/RaynCore.xcframework

release: # Create a new tag for release.
	@CORE_VERSION=$(core.version) bash -c ".github/change_version.sh "



ios-temp-prepare: 
	make ios-prepare
	flutter build ios-framework
	cd ios
	pod install
	