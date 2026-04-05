#!/usr/bin/env bash
set -Eeuo pipefail

# 自动化流程：
# 1) 使用 Let's Encrypt + Cloudflare DNS-01 申请证书（含 *.DOMAIN_ROOT）
# 2) 将证书导出到 OUTPUT_DIR（默认当前目录）
# 3) 上传证书到多吉云
# 4) 绑定证书到指定 CDN 域名（可多个）

log() {
  echo "[$(date '+%F %T')] $*"
}

die() {
  echo "[ERROR] $*" >&2
  exit 1
}

warn() {
  echo "[WARN] $*" >&2
}

require_env() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    die "缺少环境变量: ${name}"
  fi
}

require_cmd() {
  local c="$1"
  command -v "$c" >/dev/null 2>&1 || die "缺少命令: ${c}"
}

trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

json_get() {
  local expr="$1"
  local raw_json="${2:-}"
  python3 - "$expr" "$raw_json" <<'PY'
import json
import sys

expr = sys.argv[1]
raw_json = sys.argv[2]

if not raw_json.strip():
    print("")
    sys.exit(0)

try:
    data = json.loads(raw_json)
except json.JSONDecodeError:
    print("")
    sys.exit(0)

# 支持简单点路径，如: code / msg / data.id
cur = data
for part in expr.split('.'):
    if isinstance(cur, dict):
        cur = cur.get(part)
    else:
        cur = None
        break

if cur is None:
    print("")
elif isinstance(cur, (dict, list)):
    print(json.dumps(cur, ensure_ascii=False))
else:
    print(cur)
PY
}

form_encode_from_files() {
  local note="$1"
  local cert_file="$2"
  local key_file="$3"
  python3 - "$note" "$cert_file" "$key_file" <<'PY'
import pathlib
import sys
import urllib.parse

note, cert_file, key_file = sys.argv[1:]
cert = pathlib.Path(cert_file).read_text(encoding='utf-8')
priv = pathlib.Path(key_file).read_text(encoding='utf-8')
print(urllib.parse.urlencode({
    'note': note,
    'cert': cert,
    'private': priv,
}))
PY
}

form_encode_bind() {
  local cert_id="$1"
  local domain="$2"
  python3 - "$cert_id" "$domain" <<'PY'
import sys
import urllib.parse
cert_id, domain = sys.argv[1:]
print(urllib.parse.urlencode({'id': cert_id, 'domain': domain}))
PY
}

json_list_unbound_cert_ids() {
  local raw_json="${1:-}"
  local exclude_id="${2:-}"
  python3 - "$raw_json" "$exclude_id" <<'PY'
import json
import sys

raw_json = sys.argv[1]
exclude_id = sys.argv[2].strip()

if not raw_json.strip():
  sys.exit(0)

try:
  data = json.loads(raw_json)
except json.JSONDecodeError:
  sys.exit(0)

certs = ((data.get('data') or {}).get('certs') or [])

for cert in certs:
  cert_id = cert.get('id')
  if cert_id is None:
    continue
  if exclude_id and str(cert_id) == exclude_id:
    continue

  domain_count = cert.get('domainCount')
  domains = cert.get('domains')

  # 以 domainCount 为主，domains 作为兜底
  if isinstance(domain_count, int):
    unbound = (domain_count == 0)
  else:
    unbound = not domains

  if unbound:
    print(cert_id)
PY
}

doge_sign() {
  local api_path="$1"
  local body="$2"
  local sign_str
  sign_str="${api_path}"$'\n'"${body}"

  printf '%s' "$sign_str" \
    | openssl dgst -sha1 -hmac "$DOGE_SECRET_KEY" -hex \
    | awk '{print $2}'
}

doge_post_form() {
  local api_path="$1"
  local body="$2"

  local sign
  sign="$(doge_sign "$api_path" "$body")"

  curl -fsS "https://api.dogecloud.com${api_path}" \
    -H "Authorization: TOKEN ${DOGE_ACCESS_KEY}:${sign}" \
    -H 'Content-Type: application/x-www-form-urlencoded' \
    --data "$body"
}

doge_get() {
  local api_path="$1"

  local sign
  sign="$(doge_sign "$api_path" "")"

  curl -fsS "https://api.dogecloud.com${api_path}" \
    -H "Authorization: TOKEN ${DOGE_ACCESS_KEY}:${sign}"
}

# ===== 配置项（环境变量） =====
DOMAIN_ROOT="${DOMAIN_ROOT:-example.com}"
OUTPUT_DIR="${OUTPUT_DIR:-$PWD}"
LETSENCRYPT_EMAIL="${LETSENCRYPT_EMAIL:-admin@${DOMAIN_ROOT}}"
DOGE_CERT_NOTE="${DOGE_CERT_NOTE:-LE-${DOMAIN_ROOT}-$(date +%F)}"

