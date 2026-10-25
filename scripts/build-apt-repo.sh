#!/usr/bin/env sh
# Usage: build-apt-repo.sh SITE DEB...
# Builds the GitHub Pages site that hosts serve apt updates from: a signed
# flat apt repository of DEB..., plus the keyring and sources file that the
# install instructions download. Release CI deploys SITE to
# https://reverse-bin-hosting.coolness.fyi/.
#
# The signing key is decrypted from packaging/apt/signing-key.sops.json with
# SOPS_AGE_KEY (CI) or a maintainer SSH key (see sync-sops-recipients.sh).
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SITE=${1:?usage: build-apt-repo.sh SITE DEB...}
shift
[ "$#" -gt 0 ] || { echo "usage: build-apt-repo.sh SITE DEB..." >&2; exit 1; }
SOPS=${SOPS:-$(command -v sops || echo "$ROOT/build/sops")}
KEYRING="$ROOT/packaging/apt/reverse-bin-archive-keyring.asc"

GNUPGHOME=$(mktemp -d "${TMPDIR:-/tmp}/reverse-bin-apt-gpg.XXXXXX")
export GNUPGHOME
cleanup() { rm -rf "$GNUPGHOME"; }
trap cleanup EXIT INT TERM

"$SOPS" decrypt --output-type binary "$ROOT/packaging/apt/signing-key.sops.json" > "$GNUPGHOME/key.asc"
gpg --batch --quiet --import "$GNUPGHOME/key.asc"
gpg --batch --dearmor -o "$GNUPGHOME/keyring.gpg" "$KEYRING"
fingerprint=$(gpg --batch --with-colons --show-keys "$KEYRING" | awk -F: '/^fpr/ { print $10; exit }')

mkdir -p "$SITE"
cp "$@" "$KEYRING" "$ROOT/packaging/apt/reverse-bin.sources" "$SITE/"
cd "$SITE"
rm -f InRelease Release Release.gpg
apt-ftparchive packages . > Packages
gzip -9nkf Packages
# unattended-upgrades selects this repository by Origin.
apt-ftparchive \
  -o APT::FTPArchive::Release::Origin=reverse-bin \
  -o APT::FTPArchive::Release::Label=reverse-bin \
  -o APT::FTPArchive::Release::Suite=stable \
  -o APT::FTPArchive::Release::Codename=stable \
  release . > "$GNUPGHOME/Release"
# Written elsewhere first so Release does not list a hash of itself.
mv "$GNUPGHOME/Release" Release
gpg --batch --yes --local-user "$fingerprint" --clearsign -o InRelease Release
gpg --batch --yes --local-user "$fingerprint" --armor --detach-sign -o Release.gpg Release
# Hosts verify with the shipped keyring; prove it accepts what was signed.
gpgv --keyring "$GNUPGHOME/keyring.gpg" InRelease 2>/dev/null
gpgv --keyring "$GNUPGHOME/keyring.gpg" Release.gpg Release 2>/dev/null
echo "signed apt repository in $SITE with $fingerprint"
