#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Lucky v2.28.2 Release 发布脚本(本地真构建产物版)
#
# 与"下载上游改名"方案的区别:
#   本脚本上传的是 scripts/build_v2.28.2.sh 用本仓库源码【真实交叉编译】出来的
#   18 个平台二进制,文件内嵌版本号 v2.28.2,不再沿用上游 v2.27.2 的产物。
#
# 流程:
#   1) 校验 dist-release/ 下 18 个 tar.gz 是否齐全
#   2) 生成 sha256 清单并写入 Release 正文
#   3) 用 git archive 重新打包 Source code (zip / tar.gz)
#   4) 创建 tag v2.28.2 并 push
#   5) gh release create 上传全部资产
#
# 前置条件:
#   - 已跑过: bash scripts/build_v2.28.2.sh
#   - gh 已安装且已登录: gh auth login
#   - 对 meimolihan/lucky 有 push 权限
#   - 前端源码改动已 commit(否则源码包不含改动)
#
# 用法:
#   bash scripts/release_v2.28.2.sh            # 正式发布
#   bash scripts/release_v2.28.2.sh --dry-run  # 只校验+生成正文,不 push 不上传
# -----------------------------------------------------------------------------
set -euo pipefail

REPO="meimolihan/lucky"
NEW_TAG="v2.28.2"
NEW_VER="2.28.2"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ASSET_DIR="${REPO_ROOT}/dist-release"

DRY_RUN=0
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1

# 兼容 WSL/Linux 的 gh 与 Windows 装的 gh.exe
GH_BIN="$(command -v gh 2>/dev/null || command -v gh.exe 2>/dev/null || true)"

echo "==> 仓库根目录: ${REPO_ROOT}"
echo "==> 资产目录:   ${ASSET_DIR}"

# --- 0. 环境自检 ------------------------------------------------------------
if [[ ! -d "${ASSET_DIR}" ]]; then
    echo "[错误] 未找到 ${ASSET_DIR},请先执行: bash scripts/build_v2.28.2.sh" >&2
    exit 1
fi

EXPECT=18
ACTUAL=$(find "${ASSET_DIR}" -maxdepth 1 -name "lucky_${NEW_VER}_*.tar.gz" | wc -l | tr -d ' ')
echo "==> 资产数: ${ACTUAL} / 期望 ${EXPECT}"
if [[ "${ACTUAL}" -ne "${EXPECT}" ]]; then
    echo "[错误] 资产数量不符,请检查构建是否完整" >&2
    ls -1 "${ASSET_DIR}"/*.tar.gz 2>/dev/null | sed 's#.*/##' >&2
    exit 1
fi

if [[ -z "${GH_BIN}" ]]; then
    echo "[错误] 未找到 gh。Windows 安装: winget install --id GitHub.cli" >&2
    exit 1
fi
echo "==> gh: ${GH_BIN} ($("${GH_BIN}" --version | head -1))"

if ! "${GH_BIN}" auth status >/dev/null 2>&1; then
    echo "[错误] gh 未登录。请先执行: gh auth login" >&2
    exit 1
fi

# --- 1. 生成 sha256 ---------------------------------------------------------
echo "==> 计算 sha256..."
( cd "${ASSET_DIR}" && sha256sum lucky_${NEW_VER}_*.tar.gz > sha256sums.txt )
cat "${ASSET_DIR}/sha256sums.txt"

# --- 2. 重新打包源码包 ------------------------------------------------------
cd "${REPO_ROOT}"
if [[ -n "$(git status --porcelain)" ]]; then
    echo "[警告] 工作区有未提交改动,源码包将不含这些改动:" >&2
    git status --short | head -10 >&2
    read -r -p "    仍要继续? [y/N] " yn
    [[ "${yn}" != "y" && "${yn}" != "Y" ]] && { echo "已取消"; exit 1; }
fi

if [[ "${DRY_RUN}" -eq 0 ]]; then
    echo "==> 打包 Source code (基于 HEAD)..."
    git archive --format=zip    --prefix="lucky-${NEW_TAG}/" -o "${ASSET_DIR}/lucky-${NEW_TAG}-source.zip"    HEAD
    git archive --format=tar.gz --prefix="lucky-${NEW_TAG}/" -o "${ASSET_DIR}/lucky-${NEW_TAG}-source.tar.gz" HEAD
fi

# --- 3. 生成 Release 正文 ---------------------------------------------------
NOTES="${ASSET_DIR}/notes.md"
cat > "${NOTES}" <<EOF
# Lucky ${NEW_TAG}

## 更新内容
1. 移除管理界面内全部广告位与推广内容。
2. 全局版本号更新至 ${NEW_TAG}。
3. 开源仓库地址统一变更为 https://github.com/${REPO}

## 构建说明
- 全部 ${EXPECT} 个平台二进制由本仓库源码真实交叉编译产出,版本号内嵌于二进制。
- Source code (zip / tar.gz) 基于本次前端源码修改重新打包。

## SHA256 校验值

\`\`\`
$(cat "${ASSET_DIR}/sha256sums.txt")
\`\`\`
EOF

if [[ "${DRY_RUN}" -eq 1 ]]; then
    echo ""
    echo "==> dry-run 结束。正文已生成: ${NOTES}"
    echo "    确认无误后重跑: bash scripts/release_v2.28.2.sh"
    exit 0
fi

# --- 4. 创建 tag 并 push ----------------------------------------------------
echo "==> 创建 tag ${NEW_TAG}..."
cd "${REPO_ROOT}"
if git rev-parse "${NEW_TAG}" >/dev/null 2>&1; then
    echo "[警告] tag ${NEW_TAG} 已存在,跳过创建"
else
    git tag -a "${NEW_TAG}" -m "Lucky ${NEW_TAG}: 去广告 + 版本号 + 仓库地址更新"
fi
git push origin "${NEW_TAG}"

# --- 5. 发布 Release --------------------------------------------------------
echo "==> 发布 Release ${NEW_TAG} 到 ${REPO}..."
"${GH_BIN}" release create "${NEW_TAG}" \
  --repo "${REPO}" \
  --title "Lucky ${NEW_TAG}" \
  --notes-file "${NOTES}" \
  "${ASSET_DIR}"/lucky_"${NEW_VER}"_*.tar.gz \
  "${ASSET_DIR}"/lucky-"${NEW_TAG}"-source.zip \
  "${ASSET_DIR}"/lucky-"${NEW_TAG}"-source.tar.gz

echo ""
echo "==> 完成: https://github.com/${REPO}/releases/tag/${NEW_TAG}"
