#!/bin/bash
#
# lucky (Lucky 万吉) - 发布脚本（触发 GitHub Actions 单一发布流水线）
#
# 设计对齐 fan-webssh/scripts/build-and-push.sh：
#   不在本地编译任何产物，仅做：版本号 bump -> 写发版备注 -> 提交推送 -> 打 v 开头 tag。
#   推送后由 .github/workflows/release.yml 链式自动完成：
#     [1] 构建前端 (npm install + npm run build)
#     [2] 交叉编译 18 个平台二进制并打包 tar.gz
#     [3] 创建 GitHub Release 并附带全部二进制 + sha256 清单
#
# 好处：Release 由 Actions 用 secrets.GITHUB_TOKEN 创建，
#       因此本机【不需要】 gh auth login 也能发版（git push 走 SSH 即可）。
#
# Usage:
#   bash scripts/build-and-push.sh v2.28.2 --yes -m "本次新增 xxx"
#
set -euo pipefail

info()  { echo -e "\033[38;5;10m>>> $*\033[0m"; }
warn()  { echo -e "\033[38;5;11m!!! $*\033[0m"; }
error() { echo -e "\033[38;5;9mERROR: $*\033[0m"; exit 1; }

# ===================== 参数解析 =====================
YES_MODE=0
TAG=""
MSG=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --yes) YES_MODE=1; shift ;;
        -m|--message)
            shift
            [ -n "${1:-}" ] || error "缺少 -m/--message 的备注内容"
            MSG="$1"
            shift
            ;;
        *) TAG="$1"; shift ;;
    esac
done

