# auto_cert_bind.sh 使用说明

## 这个脚本能做什么

本脚本用于自动化管理多吉云 CDN 证书，支持以下能力：

1. 使用 Let's Encrypt + Cloudflare DNS Challenge 申请证书（支持通配符）。
2. 把证书导出到本地文件。
3. 上传证书到多吉云 CDN。
4. 将证书绑定到一个或多个 CDN 域名。
5. 可选：在上传并绑定新证书后，自动删除未绑定任何域名的旧证书。
6. 可选：中国大陆网络场景下，通过 Gitee 安装 acme.sh。

## 你需要准备的信息

### 必填（所有模式都要）

1. DOGE_ACCESS_KEY：多吉云 AccessKey。
2. DOGE_SECRET_KEY：多吉云 SecretKey。

### 申请证书模式必填

1. CF_API_TOKEN：Cloudflare API Token（用于 DNS Challenge）。

### 绑定模式必填

1. BIND_DOMAINS：要绑定的域名列表，逗号分隔。

### 建议填写

1. LETSENCRYPT_EMAIL：真实邮箱。尤其在首次注册 ACME 账号、或使用 --acme-cn 安装时建议显式提供。
2. DOMAIN_ROOT：主域名，默认是 vrxiaojie.top。

## 快速开始

### 1) 填写环境变量

先编辑 export.sh，把占位值改成你自己的，然后执行：
```sh
mv export_template.sh export.sh
source ./export.sh
```

### 2) 常用命令

1. 全流程（申请 + 上传 + 绑定）：

```sh
./auto_cert_bind.sh
```

2. 强制续签后再上传绑定：
```sh
./auto_cert_bind.sh --force
```

3. 本地证书仅上传（不绑定）：
```sh
./auto_cert_bind.sh --upload-only --cert-file /path/fullchain.pem --key-file /path/private.key
```

4. 本地证书上传并绑定（推荐测试上传+绑定）：
```sh
./auto_cert_bind.sh --upload-bind --cert-file /path/fullchain.pem --key-file /path/private.key --bind-domains a.example.com,b.example.com
```

5. 本地证书上传并绑定，同时自动删除未绑定旧证书：
```sh
./auto_cert_bind.sh --upload-bind --cert-file /path/fullchain.pem --key-file /path/private.key --bind-domains a.example.com,b.example.com --auto-delete-old
```

6. 中国大陆网络下安装 acme.sh：
```sh
./auto_cert_bind.sh --acme-cn
```

## 中国大陆网络说明（acme.sh 安装）

当本机没有 acme.sh 且访问 GitHub 不稳定时，可加 --acme-cn。

**注意：** 邮箱必须是真实可用邮箱，需在export.sh中修改，不要用 example.com。

## 参数一览

1. --force：给 acme.sh 增加 --force，强制续签。
2. --upload-only：只上传本地证书，不绑定。
3. --upload-bind：上传本地证书并绑定域名。
4. --cert-file：指定证书链文件路径（fullchain.pem）。
5. --key-file：指定私钥文件路径（.key）。
6. --bind-domains：逗号分隔域名列表。
7. --bind-domain：单个域名，可重复传多次。
8. --auto-delete-old：上传并绑定成功后，删除未绑定旧证书。
9. --acme-cn：使用 Gitee 安装 acme.sh。

