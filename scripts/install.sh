#!/usr/bin/env bash
#
# lucky (Lucky 万吉) - Linux 一键安装脚本
#
# 作用：从 GitHub Releases 下载对应架构的预编译二进制（单文件，前端已内嵌），
#       安装为 systemd 服务。可重复执行，升级 = 覆盖二进制并重启服务，配置保留。
#
# 用法：
#   远程一键安装（默认端口 16601）：
#     bash -c "$(curl -sSL https://raw.githubusercontent.com/meimolihan/lucky/master/scripts/install.sh)" -p 16601
#   本地执行：
#     bash scripts/install.sh -p 16601
#     bash scripts/install.sh -p 16601 -d /etc/lucky -v v2.28.2 -y
#
# 参数：
#   -p, --port      管理后台监听端口（默认 16601）
#   -d, --dir       安装目录（默认 /etc/lucky，内含 lucky 与 lucky.conf）
#   -v, --version   指定版本，如 v2.28.2（默认 latest）
#   -y, --yes       免交互，未指定项全部使用默认值
#   -h, --help      显示帮助
#
# 环境变量：
#   LUCKY_VERSION       同 -v
#   LUCKY_ASSET         强制指定资产后缀，如 Linux_armv5 / Linux_mipsle_hardfloat
#   LUCKY_MIPS_FLOAT    mips 架构浮点类型：hardfloat / softfloat
#   LUCKY_REPO          仓库，默认 meimolihan/lucky
#   LUCKY_PKG           离线安装包路径（内网/离线环境），指定后不再联网下载
#
# 注意（lucky 自身的端口机制）：
#   main.go 中 -p 只在配置文件【不存在或读取失败】时生效；配置文件存在时以
#   lucky.conf 内的 BaseConfigure.AdminWebListenPort 为准。
#   因此本脚本：首次安装靠 -p 生成配置；重装时若传了 -p，则直接改写 lucky.conf。
#
set -euo pipefail

# ===================== 终端配色 =====================
list_color_init() {
    export gl_hui=$'\033[38;5;59m'
    export gl_hong=$'\033[38;5;9m'
    export gl_lv=$'\033[38;5;10m'
    export gl_huang=$'\033[38;5;11m'
    export gl_lan=$'\033[38;5;32m'
    export gl_bai=$'\033[38;5;15m'
    export gl_zi=$'\033[38;5;13m'
    export gl_bufan=$'\033[38;5;14m'
    export reset=$'\033[0m'
}
list_color_init

sep_line() {
  printf '%s' "$gl_bufan"
  printf '—%.0s' {1..46}
  printf '%s\n' "$reset"
}

section() { printf "  %s %s\n" "${gl_zi}▶${reset}" "$1"; }
ok()      { printf "  %s %s\n" "${gl_lv}>>>${reset}" "$1"; }
skip()    { printf "  %s %s\n" "${gl_hui}--${reset}" "$1"; }
warn()    { printf "  %s %s\n" "${gl_huang}[提示]${reset}" "$1"; }
error()   { printf "  %s %s\n" "${gl_hong}[错误]${reset}" "$1" >&2; exit 1; }

print_banner() {
  local z="$gl_zi" r="$reset" b="$gl_bai" l="$gl_lan"
  printf '%s\n' \
    "" \
    "  ${z}┌─────────────────────────────────────────────┐${r}" \
    "  ${z}│${r}   ${b}lucky${r}  ${l}万吉 · 端口转发 / DDNS / 反代${r}      ${z}│${r}" \
    "  ${z}└─────────────────────────────────────────────┘${r}" \
    ""
}

# ===================== 常量 =====================
APP_NAME="lucky"
DEFAULT_PORT=16601
DEFAULT_INSTALL_DIR="/etc/lucky"
GITHUB_REPO="${LUCKY_REPO:-meimolihan/lucky}"
# 解析 latest 失败时的兜底版本（保证安装不因网络问题中断）
FALLBACK_VERSION="2.28.2"

