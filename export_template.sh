#!/usr/bin/env bash

# 使用方法:
#   请把下面的占位值替换成你自己的真实配置。
#   mv export_template.sh export.sh
#   source ./export.sh

# ===== 必填：多吉云 API =====
export DOGE_ACCESS_KEY="请填写你的多吉云AccessKey"
export DOGE_SECRET_KEY="请填写你的多吉云SecretKey"

# ===== 申请证书模式必填：Cloudflare =====
# 仅在需要 acme.sh 申请证书时使用（不走 --upload-only / --upload-bind 时）
export CF_API_TOKEN="请填写你的CloudflareApiToken"

# ===== 绑定域名（绑定模式必填） =====
# 逗号分隔，示例: cdn1.example.com,cdn2.example.com
export BIND_DOMAINS="请填写要绑定的域名列表，多个域名用英文逗号隔开"

# ===== 建议填写 =====
export LETSENCRYPT_EMAIL="请填写你的真实邮箱"

# 默认主域名（申请模式下使用）
export DOMAIN_ROOT="example.com"

# 输出目录（默认当前目录）
# export OUTPUT_DIR="$PWD"

# 证书备注（上传到多吉云时显示）
# export DOGE_CERT_NOTE="LE-example.com-$(date +%F)"

# 申请测试环境（true/false），建议联调时使用 true
# export USE_STAGING="false"

# Cloudflare 可选参数
# export CF_ZONE_ID=""
# export CF_ACCOUNT_ID=""