CERT_FILE="${CERT_FILE:-${OUTPUT_DIR}/${DOMAIN_ROOT}.cer}"
KEY_FILE="${KEY_FILE:-${OUTPUT_DIR}/${DOMAIN_ROOT}.key}"
CA_FILE="${CA_FILE:-${OUTPUT_DIR}/${DOMAIN_ROOT}.ca.cer}"
FULLCHAIN_FILE="${FULLCHAIN_FILE:-${OUTPUT_DIR}/${DOMAIN_ROOT}.fullchain.pem}"

# 需要绑定到多吉云 CDN 的域名，多个用英文逗号分隔
# 示例: BIND_DOMAINS="cdn.example.com,static.example.com"
BIND_DOMAINS="${BIND_DOMAINS:-}"

# 可选：测试环境，true 时使用 Let's Encrypt staging
USE_STAGING="${USE_STAGING:-false}"

# 可选：强制续签，true 时给 acme.sh 追加 --force
FORCE_RENEW="${FORCE_RENEW:-false}"

# 可选：仅上传本地证书，不执行申请/导出/绑定
UPLOAD_ONLY="${UPLOAD_ONLY:-false}"

# 是否执行绑定步骤
DO_BIND="${DO_BIND:-true}"

# 是否在上传并绑定后自动删除未绑定旧证书
AUTO_DELETE_OLD="${AUTO_DELETE_OLD:-false}"

# 可选：中国大陆网络环境下从 Gitee 安装 acme.sh
ACME_CN_INSTALL="${ACME_CN_INSTALL:-false}"

# 命令行补充绑定域名（可多次传入 --bind-domain）
BIND_DOMAINS_CLI=""

