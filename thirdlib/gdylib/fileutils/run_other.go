//go:build !linux && !windows
// +build !linux,!windows

package fileutils

import (
	"fmt"
	"os/exec"
)

//OpenProgramOrFile 启动程序
//
// 原仓库只有 run_linux.go / run_windows.go 两份实现,导致 darwin/freebsd 等
// 平台交叉编译时报 "undefined: fileutils.OpenProgramOrFile"。
// 这里为其余平台补一份通用 exec 实现,行为与 run_linux.go 保持一致:
// 用 argv[0] 作为可执行程序, argv[1:] 作为参数启动。
//
// 仅用于程序自重启(web/configure.go 的恢复配置确认、web/web.go 的重启),
// 不改动任何业务逻辑,也不影响 linux/windows 上的原有实现。
func OpenProgramOrFile(argv []string) error {
	if len(argv) <= 0 {
		return fmt.Errorf("OpenProgramOrFile: argv 为空")
	}

	var startArgvs []string
	for i := range argv {
		if i == 0 {
			continue
		}
		startArgvs = append(startArgvs, argv[i])
	}

	cmd := exec.Command(argv[0], startArgvs...)
	return cmd.Start()
}
