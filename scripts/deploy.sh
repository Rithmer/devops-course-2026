#!/usr/bin/env bash
set -euo pipefail

REMOTE="devops"
REMOTE_DIR="/var/www/devops-site"
SITE_URL="https://devops.local"
CA_CERT="${HOME}/devops.crt"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "${SCRIPT_DIR}/.." rev-parse --show-toplevel)"
LOCAL_DIR="${REPO_ROOT}/site/"
DRY_RUN=false

usage() {
    printf 'Usage: %s [--dry-run]\n' "${BASH_SOURCE[0]}" >&2
    exit 2
}

if (($# > 1)); then usage; fi
if (($# == 1)); then
    [[ "$1" == "--dry-run" ]] || usage
    DRY_RUN=true
fi

if [[ ! -f "${LOCAL_DIR}index.html" ]]; then
    printf 'Ошибка: отсутствует %sindex.html; доставка отменена.\n' "$LOCAL_DIR" >&2
    exit 1
fi

if [[ -n "$(git -C "$REPO_ROOT" status --porcelain --untracked-files=all)" ]]; then
    printf 'Ошибка: в репозитории есть незакоммиченные изменения; доставка отменена.\n' >&2
    exit 1
fi

RSYNC_ARGS=(-avz --delete --chmod=Du=rwx,Dgo=rx,Fu=rw,Fgo=r)
if [[ "$DRY_RUN" == true ]]; then
    RSYNC_ARGS+=(--dry-run)
fi

# One rsync process opens one SSH connection. BatchMode forbids password prompts.
rsync "${RSYNC_ARGS[@]}" -e 'ssh -o BatchMode=yes -o ConnectTimeout=5' \
    "$LOCAL_DIR" "${REMOTE}:${REMOTE_DIR}/"

if [[ "$DRY_RUN" == true ]]; then
    printf 'Пробный запуск завершён; состояние сервера не изменено.\n'
    exit 0
fi

CURL_ARGS=(--fail --silent --show-error --connect-timeout 5 --max-time 15
    --cacert "$CA_CERT" --output /dev/null)
HOST_IP="$(awk '$2 == "devops.local" { print $1; exit }' /etc/hosts 2>/dev/null || true)"
if [[ -n "$HOST_IP" ]]; then
    # On macOS, .local may be routed through mDNS despite an /etc/hosts entry.
    # --resolve keeps the URL/SNI hostname for certificate verification.
    CURL_ARGS+=(--noproxy '*' --resolve "devops.local:443:${HOST_IP}")
fi
if ! curl "${CURL_ARGS[@]}" "$SITE_URL"; then
    printf 'Ошибка: ресурс %s недоступен или сертификат не прошёл проверку.\n' "$SITE_URL" >&2
    exit 1
fi

printf 'Доставка успешна. Коммит: %s\n' "$(git -C "$REPO_ROOT" rev-parse --short HEAD)"
