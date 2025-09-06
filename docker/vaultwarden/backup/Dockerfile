# /my-vaultwarden/backup/Dockerfile

FROM alpine:latest

# 安装 rclone 和 tar (用于打包)
RUN apk add --no-cache rclone tar

# 创建备份脚本的工作目录
WORKDIR /app

# 将备份脚本复制到镜像中
COPY backup.sh .

# 赋予脚本执行权限
RUN chmod +x backup.sh

# 容器启动时默认执行的命令
CMD ["./backup.sh"]