[[ -z "${TAG}" ]] && error "缺少TAG参数，示例: $0 v2.28.2 --yes"
[[ "${TAG}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+ ]] || error "TAG 格式错误，示例: v2.28.2"

cd "$(dirname "$0")/.."
TARGET_VER="${TAG#v}"

# 当前分支（lucky 用 master，fan-webssh 用 main，这里自动识别）
BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "master")

info "目标版本: ${TAG} (分支: ${BRANCH})"

# ===================== 版本号 bump =====================
info "执行版本号更新 -> ${TARGET_VER}"

BUMP_FILES=("web/adminviews/package.json")
for f in "${BUMP_FILES[@]}"; do
    [[ -f "${f}" ]] || error "缺失文件 ${f}"
done

# sed -i 在 GNU / BSD(macOS) 下语法不同，统一处理
if sed --version 2>&1 | grep -q GNU; then
    SED_I=(-i)
else
    SED_I=(-i '')
fi

for f in "${BUMP_FILES[@]}"; do
    if grep -q '"version"' "${f}"; then
        sed "${SED_I[@]}" "s/^  \"version\": \".*\",\$/  \"version\": \"${TARGET_VER}\",/" "${f}"
    else
        warn "${f} 无 version 字段，跳过"
    fi
done

info "版本号确认:"
grep -n '"version"' "${BUMP_FILES[@]}"

# ===================== 写发版备注 =====================
info "写入发版备注 RELEASE_NOTES.md"
{
  if [ -n "${MSG}" ]; then
    printf '%s\n\n' "${MSG}"
  fi
  printf '## 一键安装（Linux）\n\n'
  printf '```bash\n'
  printf 'bash -c "$(curl -sSL https://raw.githubusercontent.com/meimolihan/lucky/master/scripts/install.sh)" -p 16601\n'
  printf '```\n\n'
  printf '可选参数：`-p 端口`（默认 16601）、`-d 安装目录`（默认 /etc/lucky）、`-v 版本`、`-y` 免交互。\n'
  printf '重装/升级再执行一次即可，`lucky.conf` 配置保留。\n\n'
  printf '## Docker\n\n'
  printf '镜像名：`mobufan/lucky`（标签 `latest` 与 `%s`）\n\n' "${TAG}"
  printf '```bash\n'
  printf 'docker run -d --name lucky --restart=always --net=host mobufan/lucky:%s\n' "${TAG}"
  printf '# 挂载配置目录，删除容器后配置不丢失\n'
  printf 'docker run -d --name lucky --restart=always --net=host -v /root/luckyconf:/goodluck mobufan/lucky:%s\n' "${TAG}"
  printf '```\n\n'
  printf '自行构建镜像：\n\n'
  printf '```bash\n'
  printf 'bash scripts/docker-build-push.sh --arch amd64 --push   # 需先 docker login\n'
  printf '```\n\n'
  printf '## 默认凭据\n\n'
  printf '后台地址 `http://<设备IP>:16601`，默认账号/密码 `666 / 666`，登录后请立即修改。\n'
} > RELEASE_NOTES.md

# ===================== 重复 Tag/Release 清理 =====================
# 需要 gh 登录；未登录时跳过（不影响发版，Actions 侧也会 delete 后重建）
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    if gh release view "${TAG}" >/dev/null 2>&1; then
        warn "发现已存在 Release ${TAG}，删除之"
        gh release delete "${TAG}" -y --cleanup-tag 2>/dev/null || true
    fi
    git tag -d "${TAG}" 2>/dev/null || true
    git push origin --delete "${TAG}" 2>/dev/null || true
else
    warn "gh 未登录，跳过远端 Release/tag 预清理（Actions 会自动 delete 后重建）"
    git tag -d "${TAG}" 2>/dev/null || true
fi

# ===================== 提交 & 打 Tag =====================
info "提交版本变更"
git add -A
git commit -m "chore: bump version to ${TARGET_VER}" || info "无版本文件变更，跳过提交"

if [[ "${YES_MODE}" -eq 0 ]]; then
    read -r -p "确认推送到 origin/${BRANCH} 并打 tag ${TAG}? [y/N] " yn
    [[ "${yn}" == "y" || "${yn}" == "Y" ]] || { warn "已取消"; exit 0; }
fi

info "推送 ${BRANCH}"
git push origin "${BRANCH}"

info "创建并推送 tag ${TAG}"
git tag "${TAG}" 2>/dev/null || warn "tag ${TAG} 已存在，复用"
git push origin "${TAG}"

info "已推送 tag ${TAG}，GitHub Actions 将自动编译 18 个平台并发布 Release"

# ===================== 流水线状态展示 =====================
WORKFLOW="release.yml"

if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
    EXPECTED_SHA=$(git rev-parse HEAD 2>/dev/null || echo "")
    RUN_JSON=""
    for i in $(seq 1 18); do
        RUN_JSON=$(gh run list --workflow="${WORKFLOW}" --limit 1 --branch "${TAG}" \
            --json status,displayTitle,databaseId,startedAt,headSha 2>/dev/null) || RUN_JSON=""
        if [[ -n "${RUN_JSON}" && "${RUN_JSON}" != "[]" ]]; then
            SHA=$(echo "${RUN_JSON}" | jq -r '.[0].headSha')
            [[ -z "${EXPECTED_SHA}" || "${SHA}" == "${EXPECTED_SHA}" ]] && break
        fi
        sleep 5
    done

    if [[ -n "${RUN_JSON}" && "${RUN_JSON}" != "[]" ]]; then
        RUN_ID=$(echo "${RUN_JSON}"    | jq -r '.[0].databaseId')
        STATUS=$(echo "${RUN_JSON}"    | jq -r '.[0].status')
        TITLE=$(echo "${RUN_JSON}"     | jq -r '.[0].displayTitle')
        STARTED=$(echo "${RUN_JSON}"   | jq -r '.[0].startedAt')
        echo ""
        echo "————————————————————————————————————————————————"
        printf "%-14s%s\n" "[工作流]：" "${WORKFLOW}"
        printf "%-14s%s\n" "[运行状态]：" "${STATUS}"
        printf "%-14s%s\n" "[提交标题]：" "${TITLE}"
        printf "%-14s%s\n" "[Run ID]：" "${RUN_ID}"
        printf "%-14s%s\n" "[开始时间]：" "${STARTED}"
        echo "————————————————————————————————————————————————"
        echo "实时跟踪流水线：gh run watch ${RUN_ID}"
        echo "查看详细信息：  gh run view ${RUN_ID}"
        echo "查看失败日志：  gh run view ${RUN_ID} --log-failed"
        echo "————————————————————————————————————————————————"
    else
        warn "暂未获取到流水线记录（Actions 可能尚未注册），稍后手动查看："
        echo "  gh run list --workflow=${WORKFLOW} --branch ${TAG}"
    fi
else
    warn "gh 未登录或缺少 jq，跳过流水线状态查询。可到网页查看："
    echo "  https://github.com/meimolihan/lucky/actions/workflows/${WORKFLOW}"
fi

info "发布结果: https://github.com/meimolihan/lucky/releases/tag/${TAG}"