# ===== 命令行参数 =====
while [[ $# -gt 0 ]]; do
  case "$1" in
    --force)
      FORCE_RENEW="true"
      shift
      ;;
    --upload-only)
      UPLOAD_ONLY="true"
      DO_BIND="false"
      shift
      ;;
    --upload-bind)
      # 本地证书直传并绑定：跳过 acme 申请，保留绑定
      UPLOAD_ONLY="true"
      DO_BIND="true"
      shift
      ;;
    --auto-delete-old)
      AUTO_DELETE_OLD="true"
      shift
      ;;
    --acme-cn)
      ACME_CN_INSTALL="true"
      shift
      ;;
    --cert-file)
      [[ $# -ge 2 ]] || die "参数 --cert-file 需要文件路径"
      FULLCHAIN_FILE="$2"
      shift 2
      ;;
    --key-file)
      [[ $# -ge 2 ]] || die "参数 --key-file 需要文件路径"
      KEY_FILE="$2"
      shift 2
      ;;
    --bind-domains)
      [[ $# -ge 2 ]] || die "参数 --bind-domains 需要逗号分隔的域名列表"
      BIND_DOMAINS="$2"
      shift 2
      ;;
    --bind-domain)
      [[ $# -ge 2 ]] || die "参数 --bind-domain 需要一个域名"
      if [[ -n "$BIND_DOMAINS_CLI" ]]; then
        BIND_DOMAINS_CLI+=",$2"
      else
        BIND_DOMAINS_CLI="$2"
      fi
      shift 2
      ;;
    -h|--help)
      cat <<'EOF'
用法:
  ./auto_cert_bind.sh [--force]
  ./auto_cert_bind.sh --upload-only --cert-file /path/fullchain.pem --key-file /path/private.key
  ./auto_cert_bind.sh --upload-bind --cert-file /path/fullchain.pem --key-file /path/private.key --bind-domains a.com,b.com [--auto-delete-old]
  ./auto_cert_bind.sh --acme-cn

参数:
  --force        传递给 acme.sh 的 --force，用于强制续签
  --upload-only  直接上传本地证书到多吉云，跳过 acme.sh 申请与导出，不绑定
  --upload-bind  直接上传本地证书并绑定域名（用于测试上传+绑定）
  --cert-file    指定证书链文件（fullchain.pem）路径
  --key-file     指定私钥文件（.key）路径
  --bind-domains 指定逗号分隔的绑定域名列表
  --bind-domain  指定单个绑定域名，可多次传入
  --auto-delete-old  上传并绑定成功后，自动删除未绑定任何域名的旧证书
  --acme-cn      当无法访问 GitHub 时，从 Gitee 安装 acme.sh（需提供真实邮箱 LETSENCRYPT_EMAIL）
EOF
      exit 0
      ;;
    *)
      die "未知参数: $1"
      ;;
  esac
done

if [[ -n "$BIND_DOMAINS_CLI" ]]; then
  if [[ -n "$BIND_DOMAINS" ]]; then
    BIND_DOMAINS+="${BIND_DOMAINS:+,}${BIND_DOMAINS_CLI}"
  else
    BIND_DOMAINS="$BIND_DOMAINS_CLI"
  fi
fi

# ===== 参数校验 =====
require_env DOGE_ACCESS_KEY
require_env DOGE_SECRET_KEY

if [[ "$UPLOAD_ONLY" != "true" ]]; then
  require_env CF_API_TOKEN
fi

if [[ "$DO_BIND" == "true" ]]; then
  require_env BIND_DOMAINS
fi

if [[ "$AUTO_DELETE_OLD" == "true" && "$DO_BIND" != "true" ]]; then
  die "--auto-delete-old 需要在绑定流程下使用（请使用默认流程或 --upload-bind）"
fi

require_cmd curl
require_cmd openssl
require_cmd python3

mkdir -p "$OUTPUT_DIR"

if [[ "$UPLOAD_ONLY" == "true" ]]; then
  log "已启用 --upload-only，跳过证书申请与导出步骤。"
else
  # ===== 安装/定位 acme.sh =====
  ACME_SH="${HOME}/.acme.sh/acme.sh"
  if [[ ! -x "$ACME_SH" ]]; then
    if [[ "$ACME_CN_INSTALL" == "true" ]]; then
      require_cmd git

      [[ -n "$LETSENCRYPT_EMAIL" ]] || die "使用 --acme-cn 时请提供真实邮箱 LETSENCRYPT_EMAIL"
      if [[ "$LETSENCRYPT_EMAIL" == *"example.com"* ]]; then
        die "使用 --acme-cn 时 LETSENCRYPT_EMAIL 不能是 example.com，请设置真实邮箱"
      fi

      # 按中国大陆可访问流程安装：
      # git clone https://gitee.com/neilpang/acme.sh.git
      # cd acme.sh
      # ./acme.sh --install -m my@example.com
      ACME_TMP_DIR="$(mktemp -d)"
      log "未检测到 acme.sh，使用 Gitee 镜像安装..."
      git clone https://gitee.com/neilpang/acme.sh.git "$ACME_TMP_DIR/acme.sh"
      (
        cd "$ACME_TMP_DIR/acme.sh"
        ./acme.sh --install -m "$LETSENCRYPT_EMAIL"
      )
      rm -rf "$ACME_TMP_DIR"
    else
      warn "如果中国大陆网络无法访问 GitHub，请使用参数 --acme-cn 从 Gitee 安装 acme.sh。"
      log "未检测到 acme.sh，开始安装..."
      curl -fsSL https://get.acme.sh | sh -s email="$LETSENCRYPT_EMAIL"
    fi
  fi

  [[ -x "$ACME_SH" ]] || die "acme.sh 安装失败，请手动检查。"

  # ===== 申请证书（DNS-01） =====
  # acme.sh 的 dns_cf 插件会自动在 Cloudflare 创建/删除 _acme-challenge TXT 记录。
  export CF_Token="$CF_API_TOKEN"
  [[ -n "${CF_ZONE_ID:-}" ]] && export CF_Zone_ID="$CF_ZONE_ID"
  [[ -n "${CF_ACCOUNT_ID:-}" ]] && export CF_Account_ID="$CF_ACCOUNT_ID"

  ISSUE_ARGS=(
    --issue
    --dns dns_cf
    -d "$DOMAIN_ROOT"
    -d "*.${DOMAIN_ROOT}"
    --server letsencrypt
  )

  if [[ "$FORCE_RENEW" == "true" ]]; then
    ISSUE_ARGS+=(--force)
  fi

  if [[ "$USE_STAGING" == "true" ]]; then
    ISSUE_ARGS+=(--staging)
  fi

  log "开始申请 Let's Encrypt 证书: *.${DOMAIN_ROOT}"
  "$ACME_SH" "${ISSUE_ARGS[@]}"

  # ===== 导出证书到当前目录 =====
  "$ACME_SH" --install-cert -d "$DOMAIN_ROOT" \
    --cert-file "$CERT_FILE" \
    --key-file "$KEY_FILE" \
    --ca-file "$CA_FILE" \
    --fullchain-file "$FULLCHAIN_FILE"

  log "证书已导出到: ${OUTPUT_DIR}"
fi

[[ -f "$FULLCHAIN_FILE" ]] || die "证书文件不存在: $FULLCHAIN_FILE"
[[ -f "$KEY_FILE" ]] || die "私钥文件不存在: $KEY_FILE"

# ===== 上传到多吉云 =====
UPLOAD_API="/cdn/cert/upload.json"
UPLOAD_BODY="$(form_encode_from_files "$DOGE_CERT_NOTE" "$FULLCHAIN_FILE" "$KEY_FILE")"

log "上传证书到多吉云..."
UPLOAD_RESP="$(doge_post_form "$UPLOAD_API" "$UPLOAD_BODY")"

if [[ -z "$UPLOAD_RESP" ]]; then
  die "证书上传失败：接口返回为空"
fi

UPLOAD_CODE="$(json_get 'code' "$UPLOAD_RESP")"
UPLOAD_MSG="$(json_get 'msg' "$UPLOAD_RESP")"
CERT_ID="$(json_get 'data.id' "$UPLOAD_RESP")"

if [[ "$UPLOAD_CODE" != "200" || -z "$CERT_ID" ]]; then
  echo "$UPLOAD_RESP"
  die "证书上传失败，返回可能不是合法 JSON 或 code 非 200。code=${UPLOAD_CODE}, msg=${UPLOAD_MSG}"
fi

log "多吉云证书上传成功，证书 ID: ${CERT_ID}"

if [[ "$DO_BIND" != "true" ]]; then
  log "已跳过绑定步骤（DO_BIND=false）"
  log "证书文件:"
  log "  - ${FULLCHAIN_FILE}"
  log "  - ${KEY_FILE}"
  exit 0
fi

# ===== 绑定证书 =====
BIND_API="/cdn/cert/bind.json"
IFS=',' read -r -a DOMAIN_ARR <<< "$BIND_DOMAINS"

for raw_domain in "${DOMAIN_ARR[@]}"; do
  domain="$(trim "$raw_domain")"
  [[ -n "$domain" ]] || continue

  BIND_BODY="$(form_encode_bind "$CERT_ID" "$domain")"
  log "绑定证书到域名: ${domain}"

  BIND_RESP="$(doge_post_form "$BIND_API" "$BIND_BODY")"

  if [[ -z "$BIND_RESP" ]]; then
    die "绑定失败: domain=${domain}, 接口返回为空"
  fi

  BIND_CODE="$(json_get 'code' "$BIND_RESP")"
  BIND_MSG="$(json_get 'msg' "$BIND_RESP")"

  if [[ "$BIND_CODE" != "200" ]]; then
    echo "$BIND_RESP"
    die "绑定失败: domain=${domain}, code=${BIND_CODE}, msg=${BIND_MSG}"
  fi

done

if [[ "$AUTO_DELETE_OLD" == "true" ]]; then
  log "开始自动清理未绑定旧证书..."

  LIST_API="/cdn/cert/list.json"
  LIST_RESP="$(doge_get "$LIST_API")"

  if [[ -z "$LIST_RESP" ]]; then
    die "拉取证书列表失败：接口返回为空"
  fi

  LIST_CODE="$(json_get 'code' "$LIST_RESP")"
  LIST_MSG="$(json_get 'msg' "$LIST_RESP")"
  if [[ "$LIST_CODE" != "200" ]]; then
    echo "$LIST_RESP"
    die "拉取证书列表失败，code=${LIST_CODE}, msg=${LIST_MSG}"
  fi

  mapfile -t OLD_CERT_IDS < <(json_list_unbound_cert_ids "$LIST_RESP" "$CERT_ID")

  if [[ ${#OLD_CERT_IDS[@]} -eq 0 ]]; then
    log "未发现可删除的未绑定证书。"
  else
    DELETE_API="/cdn/cert/delete.json"
    deleted_count=0
    failed_count=0

    for old_id in "${OLD_CERT_IDS[@]}"; do
      old_id="$(trim "$old_id")"
      [[ -n "$old_id" ]] || continue

      log "删除未绑定证书: id=${old_id}"
      DELETE_RESP="$(doge_post_form "$DELETE_API" "id=${old_id}")"

      if [[ -z "$DELETE_RESP" ]]; then
        warn "删除失败（空响应）: id=${old_id}"
        failed_count=$((failed_count + 1))
        continue
      fi

      DELETE_CODE="$(json_get 'code' "$DELETE_RESP")"
      DELETE_MSG="$(json_get 'msg' "$DELETE_RESP")"

      if [[ "$DELETE_CODE" == "200" ]]; then
        deleted_count=$((deleted_count + 1))
      else
        warn "删除失败: id=${old_id}, code=${DELETE_CODE}, msg=${DELETE_MSG}"
        failed_count=$((failed_count + 1))
      fi
    done

    log "自动清理结束：成功删除 ${deleted_count} 个，失败 ${failed_count} 个。"
  fi
fi

log "全部完成。证书 ID: ${CERT_ID}"
log "证书文件:"
log "  - ${FULLCHAIN_FILE}"
log "  - ${KEY_FILE}"
