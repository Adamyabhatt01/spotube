INNO_VERSION=6.2.0
TEMP_DIR=/tmp/spotube-tar
USR_SHARE=deb-struct/usr/share
BUNDLE_DIR=build/linux/${ARCH}/release/bundle
MIRRORLIST=${PWD}/build/mirrorlist
# `fvm flutter` when fvm is available (this repo pins its SDK in .fvmrc),
# plain `flutter` otherwise.
FLUTTER=$(shell command -v fvm >/dev/null 2>&1 && echo "fvm flutter" || echo flutter)

tar:
		mkdir -p $(TEMP_DIR)\
		&& cp -r $(BUNDLE_DIR)/* $(TEMP_DIR)\
		&& cp linux/spotube.desktop $(TEMP_DIR)\
		&& cp assets/branding/spotube-logo.png $(TEMP_DIR)\
		&& cp linux/com.github.KRTirtho.Spotube.appdata.xml $(TEMP_DIR)\
		&& tar -cJf build/spotube-linux-${VERSION}-${PKG_ARCH}.tar.xz -C $(TEMP_DIR) .\
		&& rm -rf $(TEMP_DIR)

aursrcinfo:
					 docker run -e EXPORT_SRC=1 -v ${PWD}/aur-struct:/pkg -v ${MIRRORLIST}:/etc/pacman.d/mirrorlist:ro whynothugo/makepkg

publishaur: 
					 echo '[Warning!]: you need SSH paired with AUR'\
					 && rm -rf build/spotube\
					 && git clone ssh://aur@aur.archlinux.org/spotube-bin.git build/spotube\
					 && cp aur-struct/PKGBUILD aur-struct/.SRCINFO build/spotube\
					 && cd build/spotube\
					 && git add .\
					 && git commit -m "${MSG}"\
					 && git push

innoinstall:
						powershell curl -o build\installer.exe http://files.jrsoftware.org/is/6/innosetup-${INNO_VERSION}.exe
						powershell git clone https://github.com/DomGries/InnoDependencyInstaller.git  build\inno-depend
		 				powershell build\installer.exe /verysilent /allusers /dir=build\iscc

inno:
		 powershell .\build\iscc\iscc.exe scripts\windows-setup-creator.iss

choco:
			powershell cp dist\Spotube-windows-x86_64-setup.exe choco-struct\tools
			powershell choco pack .\choco-struct\spotube.nuspec  --outputdirectory dist

apk:
		mkdir -p build
		for f in build/app/outputs/flutter-apk/app-*-release.apk; do \
			n=$$(basename $$f .apk | sed 's/^app-//;s/-release$$//'); \
			mv $$f build/Spotube-android-$$n.apk; \
		done
		ls -lh build/Spotube-android-*.apk

# Arm64-v8a only APK.
#
# `--target-platform android-arm64` alone is NOT enough: it narrows the Dart
# AOT, but with ABI splits disabled the Flutter Gradle plugin sets
# `buildType.ndk.abiFilters` to all three ABIs, so the prebuilt native libs
# (mpv, metadata_god, media_kit, flutter_discord_rpc) still ship for
# armeabi-v7a and x86_64. `--split-per-abi` makes the plugin emit
# `splits.abi.include("arm64-v8a")` and nothing else, which drops ~23 MB of
# foreign-ABI libraries. The plugin also applies the per-ABI versionCode
# override (arm64 = 2 * 1000 + versionCode) so Play Store versioning stays
# correct.
apk-arm64:
		$(FLUTTER) build apk --release --target-platform android-arm64 --split-per-abi --flavor stable
		mkdir -p build
		cp build/app/outputs/flutter-apk/app-arm64-v8a-stable-release.apk build/Spotube-android-arm64-v8a.apk
		ls -lh build/Spotube-android-arm64-v8a.apk

gensums:
				sh -c scripts/gensums.sh

migrate:
				dart run drift_dev make-migrations

dmg:
		flutter build macos &&\
		if [ -f dist/Spotube-macos-universal.dmg ];\
		then rm dist/Spotube-macos-universal.dmg;\
		fi &&\
		appdmg appdmg.json dist/Spotube-macos-universal.dmg

changelog:
	git-cliff --unreleased