PORT=""
INSTALL_DIR=""
WANT_VERSION="${LUCKY_VERSION:-}"
INSTALL_YES=0

# ===================== GitHub 下载加速镜像 =====================
# 原始 GitHub 地址失败时按序尝试（末尾必须带斜杠）
GITHUB_MIRRORS=(
  "https://ghfast.top/"
  "https://ghproxy.net/"
  "https://gh.xxooo.cf/"
  "https://v6.gh-proxy.org/"
  "https://githubproxy.cc/"
)
# v6.gh-proxy.org 为纯 IPv6 代理：本机无 IPv6 时剔除，避免每次空等超时
if [ ! -s /proc/net/if_inet6 ] 2>/dev/null; then
  _no_v6=()
  for _m in "${GITHUB_MIRRORS[@]}"; do
    case "${_m}" in *v6.gh-proxy.org*) continue ;; esac
    _no_v6+=("${_m}")
  done
  GITHUB_MIRRORS=("${_no_v6[@]}")
fi

# 仓库根地址候选（原始 + 各镜像），末尾带斜杠
make_url_bases() {
  printf 'https://github.com/%s/\n' "${GITHUB_REPO}"
  local p
  for p in "${GITHUB_MIRRORS[@]}"; do
    printf '%shttps://github.com/%s/\n' "${p}" "${GITHUB_REPO}"
  done
}

# 完整 URL 候选（原始 + 各镜像前缀）
make_url_candidates() {
  local github_url="$1" p
  printf '%s\n' "${github_url}"
  for p in "${GITHUB_MIRRORS[@]}"; do
    printf '%s\n' "${p}${github_url}"
  done
}

# ===================== 参数解析 =====================
# 支持 `bash -c "$(curl ...)" -p 16601`：此时 $0 = "-p"，需并回参数列表
case "$0" in
  -*) set -- "$0" "$@" ;;
esac

while [ "$#" -gt 0 ]; do
  case "$1" in
    -p|--port)
      shift
      [ -n "${1:-}" ] || error "缺少 -p/--port 的值"
      PORT="$1"
      ;;
    -d|--dir)
      shift
      [ -n "${1:-}" ] || error "缺少 -d/--dir 的值"
      INSTALL_DIR="$1"
      ;;
    -v|--version)
      shift
      [ -n "${1:-}" ] || error "缺少 -v/--version 的值"
      WANT_VERSION="$1"
      ;;
    -y|--yes)
      INSTALL_YES=1
      ;;
    -h|--help)
      printf "%s\n" "${gl_lan}lucky${reset} - ${gl_bai}端口转发 / DDNS / 反向代理 网络工具 安装脚本${reset}"
      printf "  %-13s %s\n" "${gl_bai}用法:${reset}" "bash scripts/install.sh [-p PORT] [-d DIR] [-v VERSION] [-y]"
      printf "  %-13s %s\n" "${gl_bai}-p, --port${reset}" "管理后台端口（默认 ${gl_lan}${DEFAULT_PORT}${reset}）"
      printf "  %-13s %s\n" "${gl_bai}-d, --dir${reset}" "安装目录（默认 ${gl_lan}${DEFAULT_INSTALL_DIR}${reset}）"
      printf "  %-13s %s\n" "${gl_bai}-v, --version${reset}" "指定版本（默认 ${gl_lan}latest${reset}）"
      printf "  %-13s %s\n" "${gl_bai}-y, --yes${reset}" "免交互安装"
      printf "  %-13s %s\n" "${gl_bai}-h, --help${reset}" "显示本帮助"
      printf "%s\n" "${gl_hui}配置目录内的 lucky.conf 在重装时保留，仅替换二进制。${reset}"
      printf "%s\n" "${gl_hui}默认登录账号/密码：666 / 666，登录后请立即修改。${reset}"
      exit 0
      ;;
    *)
      error "未知参数: $1（使用 -h 查看帮助）"
      ;;
  esac
  shift
done

[ "$(id -u)" = "0" ] || error "请以 root 身份运行（例如 sudo bash scripts/install.sh）"

