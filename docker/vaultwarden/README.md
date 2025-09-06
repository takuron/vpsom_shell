# Vaultwarden with Automated WebDAV Backups

这是一个用于部署 [Vaultwarden](https://github.com/dani-garcia/vaultwarden)（一个非官方的 Bitwarden 服务器实现）的 Docker Compose 配置模板。它内置了使用 `rclone` 将数据自动定时备份到 WebDAV 服务器的功能，并集成了 `Watchtower` 以实现容器的自动更新。

## 设计特性

* **安全优先**: Vaultwarden 服务仅监听本地 `127.0.0.1` 地址，必须通过反向代理才能从外部访问。
* **自动化备份**: 独立的备份容器会定时将数据打包、压缩并上传到你的 WebDAV 服务器，并自动清理旧备份。
* **自动化更新**: Watchtower 会定期检查并更新 Vaultwarden 镜像，确保你的服务保持最新。
* **开箱即用**: 你只需要修改几个配置文件，即可快速启动并运行整套服务。

## 目录结构

请确保你的目录结构与此一致：

```
.
├── docker-compose.yml   # 核心服务编排文件
├── rclone.conf          # WebDAV 连接配置文件
├── backup/
│   ├── Dockerfile       # 备份容器的构建定义
│   └── backup.sh        # 核心备份逻辑脚本
└── README.md            # 本说明文档
```

## 🚀 快速开始

在启动服务之前，你必须完成以下配置步骤。

### 步骤 1: 配置 WebDAV 连接 (`rclone.conf`)

编辑 `rclone.conf` 文件，填入你的 WebDAV 服务器信息。

```ini
[webdav-remote]
type = webdav
url = [https://your-webdav-server.com/remote.php/dav/files/username/vaultwarden_backups](https://your-webdav-server.com/remote.php/dav/files/username/vaultwarden_backups)
vendor = other
user = your_webdav_username
pass = your_webdav_password_obscured
```

* `url`: **[必需]** 你的 WebDAV 完整 URL，路径应指向用于存放备份的目录。
* `user`: **[必需]** 你的 WebDAV 用户名。
* `pass`: **[必需]** 你的 WebDAV 密码。**强烈建议**不要使用明文密码。请通过运行以下命令生成加密后的密码字符串，然后粘贴到此处：
    ```bash
    docker run --rm -it rclone/rclone obscure YOUR_REAL_PASSWORD_HERE
    ```

### 步骤 2: 配置 Vaultwarden 服务 (`docker-compose.yml`)

编辑 `docker-compose.yml` 文件，修改 `vaultwarden` 服务下的 `environment` 变量。

* `DOMAIN`: **[必需]** 设置为你将用于访问 Vaultwarden 的完整域名，例如 `https://vault.your-domain.com`。
* `ADMIN_TOKEN`: **[必需]** 设置一个超长且随机的字符串作为后台管理员令牌。你可以使用 `openssl rand -base64 48` 来生成一个。
* `TZ`: **[必需]** 修改为你所在的时区，例如 `Asia/Shanghai`。
* `SIGNUPS_ALLOWED`: 建议在创建完自己的账户后，将其修改为 `false` 以禁止新用户注册。

### 步骤 3: (可选) 调整备份频率

在 `docker-compose.yml` 文件中，`backup` 服务的 `BACKUP_INTERVAL` 环境变量控制着备份的频率，单位为秒。默认值为 `86400` (24小时)。

## ⚠️ 前提：配置反向代理

此配置**不会**将 Vaultwarden 直接暴露在公网上。你**必须**设置一个反向代理（如 Nginx, Caddy 等）来监听公网的 443 端口 (HTTPS)，并将流量安全地转发到 Vaultwarden 容器的 `127.0.0.1:13000` 端口。

#### Caddy 示例 (`Caddyfile`)

```caddy
vault.your-domain.com {
    # 将流量反向代理到 Vaultwarden 容器
    reverse_proxy 127.0.0.1:13000
}
```

#### Nginx 示例

```nginx
server {
    listen 80;
    server_name vault.your-domain.com;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl http2;
    server_name vault.your-domain.com;

    # 你的 SSL 证书路径
    ssl_certificate /path/to/your/fullchain.pem;
    ssl_certificate_key /path/to/your/privkey.pem;

    location / {
        proxy_pass [http://127.0.0.1:13000](http://127.0.0.1:13000);
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # 为 WebSocket 提供支持
    location /notifications/hub {
        proxy_pass [http://127.0.0.1:13000](http://127.0.0.1:13000);
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
```

## 部署与管理

1.  **启动服务**:
    完成上述所有配置后，在当前目录下运行：
    ```bash
    docker-compose up -d --build
    ```
    `--build` 参数会根据 `backup/Dockerfile` 构建本地的备份镜像。

2.  **检查运行状态**:
    ```bash
    docker-compose ps
    ```
    确认 `vaultwarden`, `watchtower`, `vaultwarden-backup` 三个容器的状态均为 `running` 或 `up`。

3.  **查看日志**:
    * 查看 Vaultwarden 应用日志: `docker-compose logs -f vaultwarden`
    * 查看备份服务日志，确认备份是否成功执行: `docker-compose logs -f backup`

4.  **访问你的实例**:
    * 通过浏览器访问你配置的域名 `https://vault.your-domain.com` 来注册和使用。
    * 访问 `https://vault.your-domain.com/admin` 并使用你设置的 `ADMIN_TOKEN` 登录管理后台。

## 数据恢复

如果发生意外需要从备份中恢复数据：

1.  **停止服务**: `docker-compose stop vaultwarden`
2.  **下载备份**: 从你的 WebDAV 服务器下载最新的备份文件 (e.g., `vaultwarden-backup-....tar.gz`)。
3.  **定位数据卷**: 运行 `docker volume inspect vaultwarden_vw-data` 并找到 `Mountpoint` 所指向的宿主机路径。
4.  **清空旧数据**: **务必小心操作！**删除 `Mountpoint` 路径下的所有文件和文件夹。
    ```bash
    # 示例路径，请替换为你自己的
    sudo rm -rf /var/lib/docker/volumes/vaultwarden_vw-data/_data/*
    ```
5.  **解压备份**: 将下载的备份文件解压到数据卷目录。
    ```bash
    # 示例路径，请替换为你自己的
    sudo tar -xzf /path/to/your/downloaded-backup.tar.gz -C /var/lib/docker/volumes/vaultwarden_vw-data/_data/
    ```
6.  **重启服务**: `docker-compose up -d vaultwarden`