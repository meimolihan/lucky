#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Lucky v2.28.2 全平台二进制构建脚本
#
# 说明:
#   - 用本仓库源码真实交叉编译 18 个平台的二进制,打包成 lucky_2.28.2_<平台>.tar.gz
#   - 与上游 v2.27.2 Release 的资产命名保持一一对应(便于用户平滑替换)
#   - 版本号通过 ldflags 注入 main.version,不修改 Go 源码
#
# 用法:
#   bash scripts/build_v2.28.2.sh
#
# 产物:
#   dist-release/lucky_2.28.2_*.tar.gz   18 个
#   dist-release/sha256sums.txt         校验值清单
# -----------------------------------------------------------------------------
set -euo pipefail

VERSION="v2.28.2"
VER_NUM="2.28.2"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTDIR="${REPO_ROOT}/dist-release"

# 前端产物必须已构建(web/adminviews/dist),否则 go:embed 会拿到旧前端或失败
if [[ ! -f "${REPO_ROOT}/web/adminviews/dist/index.html" ]]; then
    echo "[错误] 未找到 web/adminviews/dist/index.html,请先执行 npm run build" >&2
    exit 1
fi

mkdir -p "${OUTDIR}"
rm -f "${OUTDIR}"/*.tar.gz "${OUTDIR}/sha256sums.txt"
cd "${REPO_ROOT}"

# Go 模块代理: 默认 proxy.golang.org 在国内常被墙(502 Bad Gateway),改用国内镜像
export GOPROXY="${GOPROXY:-https://goproxy.cn,https://mirrors.aliyun.com/goproxy/,direct}"
export GOSUMDB=off
export GOFLAGS="-mod=mod"
echo "==> GOPROXY=${GOPROXY}"

# 平台表: 输出名后缀 | GOOS | GOARCH | GOARM | GOMIPS
# 命名与上游 v2.27.2 资产完全一致
PLATFORMS="
darwin_arm64|darwin|arm64|||
darwin_x86_64|darwin|amd64|||
freebsd_arm64|freebsd|arm64|||
freebsd_i386|freebsd|386|||
freebsd_x86_64|freebsd|amd64|||
Linux_arm64|linux|arm64|||
Linux_armv5|linux|arm|5||
Linux_armv6|linux|arm|6||
Linux_armv7|linux|arm|7||
Linux_i386|linux|386|||
Linux_mipsle_hardfloat|linux|mipsle||hardfloat
Linux_mipsle_softfloat|linux|mipsle||softfloat
Linux_mips_hardfloat|linux|mips||hardfloat
Linux_mips_softfloat|linux|mips||softfloat
Linux_riscv64|linux|riscv64|||
Linux_x86_64|linux|amd64|||
Windows_i386|windows|386|||
Windows_x86_64|windows|amd64|||
"

TOTAL=$(echo "${PLATFORMS}" | grep -c '|' || true)
COUNT=0

echo "==> 开始构建 ${VERSION},共 ${TOTAL} 个平台"

while IFS='|' read -r name goos goarch goarm gomips; do
    [[ -z "${name}" ]] && continue
    COUNT=$((COUNT + 1))

    bin="lucky"
    [[ "${goos}" == "windows" ]] && bin="lucky.exe"

    printf "[%2d/%2d] %-26s (%s/%s" "${COUNT}" "${TOTAL}" "${name}" "${goos}" "${goarch}"
    [[ -n "${goarm}" ]]   && printf " GOARM=%s" "${goarm}"
    [[ -n "${gomips}" ]]  && printf " GOMIPS=%s" "${gomips}"
    printf ")\n"

    # 清理上一次的中间产物
    rm -f "${bin}"

    env CGO_ENABLED=0 \
        GOOS="${goos}" \
        GOARCH="${goarch}" \
        GOARM="${goarm}" \
        GOMIPS="${gomips}" \
        GOFLAGS="-mod=mod" \
        go build \
          -tags "adminweb nomsgpack" \
          -ldflags "-s -w -X main.version=${VERSION}" \
          -o "${bin}" \
          .

    # 打包: tar.gz 内直接是单个可执行文件,与上游一致
    tar czf "${OUTDIR}/lucky_${VER_NUM}_${name}.tar.gz" "${bin}"
    rm -f "${bin}"
done <<< "${PLATFORMS}"

echo ""
echo "==> 生成 sha256 清单..."
( cd "${OUTDIR}" && sha256sum lucky_${VER_NUM}_*.tar.gz > sha256sums.txt )

echo ""
echo "==> 构建完成,产物在 ${OUTDIR}:"
ls -lh "${OUTDIR}" | tail -n +2
echo ""
cat "${OUTDIR}/sha256sums.txt"
