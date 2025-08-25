# FreshRSS Docker 部署指南

这是一个用于部署健壮、可自动更新的 [FreshRSS](https://freshrss.org/) 服务的 Docker Compose 配置。它使用 PostgreSQL 作为后端数据库，并集成 [Watchtower](https://containrrr.dev/watchtower/) 实现容器的自动更新。

此方案专为使用外部（宿主机）反向代理（如 Caddy、Nginx）而设计，以处理 HTTPS 和外部流量。

## ✨ 特性

-   **容器化**: 所有服务（FreshRSS, PostgreSQL）均在 Docker 容器中运行，环境隔离且部署简单。
-   **持久化存储**: 所有重要数据（数据库、FreshRSS配置、扩展）都通过 Docker 数据卷进行持久化。
-   **安全设计**:
    -   数据库不暴露于公网。
    -   FreshRSS 应用仅监听宿主机的本地回环地址(`localhost`)，强制通过反向代理访问。
-   **自动更新**: 内置 Watchtower 服务，会在每天凌晨4点自动检查并更新 FreshRSS 和 PostgreSQL 的镜像，并清理旧镜像。
-   **配置分离**: 使用 `.env` 文件管理所有敏感信息和可变配置，无需修改 `docker-compose.yml`。

## 📂 文件结构

在开始之前，请确保您的文件夹包含以下三个文件：

```
.
├── docker-compose.yml
├── .env
└── README.md
```

## 🚀 部署步骤

### 1. 先决条件

在开始之前，请确保您已具备：

1.  一台已经安装好 Docker 和 Docker Compose 的服务器。
2.  一个域名，并且已经将其 DNS A/AAAA 记录指向您服务器的公网 IP 地址。
3.  在服务器（宿主机）上安装并运行了一个 Web 服务器/反向代理软件（如 Caddy 或 Nginx）。

### 2. 配置环境变量

这是部署前 **唯一需要修改** 的文件。请打开 `.env` 文件并根据您的实际情况修改其中的值。

```env
# --- General Settings ---
# 设置您所在的时区
TZ=Asia/Shanghai

# --- PostgreSQL Database Settings ---
# 数据库名 (通常无需修改)
POSTGRES_DB=freshrss
# 数据库用户名 (通常无需修改)
POSTGRES_USER=freshrss_user
# !!! 请务必替换为一个长而随机的强密码 !!!
POSTGRES_PASSWORD=YOUR_VERY_STRONG_AND_SECRET_PASSWORD

# --- Host Port for FreshRSS ---
# Caddy/Nginx 将通过这个端口访问FreshRSS服务 (通常无需修改)
FRESHRSS_HOST_PORT=8090
```

-   **`POSTGRES_PASSWORD`**: **（必须修改）** 这是最重要的安全设置。请将 `YOUR_VERY_STRONG_AND_SECRET_PASSWORD` 替换为您自己生成的一个长而复杂的密码。
-   **`FRESHRSS_HOST_PORT`**: 这是 FreshRSS 容器映射到您服务器本地的端口。后续的反向代理配置需要用到此端口。默认的 `8090` 通常是安全的，但如果您服务器上的此端口已被占用，可以修改为其他任意未被占用的端口（建议大于1024）。

### 3. 配置反向代理

您需要在宿主机上配置您的 Web 服务器，将来自公网的请求转发到本地的 FreshRSS 容器。

**请将所有示例中的 `rss.your-domain.com` 替换为您的真实域名。**

#### Caddy 配置范例

如果您的宿主机上安装了 Caddy，请将以下配置块添加到您的 `Caddyfile` (通常位于 `/etc/caddy/Caddyfile`)。Caddy 会自动处理 HTTPS 证书。

```caddy
# 将 rss.your-domain.com 替换为您的真实域名
rss.your-domain.com {
    # 启用 Gzip 和 Zstandard 压缩以提升性能
    encode zstd gzip

    # 添加推荐的安全头
    header {
        Strict-Transport-Security "max-age=31536000;"
        X-Content-Type-Options "nosniff"
        X-Frame-Options "DENY"
        Referrer-Policy "strict-origin-when-cross-origin"
    }

    # 将所有请求反向代理到本地运行的 FreshRSS 容器
    # 确保端口号与 .env 文件中的 FRESHRSS_HOST_PORT 匹配
    reverse_proxy localhost:8090
}
```

修改配置后，重载 Caddy 服务使其生效：

```bash
sudo systemctl reload caddy
```

#### Nginx 配置范例

如果您的宿主机上安装了 Nginx，可以创建一个新的配置文件，例如 `/etc/nginx/sites-available/freshrss.conf`，并填入以下内容。

此范例假设您使用 [Certbot](https://certbot.eff.org/) 来获取和管理 SSL 证书。

```nginx
server {
    listen 80;
    server_name rss.your-domain.com;

    # 自动将所有 HTTP 请求重定向到 HTTPS
    location / {
        return 301 https://$host$request_uri;
    }
}

server {
    listen 443 ssl http2;
    server_name rss.your-domain.com;

    # SSL 证书路径 (由Certbot生成)
    ssl_certificate /etc/letsencrypt/live/[rss.your-domain.com/fullchain.pem](https://rss.your-domain.com/fullchain.pem);
    ssl_certificate_key /etc/letsencrypt/live/[rss.your-domain.com/privkey.pem](https://rss.your-domain.com/privkey.pem);
    include /etc/letsencrypt/options-ssl-nginx.conf;
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;

    # 添加推荐的安全头
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "DENY" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    
    # Gzip 压缩
    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml application/xml+rss text/javascript;

    location / {
        # 反向代理到本地的 FreshRSS 容器
        # 确保端口号与 .env 文件中的 FRESHRSS_HOST_PORT 匹配
        proxy_pass [http://127.0.0.1:8090](http://127.0.0.1:8090);
        
        # 设置必要的代理头
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host $host;
        proxy_set_header X-Forwarded-Port $server_port;
    }
}
```

创建文件后，启用该站点并重载 Nginx：

```bash
# 创建软链接以启用站点
sudo ln -s /etc/nginx/sites-available/freshrss.conf /etc/nginx/sites-enabled/

# 测试 Nginx 配置语法是否正确
sudo nginx -t

# 如果测试通过，则重载 Nginx 服务
sudo systemctl reload nginx
```

### 4. 启动服务

完成以上所有配置后，在 `docker-compose.yml` 文件所在的目录下，执行以下命令来启动所有服务：

```bash
docker-compose up -d
```

Docker 将会下载所需的镜像并在后台启动容器。

### 5. 完成 FreshRSS 初始化

打开您的浏览器，访问 `https://rss.your-domain.com`。您应该能看到 FreshRSS 的安装向导页面。根据页面提示完成最后的数据库配置和管理员账户创建即可开始使用。

## 🔧 日常维护

-   **查看服务状态**:
    ```bash
    docker-compose ps
    ```
-   **查看实时日志**:
    ```bash
    # 查看所有服务的日志
    docker-compose logs -f
    # 只看 FreshRSS 服务的日志
    docker-compose logs -f freshrss
    ```
-   **停止服务**:
    ```bash
    docker-compose down
    ```
-   **手动更新**: Watchtower 会自动更新。但如果您想立即手动更新所有容器，可以执行：
    ```bash
    docker-compose pull && docker-compose up -d
    ```
-   **备份**: 强烈建议定期备份您的数据。最关键的数据位于 Docker 数据卷中。您可以使用 `docker cp` 命令或挂载宿主机目录的方式来备份 `freshrss_data`, `freshrss_extensions`, 和 `postgres_data` 这三个数据卷的内容。