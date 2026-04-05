#!/usr/bin/env sh
set -eu

EMAIL="${ACME_INSTALL_EMAIL:-${LETSENCRYPT_EMAIL:-}}"

if [ ! -x "${HOME}/.acme.sh/acme.sh" ]; then
  if [ -z "$EMAIL" ]; then
    echo "[ERROR] 首次启动需要设置 ACME_INSTALL_EMAIL 或 LETSENCRYPT_EMAIL，用于 acme.sh --install -m" >&2
    exit 1
  fi

  cd /opt/acme.sh
  ./acme.sh --install -m "$EMAIL" --no-cron --no-profile
fi

exec /usr/local/bin/auto_cert_bind.sh "$@"
