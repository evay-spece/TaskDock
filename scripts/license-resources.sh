#!/bin/zsh

# Shared by local installation and release packaging. Copy only public assets.
taskdock_verify_license_resources() {
  local project_root="$1" app_path="$2"
  local resource_name
  for resource_name in Billing.plist license-public-key.pem payment-alipay.jpg payment-wechat.jpg; do
    [[ -f "$project_root/Sources/TaskDock/Resources/$resource_name" &&
       -f "$app_path/Contents/Resources/$resource_name" ]] || {
      echo "缺少离线授权资源：$resource_name" >&2; return 1
    }
    cmp "$project_root/Sources/TaskDock/Resources/$resource_name" \
      "$app_path/Contents/Resources/$resource_name" || return 1
  done
  local support_email
  support_email="$(/usr/bin/plutil -extract SupportEmail raw -o - "$app_path/Contents/Resources/Billing.plist")" || return 1
  [[ "$support_email" == '53803736@qq.com' ]] || {
    echo '客服邮箱与发布配置不一致' >&2; return 1
  }
  if /usr/bin/grep -q -- '-----BEGIN RSA PUBLIC KEY-----' "$app_path/Contents/Resources/license-public-key.pem"; then
    /usr/bin/openssl rsa -RSAPublicKey_in -in "$app_path/Contents/Resources/license-public-key.pem" -noout || return 1
  else
    /usr/bin/openssl pkey -pubin -in "$app_path/Contents/Resources/license-public-key.pem" -noout || return 1
  fi
  if /usr/bin/grep -R -a -q -E -- '-----BEGIN ([A-Z0-9]+ )*PRIVATE KEY-----' "$app_path/Contents"; then
    echo '安装包中发现私钥，停止交付' >&2; return 1
  fi
}

taskdock_copy_license_resources() {
  local project_root="$1" app_path="$2"
  local resource_name
  mkdir -p "$app_path/Contents/Resources" || return 1
  for resource_name in Billing.plist license-public-key.pem payment-alipay.jpg payment-wechat.jpg; do
    [[ -f "$project_root/Sources/TaskDock/Resources/$resource_name" ]] || {
      echo "缺少离线授权资源：$resource_name" >&2; return 1
    }
    cp "$project_root/Sources/TaskDock/Resources/$resource_name" \
      "$app_path/Contents/Resources/$resource_name" || return 1
  done
  taskdock_verify_license_resources "$project_root" "$app_path"
}