# ===================== 交互式补全端口 =====================
if [ -z "${PORT}" ]; then
  if [ "${INSTALL_YES}" = "1" ] || [ ! -t 0 ]; then
    PORT="${DEFAULT_PORT}"
  else
    read -r -p "  ${gl_bai}管理后台端口${reset} [默认 ${gl_lan}${DEFAULT_PORT}${reset}]: " _in
    PORT="${_in:-${DEFAULT_PORT}}"
  fi
fi
case "${PORT}" in
  ''|*[!0-9]*) error "端口必须为数字：${PORT}" ;;
esac
[ "${PORT}" -ge 1 ] && [ "${PORT}" -le 65535 ] || error "端口超出范围：${PORT}"

[ -n "${INSTALL_DIR}" ] || INSTALL_DIR="${DEFAULT_INSTALL_DIR}"
BIN_PATH="${INSTALL_DIR}/${APP_NAME}"
CONF_FILE="${INSTALL_DIR}/${APP_NAME}.conf"
SERVICE_FILE="/etc/systemd/system/${APP_NAME}.service"

print_banner
sep_line
section "安装信息"
printf "  %-14s %s\n" "${gl_lan}系统${reset}" "$(uname -s) $(uname -m)"
printf "  %-14s %s\n" "${gl_lan}程序${reset}" "${gl_bai}${APP_NAME}${reset}"
printf "  %-14s %s\n" "${gl_lan}安装目录${reset}" "${gl_bai}${INSTALL_DIR}${reset}"
printf "  %-14s %s\n" "${gl_lan}端口${reset}" "${gl_bai}${PORT}${reset}"
sep_line

# ===================== 架构 → 资产后缀 =====================
mips_float_suffix() {
  local base="$1" f="${LUCKY_MIPS_FLOAT:-}"
  if [ -z "${f}" ]; then
    # /proc/cpuinfo 无 FPU 信息时按软浮点处理（OpenWrt 多数 mips 设备为软浮点）
    if grep -qiE '^[[:space:]]*fpu[[:space:]]*:[[:space:]]*yes' /proc/cpuinfo 2>/dev/null; then
      f="hardfloat"
    else
      f="softfloat"
    fi
  fi
  printf '%s_%s' "${base}" "${f}"
}

detect_asset() {
  if [ -n "${LUCKY_ASSET:-}" ]; then
    printf '%s' "${LUCKY_ASSET}"
    return 0
  fi
  case "$(uname -m)" in
    x86_64|amd64)      printf 'Linux_x86_64' ;;
    aarch64|arm64)     printf 'Linux_arm64' ;;
    armv7l|armv8l)     printf 'Linux_armv7' ;;
    armv6l)            printf 'Linux_armv6' ;;
    armv5l|arm*)       printf 'Linux_armv5' ;;
    i386|i686)         printf 'Linux_i386' ;;
    riscv64)           printf 'Linux_riscv64' ;;
    mipsel|mipsle)     mips_float_suffix 'mipsle' ;;
    mips)              mips_float_suffix 'mips' ;;
    *)                 return 1 ;;
  esac
}

ASSET="$(detect_asset)" || error "无法识别架构 $(uname -m)，可用 LUCKY_ASSET=Linux_xxx 手动指定资产后缀"
ok "目标资产后缀：${gl_bai}${ASSET}${reset}"

# ===================== 版本解析 =====================
resolve_latest_version() {
  local base loc tag
  # 方式一：跟随 /releases/latest 的重定向（无需访问 api.github.com）
  while read -r base; do
    [ -n "${base}" ] || continue
    loc="$(curl -fsSL -o /dev/null -w '%{url_effective}' --connect-timeout 8 --max-time 20 \
           "${base}releases/latest" 2>/dev/null || true)"
    case "${loc}" in
      */releases/tag/*)
        tag="${loc##*/tag/}"
        [ -n "${tag}" ] && { printf '%s' "${tag}"; return 0; }
        ;;
    esac
  done < <(make_url_bases)

  # 方式二：GitHub API
  tag="$(curl -fsSL --connect-timeout 8 --max-time 20 \
        "https://api.github.com/repos/${GITHUB_REPO}/releases/latest" 2>/dev/null \
        | grep -m1 '"tag_name"' | sed -E 's/.*"tag_name"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/' || true)"
  [ -n "${tag}" ] && { printf '%s' "${tag}"; return 0; }
  return 1
}

