#!/usr/bin/env bash
#
# lucky (Lucky 万吉) - Docker 镜像构建 / 推送脚本
#
# 镜像名：mobufan/lucky（:latest + :<版本号>）
#
# 说明：
#   Dockerfile 为 FROM scratch + COPY lucky /，因此构建上下文根目录必须存在
#   名为 lucky 的可执行文件。本脚本自动从 GitHub Releases 下载对应架构的
#   预编译二进制并解压到仓库根目录（该文件已被 .gitignore 忽略，不会误提交）。
#
# 用法：
#   bash scripts/docker-build-push.sh                 # 构建 amd64，仅本地
#   bash scripts/docker-build-push.sh --arch arm64    # 构建 arm64
#   bash scripts/docker-build-push.sh --push          # 构建并推送到 Docker Hub
#   bash scripts/docker-build-push.sh v2.28.2 --push  # 指定版本并推送
#
# 前置：推送前需先 docker login（Docker Hub 账号需有 mobufan 命名空间权限）
#
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-mobufan/lucky}"
GITHUB_REPO="${LUCKY_REPO:-meimolihan/lucky}"
FALLBACK_VERSION="2.28.2"

WANT_VERSION=""
ARCH="amd64"
DO_PUSH=0

info()  { printf '\033[38;5;10m>>> %s\033[0m\n' "$*"; }
warn()  { printf '\033[38;5;11m!!! %s\033[0m\n' "$*"; }
error() { printf '\033[38;5;9mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

while [ "$#" -gt 0 ]; do
  case "$1" in
    --arch)
      shift
      [ -n "${1:-}" ] || error "缺少 --arch 的值"
      ARCH="$1"
      ;;
    --push) DO_PUSH=1 ;;
    -h|--help)
      sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    -*|--) error "未知参数: $1" ;;
    *)     WANT_VERSION="$1" ;;
  esac
  shift
done

case "${ARCH}" in
  amd64)   ASSET="Linux_x86_64" ;;
  arm64)   ASSET="Linux_arm64"  ;;
  arm/v7)  ASSET="Linux_armv7"  ;;
  *)       error "暂不支持架构 ${ARCH}（可选 amd64 / arm64 / arm/v7）" ;;
esac

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

command -v docker >/dev/null 2>&1 || error "未检测到 docker"

# ---------- 解析版本号 ----------
if [ -z "${WANT_VERSION}" ]; then
  WANT_VERSION="$(curl -fsSL -o /dev/null -w '%{url_effective}' --connect-timeout 10 --max-time 25 \
                  "https://github.com/${GITHUB_REPO}/releases/latest" 2>/dev/null \
                  | sed -n 's|.*/releases/tag/||p' || true)"
  [ -n "${WANT_VERSION}" ] || WANT_VERSION="v${FALLBACK_VERSION}"
  info "解析到最新版本：${WANT_VERSION}"
fi
case "${WANT_VERSION}" in
  v*) TAG="${WANT_VERSION}" ;;
  *)  TAG="v${WANT_VERSION}" ;;
esac
VER_NUM="${TAG#v}"

# ---------- 准备构建上下文所需二进制 ----------
ASSET_NAME="lucky_${VER_NUM}_${ASSET}.tar.gz"
DL_URL="https://github.com/${GITHUB_REPO}/releases/download/${TAG}/${ASSET_NAME}"

TMP_DIR="$(mktemp -d)"
TMP_PKG="${TMP_DIR}/${ASSET_NAME}"
info "下载 ${ASSET_NAME}"
curl -fsSL --connect-timeout 10 --max-time 300 -o "${TMP_PKG}" "${DL_URL}" \
  || error "下载失败：${DL_URL}"

tar -xzf "${TMP_PKG}" -C "${TMP_DIR}"
[ -f "${TMP_DIR}/lucky" ] || error "压缩包内未找到 lucky 二进制"
install -m 0755 "${TMP_DIR}/lucky" "${REPO_ROOT}/lucky"
rm -rf "${TMP_DIR}"
info "已就绪构建上下文二进制：${REPO_ROOT}/lucky"

# ---------- 构建 ----------
info "构建镜像 ${IMAGE_NAME}:${VER_NUM} (linux/${ARCH})"
docker build --platform "linux/${ARCH}" -t "${IMAGE_NAME}:${VER_NUM}" -t "${IMAGE_NAME}:latest" .

# ---------- 推送 ----------
if [ "${DO_PUSH}" = "1" ]; then
  info "推送镜像到 Docker Hub"
  docker push "${IMAGE_NAME}:${VER_NUM}"
  docker push "${IMAGE_NAME}:latest"
  info "推送完成：${IMAGE_NAME}:${VER_NUM} / ${IMAGE_NAME}:latest"
else
  info "构建完成（未推送）。如需推送请加 --push，并确保已执行 docker login"
fi

# ---------- 运行提示 ----------
cat <<EOF

运行示例：
  docker run -d --name lucky --restart=always --net=host ${IMAGE_NAME}:${VER_NUM}
  docker run -d --name lucky --restart=always -p 16601:16601 ${IMAGE_NAME}:${VER_NUM}
  docker run -d --name lucky --restart=always --net=host -v /root/luckyconf:/goodluck ${IMAGE_NAME}:${VER_NUM}

访问：http://<主机IP>:16601   默认账号/密码：666 / 666
EOF
