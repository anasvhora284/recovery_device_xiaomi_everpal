#!/usr/bin/env bash
# AERA (everpal) CI steps, called by .github/workflows/aera-build.yml as: bash aera-ci.sh <step>
# Kept out of the workflow file so fixes don't need a token with the `workflow` scope.
set -euo pipefail
TREE=$(cd "$(dirname "$0")/.." && pwd)     # this device tree (actions/checkout)
: "${SRC:=$HOME/aera}" "${OUT_DIR:=/mnt/out}"

case "$1" in
free)
	sudo rm -rf /usr/share/dotnet /usr/local/lib/android /opt/ghc /opt/hostedtoolcache \
		/usr/local/share/boost /usr/share/swift /usr/local/.ghcup /usr/lib/jvm /usr/local/share/powershell
	sudo docker system prune -af >/dev/null 2>&1 || true
	sudo mkdir -p "$OUT_DIR" && sudo chown "$USER:$USER" "$OUT_DIR"
	sudo fallocate -l 16G /mnt/swap && sudo chmod 600 /mnt/swap && sudo mkswap /mnt/swap >/dev/null && sudo swapon /mnt/swap
	df -h / /mnt; free -g; nproc ;;
tools)
	sudo apt-get update -qq
	sudo apt-get install -y -qq git-core gnupg flex bison build-essential zip curl zlib1g-dev libc6-dev-i386 \
		x11proto-core-dev libx11-dev lib32z1-dev libgl1-mesa-dev libxml2-utils xsltproc unzip fontconfig \
		python-is-python3 rsync >/dev/null
	mkdir -p ~/bin && curl -s https://storage.googleapis.com/git-repo-downloads/repo > ~/bin/repo && chmod +x ~/bin/repo
	echo "$HOME/bin" >> "${GITHUB_PATH:-/dev/null}"
	git config --global user.name ci && git config --global user.email ci@localhost ;;
sync)
	mkdir -p "$SRC" && cd "$SRC"
	repo init -q --depth=1 -u https://github.com/AERA-Recovery/android_manifest.git -b aera-16.0
	# AOSP (googlesource) rate-limits busy CI IPs (RESOURCE_EXHAUSTED): fewer jobs + resume-retries
	for try in 1 2 3 4; do
		repo sync -q -c -j8 --force-sync --no-clone-bundle --no-tags --optimized-fetch && break
		[ $try = 4 ] && exit 1; echo "sync attempt $try failed, retrying in $((try*60)) s"; sleep $((try*60))
	done
	# AERA_ENABLE_WLAN needs it; newer AERA manifests already ship it
	[ -e external/wpa_supplicant_8/Android.bp ] || git clone -q --depth=1 -b android16-s2-release \
		https://android.googlesource.com/platform/external/wpa_supplicant_8 external/wpa_supplicant_8
	mkdir -p device/xiaomi && rm -rf device/xiaomi/everpal && cp -a "$TREE" device/xiaomi/everpal
	df -h / ;;
patch)
	cd "$SRC"
	for d in "$TREE"/aera-patches/*/; do
		proj=$(basename "$d" | tr _ /)     # bootable_recovery -> bootable/recovery (ponytail: no '_' in project names yet)
		for p in "$d"*.patch; do echo "== $proj <- ${p##*/}"; git -C "$proj" apply --verbose "$p"; done
	done ;;
build)
	cd "$SRC"
	export AERA_BUILD_DEVICE=everpal
	set +u; source build/envsetup.sh; lunch twrp_everpal-bp2a-eng; set -u
	mka adbd bootimage
	ls -la "$OUT_DIR/target/product/everpal/" | grep -E "\.img|\.zip" ;;
*) echo "usage: $0 free|tools|sync|patch|build"; exit 2 ;;
esac