if [ -z "${WANT_VERSION}" ]; then
  skip "解析最新版本号 ..."
  WANT_VERSION="$(resolve_latest_version || true)"
  if [ -n "${WANT_VERSION}" ]; then
    ok "最新版本：${gl_bai}${WANT_VERSION}${reset}"
  else
    warn "无法解析 latest（网络受限），回退到内置版本 ${FALLBACK_VERSION}"
    WANT_VERSION="${FALLBACK_VERSION}"
  fi
fi
case "${WANT_VERSION}" in
  v*) TAG="${WANT_VERSION}" ;;
  *)  TAG="v${WANT_VERSION}" ;;
esac
VER_NUM="${TAG#v}"

# ===================== 下载 =====================
have_curl() { command -v curl >/dev/null 2>&1; }
have_wget() { command -v wget >/dev/null 2>&1; }
if have_curl; then
  DL_MODE="curl"
elif have_wget; then
  DL_MODE="wget"
else
  error "未检测到 curl / wget，无法下载安装包"
fi

ASSET_NAME="lucky_${VER_NUM}_${ASSET}.tar.gz"
REL_URL="https://github.com/${GITHUB_REPO}/releases/download/${TAG}/${ASSET_NAME}"

download_asset() {
  local url tmp hdr candidates=() c
  tmp="$(mktemp)"
  hdr="${tmp}.hdr"
  mapfile -t candidates < <(make_url_candidates "${REL_URL}")

  # 注意：本函数的 stdout 会被调用方 $( ) 捕获为临时文件路径，
  #       因此所有进度信息一律走 stderr，避免污染返回值。
  for c in "${candidates[@]}"; do
    skip "尝试下载 ${gl_bai}${c}${reset}" >&2
    rm -f "${tmp}" "${hdr}" 2>/dev/null || true
    local fail="n"

    if [ "${DL_MODE}" = "curl" ]; then
      if command -v timeout >/dev/null 2>&1; then
        timeout 180 curl -fsSL --connect-timeout 10 --max-time 180 \
          -o "${tmp}" -D "${hdr}" "${c}" 2>/dev/null || fail="y"
      else
        curl -fsSL --connect-timeout 10 --max-time 180 \
          -o "${tmp}" -D "${hdr}" "${c}" 2>/dev/null || fail="y"
      fi
    else
      wget -qO "${tmp}" --timeout=60 --tries=1 "${c}" 2>/dev/null || fail="y"
    fi

    if [ "${fail}" = "y" ] || [ ! -s "${tmp}" ]; then
      warn "下载失败：${c}" >&2
      continue
    fi

    # 大小核对：镜像可能返回被截断的残缺文件（curl 仍认为传输正常）
    if [ "${DL_MODE}" = "curl" ] && [ -f "${hdr}" ]; then
      local expected actual
      # 无 content-length（chunked 传输）时 grep 会返回非零，必须兜底，否则 set -e 会中断脚本
      expected="$(grep -i '^content-length:' "${hdr}" | tail -n 1 | tr -d '\r' | awk '{print $2}' || true)"
      actual="$(stat -c%s "${tmp}" 2>/dev/null || echo 0)"
      if [ -n "${expected}" ] && [ "${actual}" != "${expected}" ]; then
        warn "文件不完整（${actual}/${expected} 字节），跳过该源" >&2
        continue
      fi
    fi

    # 魔数校验：必须是 gzip（1f 8b），否则可能是镜像返回的 HTML 错误页
    local magic
    magic="$(head -c2 "${tmp}" | od -An -tx1 | tr -d ' \n')"
    if [ "${magic}" != "1f8b" ]; then
      warn "下载内容不是 gzip 包，跳过该源" >&2
      continue
    fi

    # 完整性校验：tar 必须能正常列出内容
    if ! tar -tzf "${tmp}" >/dev/null 2>&1; then
      warn "tar 包损坏，跳过该源" >&2
      continue
    fi

    printf '%s' "${tmp}"
    rm -f "${hdr}" 2>/dev/null || true
    return 0
  done

  rm -f "${tmp}" "${hdr}" 2>/dev/null || true
  return 1
}

