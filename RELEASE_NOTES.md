v2.28.2: 移除界面推广内容, 版本号更新, 仓库地址变更为 meimolihan/lucky

## 一键安装（Linux）

```bash
bash -c "$(curl -sSL https://raw.githubusercontent.com/meimolihan/lucky/master/scripts/install.sh)" -p 16601
```

可选参数：`-p 端口`（默认 16601）、`-d 安装目录`（默认 /etc/lucky）、`-v 版本`、`-y` 免交互。
重装/升级再执行一次即可，`lucky.conf` 配置保留。

彻底卸载：`bash -c "$(curl -sSL https://raw.githubusercontent.com/meimolihan/lucky/master/scripts/install.sh)" --uninstall -y`
（停服 → 删服务单元与安装目录 → 回收防火墙端口；`lucky.conf` 先备份到 `/root/lucky-uninstall-backup-<时间戳>/`）

## Docker

镜像名：`mobufan/lucky`（标签 `latest` 与 `v2.28.2`）

```bash
docker run -d --name lucky --restart=always --net=host mobufan/lucky:v2.28.2
# 挂载配置目录，删除容器后配置不丢失
docker run -d --name lucky --restart=always --net=host -v /root/luckyconf:/goodluck mobufan/lucky:v2.28.2
```

自行构建镜像：

```bash
bash scripts/docker-build-push.sh --arch amd64 --push   # 需先 docker login
```

## 默认凭据

后台地址 `http://<设备IP>:16601`，默认账号/密码 `666 / 666`，登录后请立即修改。
