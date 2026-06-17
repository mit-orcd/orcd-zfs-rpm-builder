#!/usr/bin/env bash
#
# Publish locally built OpenZFS RPMs to the ORCD yum repository.
#
# Example (run on the repo/build server as root):
#   sudo ./scripts/publish-zfs-repo.sh 2.4.3
#
# Clients can use baseurl=.../zfs-orcd-repo/current/ to always track the latest
# published version, or .../zfs-orcd-repo/v2.4.3/ for a fixed release.

set -euo pipefail

usage() {
    cat <<'EOF'
Usage: publish-zfs-repo.sh <zfs-version>

Publish RPMs from a local GitHub Actions build tree into the ORCD repo.

Arguments:
  zfs-version   OpenZFS version, e.g. 2.4.3 or v2.4.3

Environment overrides:
  ZFS_RUNNER_WORK_ROOT   Actions runner work directory for this repo
                         (default: /home/ec2-user/actions-runner/_work/orcd-zfs-rpm-builder/orcd-zfs-rpm-builder)
  ZFS_REPO_ROOT          Repository root on disk
                         (default: /var/www/html/zfs-orcd-repo)
  ZFS_INCLUDE_SRC_RPMS   Set to 1 to include *.src.rpm in the repo (default: 0)

Example:
  sudo ./scripts/publish-zfs-repo.sh 2.4.3
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

if [[ $# -ne 1 ]]; then
    usage >&2
    exit 1
fi

if [[ "$(id -u)" -ne 0 ]]; then
    echo "error: run as root (repo path and metadata require elevated privileges)" >&2
    exit 1
fi

ZFS_VERSION="${1#v}"
if [[ ! "${ZFS_VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "error: invalid zfs version '${1}' (expected form like 2.4.3)" >&2
    exit 1
fi

RELEASE_TAG="v${ZFS_VERSION}"
RUNNER_WORK_ROOT="${ZFS_RUNNER_WORK_ROOT:-/home/ec2-user/actions-runner/_work/orcd-zfs-rpm-builder/orcd-zfs-rpm-builder}"
SOURCE_DIR="${RUNNER_WORK_ROOT}/zfs-${ZFS_VERSION}"
REPO_ROOT="${ZFS_REPO_ROOT:-/var/www/html/zfs-orcd-repo}"
VERSION_DIR="${REPO_ROOT}/${RELEASE_TAG}"
CURRENT_LINK="${REPO_ROOT}/current"
INCLUDE_SRC_RPMS="${ZFS_INCLUDE_SRC_RPMS:-0}"

if [[ ! -d "${SOURCE_DIR}" ]]; then
    echo "error: build directory not found: ${SOURCE_DIR}" >&2
    exit 1
fi

mapfile -t RPM_FILES < <(
    if [[ "${INCLUDE_SRC_RPMS}" == "1" ]]; then
        find "${SOURCE_DIR}" -type f -name '*.rpm' | sort
    else
        find "${SOURCE_DIR}" -type f -name '*.rpm' ! -name '*.src.rpm' | sort
    fi
)

if [[ "${#RPM_FILES[@]}" -eq 0 ]]; then
    echo "error: no RPM files found under ${SOURCE_DIR}" >&2
    exit 1
fi

echo "Publishing OpenZFS ${ZFS_VERSION} (${#RPM_FILES[@]} RPMs)"
echo "  source:  ${SOURCE_DIR}"
echo "  target:  ${VERSION_DIR}"

install -d -m 755 "${REPO_ROOT}" "${VERSION_DIR}"

echo "Copying RPMs..."
for rpm in "${RPM_FILES[@]}"; do
    install -m 644 "${rpm}" "${VERSION_DIR}/$(basename "${rpm}")"
done

echo "Setting permissions..."
find "${VERSION_DIR}" -type d -exec chmod 755 {} +
find "${VERSION_DIR}" -type f -exec chmod 644 {} +

echo "Generating repository metadata..."
if ! command -v createrepo_c >/dev/null 2>&1; then
    echo "error: createrepo_c not found; install with: dnf install -y createrepo_c" >&2
    exit 1
fi
createrepo_c --update "${VERSION_DIR}"

echo "Updating current -> ${RELEASE_TAG}"
ln -sfn "${RELEASE_TAG}" "${CURRENT_LINK}"

if command -v restorecon >/dev/null 2>&1; then
    echo "Applying SELinux context..."
    if command -v semanage >/dev/null 2>&1; then
        semanage fcontext -a -t httpd_sys_content_t "${REPO_ROOT}(/.*)?" 2>/dev/null \
            || semanage fcontext -m -t httpd_sys_content_t "${REPO_ROOT}(/.*)?" 2>/dev/null \
            || true
    fi
    restorecon -RF "${REPO_ROOT}"
fi

INDEX_FILE="${REPO_ROOT}/index.html"
CURRENT_TARGET="$(readlink "${CURRENT_LINK}" || true)"
GENERATED_AT="$(date -u '+%Y-%m-%d %H:%M:%S UTC')"

{
    cat <<EOF
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>ORCD ZFS RPM Repository</title>
  <style>
    body { font-family: sans-serif; margin: 2rem; }
    table { border-collapse: collapse; }
    th, td { border: 1px solid #ccc; padding: 0.5rem 1rem; text-align: left; }
    th { background: #f5f5f5; }
  </style>
</head>
<body>
  <h1>ORCD ZFS RPM Repository</h1>
  <p>Generated: ${GENERATED_AT}</p>
  <p><strong>current</strong> points to <code>${CURRENT_TARGET:-unknown}</code></p>
  <p>Client baseurl example: <code>https://orcd-repo.mit-orcd-aws.org/zfs-orcd-repo/current/</code></p>
  <h2>Available versions</h2>
  <table>
    <thead>
      <tr><th>Version</th><th>Repository path</th></tr>
    </thead>
    <tbody>
EOF

    mapfile -t VERSION_DIRS < <(
        find "${REPO_ROOT}" -mindepth 1 -maxdepth 1 -type d -name 'v*' -printf '%f\n' | sort -V
    )

    for tag in "${VERSION_DIRS[@]}"; do
        marker=""
        if [[ "${tag}" == "${CURRENT_TARGET}" ]]; then
            marker=" (current)"
        fi
        printf '      <tr><td>%s%s</td><td><a href="%s/">%s/</a></td></tr>\n' \
            "${tag}" "${marker}" "${tag}" "${tag}"
    done

    cat <<EOF
      <tr><td>current (symlink)</td><td><a href="current/">current/</a></td></tr>
    </tbody>
  </table>
</body>
</html>
EOF
} > "${INDEX_FILE}"
chmod 644 "${INDEX_FILE}"

echo
echo "Publish complete."
echo "  version repo: ${VERSION_DIR}/"
echo "  current link: ${CURRENT_LINK} -> $(readlink "${CURRENT_LINK}")"
echo "  index:        ${INDEX_FILE}"
echo
echo "Verify:"
echo "  curl -sI http://127.0.0.1/zfs-orcd-repo/current/repodata/repomd.xml"
echo "  curl -sI http://127.0.0.1/zfs-orcd-repo/${RELEASE_TAG}/repodata/repomd.xml"