PKG_LOCAL=0
if [ -n "${LUCKY_PKG:-}" ]; then
  # 离线安装：直接使用本地已下载好的 tar.gz，不联网
  [ -f "${LUCKY_PKG}" ] || error "LUCKY_PKG 指定的安装包不存在：${LUCKY_PKG}"
  TMP_PKG="${LUCKY_PKG}"
  PKG_LOCAL=1
  section "离线安装"
  ok "使用本地安装包：${gl_bai}${LUCKY_PKG}${reset}"
else
  section "下载 ${gl_bai}${ASSET_NAME}${reset}"
  TMP_PKG="$(download_asset || true)"
  if [ -z "${TMP_PKG}" ] || [ ! -s "${TMP_PKG}" ]; then
    error "所有下载源均失败。可手动下载后重试：
    ${REL_URL}
  或下载后设置 LUCKY_PKG=/path/to/${ASSET_NAME} 离线安装。"
  fi
  ok "下载完成：${gl_bai}${ASSET_NAME}${reset}"
fi

# ===================== 停止旧服务 =====================
if command -v systemctl >/dev/null 2>&1 && [ -f "${SERVICE_FILE}" ]; then
  systemctl stop "${APP_NAME}" >/dev/null 2>&1 || true
  skip "已停止已存在的 ${APP_NAME} 服务"
elif command -v pgrep >/dev/null 2>&1 && [ -x "${BIN_PATH}" ] && pgrep -f "${BIN_PATH}" >/dev/null 2>&1; then
  pkill -f "${BIN_PATH}" >/dev/null 2>&1 || true
  sleep 1
  skip "已结束旧的 ${APP_NAME} 进程"
fi

# ===================== 部署二进制 =====================
section "安装程序"
mkdir -p "${INSTALL_DIR}"

TMP_DIR="$(mktemp -d)"
tar -xzf "${TMP_PKG}" -C "${TMP_DIR}"
# 仅删除脚本自己下载的临时包，离线模式下保留用户原始文件
[ "${PKG_LOCAL}" = "1" ] || rm -f "${TMP_PKG}" 2>/dev/null || true

EXTRACTED=""
for cand in "${TMP_DIR}/${APP_NAME}" "${TMP_DIR}/${APP_NAME}_${VER_NUM}_${ASSET}" "${TMP_DIR}/lucky"; do
  [ -f "${cand}" ] && { EXTRACTED="${cand}"; break; }
done
if [ -z "${EXTRACTED}" ]; then
  # 兜底：包内取第一个普通文件
  EXTRACTED="$(find "${TMP_DIR}" -maxdepth 2 -type f | head -n 1 || true)"
fi
[ -n "${EXTRACTED}" ] && [ -s "${EXTRACTED}" ] || error "安装包内未找到 ${APP_NAME} 可执行程序"

# 备份旧二进制，便于回滚
if [ -f "${BIN_PATH}" ]; then
  cp -f "${BIN_PATH}" "${BIN_PATH}.bak.$(date +%Y%m%d%H%M%S)" 2>/dev/null || true
  skip "已备份旧二进制"
fi

install -m 0755 "${EXTRACTED}" "${BIN_PATH}"
rm -rf "${TMP_DIR}" 2>/dev/null || true
chmod +x "${BIN_PATH}"
ok "已安装 ${gl_bai}${BIN_PATH}${reset}"

# 格式校验：确认是 ELF 可执行程序（不直接执行，避免误启动服务/改写配置）
BIN_MAGIC="$(head -c4 "${BIN_PATH}" | od -An -tx1 | tr -d ' \n' || true)"
if [ "${BIN_MAGIC}" = "7f454c46" ]; then
  skip "二进制格式校验通过（ELF）"
else
  warn "二进制魔数异常（${BIN_MAGIC:-空}），请确认架构 ${ASSET} 是否匹配本机"
fi

# ===================== 端口写入配置 =====================
# lucky 的 -p 仅在配置文件不存在时生效；配置文件已存在则必须直接改写
REAL_PORT="${PORT}"
if [ -f "${CONF_FILE}" ]; then
  if grep -q '"AdminWebListenPort"' "${CONF_FILE}" 2>/dev/null; then
    CUR_PORT="$(grep -o '"AdminWebListenPort"[[:space:]]*:[[:space:]]*[0-9]*' "${CONF_FILE}" \
                | head -n 1 | grep -o '[0-9]*$' || true)"
    if [ -n "${CUR_PORT}" ] && [ "${CUR_PORT}" != "${PORT}" ]; then
      cp -f "${CONF_FILE}" "${CONF_FILE}.bak.$(date +%Y%m%d%H%M%S)" 2>/dev/null || true
      sed -i "s/\"AdminWebListenPort\"[[:space:]]*:[[:space:]]*[0-9]*/\"AdminWebListenPort\": ${PORT}/" "${CONF_FILE}"
      ok "已改写配置端口 ${gl_bai}${CUR_PORT}${reset} → ${gl_bai}${PORT}${reset}"
    else
      skip "配置文件已存在，端口保持 ${CUR_PORT:-${PORT}}"
    fi
    REAL_PORT="$(grep -o '"AdminWebListenPort"[[:space:]]*:[[:space:]]*[0-9]*' "${CONF_FILE}" \
                 | head -n 1 | grep -o '[0-9]*$' || echo "${PORT}")"
  else
    warn "配置文件存在但无 AdminWebListenPort 字段，端口以配置为准"
  fi
else
  skip "首次安装：启动时由 -p ${PORT} 生成 ${CONF_FILE}"
fi

# ===================== systemd 服务 =====================
if command -v systemctl >/dev/null 2>&1; then
  USE_SYSTEMD="y"
else
  USE_SYSTEMD="n"
  warn "未检测到 systemd（容器或受限环境），将回退为后台运行"
fi

section "启动服务"
if [ "${USE_SYSTEMD}" = "y" ]; then
  cat > "${SERVICE_FILE}" <<UNIT
[Unit]
Description=lucky - 端口转发 / DDNS / 反向代理 网络工具
Documentation=https://github.com/${GITHUB_REPO}
After=network.target
Wants=network.target

[Service]
Type=simple
User=root
WorkingDirectory=${INSTALL_DIR}
ExecStart=${BIN_PATH} -c ${CONF_FILE} -p ${PORT}
Restart=on-failure
RestartSec=3s
LimitNOFILE=999999

[Install]
WantedBy=multi-user.target
UNIT

  systemctl daemon-reload
  systemctl enable "${APP_NAME}" >/dev/null 2>&1 || true
  systemctl restart "${APP_NAME}"
  sleep 3
  if systemctl is-active "${APP_NAME}" >/dev/null 2>&1; then
    ok "${gl_bai}${APP_NAME}${reset} 服务已启动"
  else
    printf "  %s %s\n" "${gl_hong}[错误]${reset}" "服务启动失败，请排查：${gl_bai}journalctl -u ${APP_NAME} -n 50${reset}" >&2
    exit 1
  fi
else
  nohup "${BIN_PATH}" -c "${CONF_FILE}" -p "${PORT}" \
    >> "${INSTALL_DIR}/${APP_NAME}.log" 2>&1 &
  sleep 2
  ok "${APP_NAME} 已在后台启动，pid: ${gl_bai}$!${reset}"
fi

# ===================== 防火墙 =====================
FW_OPENED="n"
open_firewall_port() {
  local P="$1"
  if command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
    if ! firewall-cmd --query-port="${P}/tcp" >/dev/null 2>&1; then
      firewall-cmd --permanent --add-port="${P}/tcp" >/dev/null 2>&1 || true
      firewall-cmd --reload >/dev/null 2>&1 || true
    fi
    ok "已通过 ${gl_bai}firewalld${reset} 开放端口 ${gl_lan}${P}/tcp${reset}"
    FW_OPENED="y"
    return 0
  fi
  if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active"; then
    ufw status 2>/dev/null | grep -q "${P}/tcp" || ufw allow "${P}/tcp" >/dev/null 2>&1 || true
    ok "已通过 ${gl_bai}ufw${reset} 开放端口 ${gl_lan}${P}/tcp${reset}"
    FW_OPENED="y"
    return 0
  fi
  if command -v iptables >/dev/null 2>&1; then
    if iptables -C INPUT -p tcp --dport "${P}" -j ACCEPT >/dev/null 2>&1; then
      ok "端口 ${gl_lan}${P}/tcp${reset} 已在 iptables 中放行"
      FW_OPENED="y"
      return 0
    fi
    if iptables -L INPUT -n 2>/dev/null | grep -qE 'policy (DROP|REJECT)|REJECT|DROP'; then
      if iptables -I INPUT -p tcp --dport "${P}" -j ACCEPT >/dev/null 2>&1; then
        ok "已通过 ${gl_bai}iptables${reset} 开放端口 ${gl_lan}${P}/tcp${reset}"
        FW_OPENED="y"
        return 0
      fi
    fi
  fi
  warn "未检测到活跃防火墙（firewalld/ufw/iptables），跳过端口开放"
}

open_firewall_port "${REAL_PORT}"

# ===================== 结果输出 =====================
# 取第一个 IPv4（hostname -I 在部分系统不可用，需逐级兜底且不能让脚本因非零退出码中断）
IP="$(hostname -I 2>/dev/null | awk '{print $1}' || true)"
[ -n "${IP}" ] || IP="$(ip -4 addr show scope global 2>/dev/null \
                        | awk '/inet /{print $2}' | cut -d/ -f1 | head -n 1 || true)"
[ -n "${IP}" ] || IP="<服务器IP>"

if [ "${FW_OPENED}" = "y" ]; then
  FW_STATUS="${gl_lv}已开放 ${REAL_PORT}/tcp${reset}"
else
  FW_STATUS="${gl_huang}未检测到活跃防火墙，已跳过${reset}"
fi

sep_line
printf "  %s\n" "${gl_lv}✔ ${APP_NAME} 安装成功！${reset}"
printf "  %-14s %s\n" "${gl_lan}版本${reset}"       "${gl_bai}${TAG}${reset}"
printf "  %-14s %s\n" "${gl_lan}访问地址${reset}"   "${gl_bai}http://${IP}:${REAL_PORT}${reset}"
printf "  %-14s %s\n" "${gl_lan}账号/密码${reset}"  "${gl_bai}666 / 666${reset}（登录后请立即修改）"
printf "  %-14s %s\n" "${gl_lan}程序目录${reset}"   "${gl_bai}${INSTALL_DIR}${reset}"
printf "  %-14s %s\n" "${gl_lan}配置文件${reset}"   "${gl_bai}${CONF_FILE}${reset}"
printf "  %-14s %s\n" "${gl_lan}防火墙${reset}"     "$FW_STATUS"
printf "  %-14s %s\n" "${gl_lan}服务命令${reset}"   "${gl_hui}systemctl status ${APP_NAME}${reset}"
printf "  %-14s %s\n" "${gl_lan}查看日志${reset}"   "${gl_hui}journalctl -u ${APP_NAME} -f${reset}"
printf "  %-14s %s\n" "${gl_lan}升级方式${reset}"   "${gl_hui}重新执行本脚本（配置自动保留）${reset}"
sep_line
