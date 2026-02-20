#!/bin/bash

# ==============================================================================
# Debian 12 交互式初始化与激活脚本 (All-in-One)
#
# 作者: Takuron with Gemini 2.5Pro
# 日期: 2025-08-25
#
# 注意: 请以 root 用户或使用 sudo 权限运行此脚本。
# ==============================================================================

# 定义颜色常量
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# 检查是否以root用户运行
if [ "$(id -u)" -ne 0 ]; then
  echo -e "${RED}错误：此脚本需要以 root 权限运行。请使用 'sudo ./setup_debian.sh'。${NC}"
  exit 1
fi

# 全局变量，用于存储新的SSH端口
NEW_SSH_PORT=""

# --- 函数定义 ---

# 1. 更新系统
update_system() {
  echo -e "\n${GREEN}=== 1. 更新系统 ===${NC}"
  read -p "您想更新系统软件包吗？ (y/n): " choice
  if [[ "$choice" =~ ^[Yy]$ ]]; then
    echo "正在更新软件包列表并升级系统..."
    apt-get update && apt-get upgrade -y && apt-get autoremove -y && apt-get clean -y
    echo -e "${GREEN}系统更新完成。${NC}"
  else
    echo "跳过系统更新。"
  fi
}

# 2. 启用 BBR + CAKE
enable_bbr_cake() {
  echo -e "\n${GREEN}=== 2. 配置 TCP 拥塞控制 ===${NC}"
  read -p "您想修改 TCP 拥塞协议为 BBR，队列算法为 CAKE 吗？ (y/n): " choice
  if [[ "$choice" =~ ^[Yy]$ ]]; then
    echo "正在配置 BBR 和 CAKE..."
    if uname -r | grep -q "5\.10\|6\."; then
      cat > /etc/sysctl.d/99-bbr-cake.conf <<EOF
# 启用 BBR 拥塞控制协议
net.core.default_qdisc=cake
net.ipv4.tcp_congestion_control=bbr
EOF
      sysctl -p /etc/sysctl.d/99-bbr-cake.conf
      echo "检查配置..."
      if sysctl net.ipv4.tcp_congestion_control | grep -q "bbr" && sysctl net.core.default_qdisc | grep -q "cake"; then
        echo -e "${GREEN}BBR 和 CAKE 已成功启用。${NC}"
      else
        echo -e "${RED}配置启用失败，请手动检查。${NC}"
      fi
    else
        echo -e "${YELLOW}警告：您的内核版本可能不支持 BBR，Debian 12 默认内核应支持。${NC}"
    fi
  else
    echo "跳过 TCP 配置。"
  fi
}

# 3. 修改 SSH 端口 (修正版)
change_ssh_port() {
  echo -e "\n${GREEN}=== 3. 修改 SSH 默认端口 ===${NC}"
  read -p "您想随机修改 SSH 默认端口吗？ (y/n): " choice
  if [[ "$choice" =~ ^[Yy]$ ]]; then
    local ssh_config_file="/etc/ssh/sshd_config"
    NEW_SSH_PORT=$(shuf -i 10000-65535 -n 1)
    echo "正在将 SSH 端口修改为: $NEW_SSH_PORT"
    cp "$ssh_config_file" "$ssh_config_file.bak.$(date +%F-%T)"
    echo "已备份配置文件到 $ssh_config_file.bak.*"
    sed -i -E 's/^[#\s]*Port\s+[0-9]+/#&/' "$ssh_config_file"
    echo "" >> "$ssh_config_file"
    echo "# 由初始化脚本设置于 $(date)" >> "$ssh_config_file"
    echo "Port $NEW_SSH_PORT" >> "$ssh_config_file"
    if grep -q -E "^Port\s+$NEW_SSH_PORT" "$ssh_config_file"; then
      echo -e "${GREEN}SSH 端口已成功设置为 ${YELLOW}$NEW_SSH_PORT${GREEN}。${NC}"
      echo -e "${YELLOW}注意：新的 SSH 端口将在 SSH 服务重启后生效。${NC}"
    else
      echo -e "${RED}修改 SSH 端口失败！请手动检查 $ssh_config_file 文件。${NC}"
    fi
  else
    echo "跳过修改 SSH 端口。"
    local current_port
    current_port=$(grep -E "^\s*Port\s+" /etc/ssh/sshd_config | awk '{print $2}' | head -n 1)
    if [[ -z "$current_port" ]]; then
        NEW_SSH_PORT=22
    else
        NEW_SSH_PORT="$current_port"
    fi
    echo "将为当前 SSH 端口 ${YELLOW}$NEW_SSH_PORT${NC} 配置防火墙。"
  fi
}

# 4. 安装和配置 UFW
setup_ufw() {
  echo -e "\n${GREEN}=== 4. 安装与配置 UFW 防火墙 ===${NC}"
  read -p "您想安装 UFW 防火墙吗？ (y/n): " choice
  if [[ "$choice" =~ ^[Yy]$ ]]; then
    echo "正在安装 UFW..."
    apt-get install ufw -y
    echo "配置 UFW 规则..."
    ufw --force reset
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow 80/tcp comment 'HTTP'
    ufw allow 443/tcp comment 'HTTPS'
    if [[ -n "$NEW_SSH_PORT" ]]; then
      ufw allow "$NEW_SSH_PORT"/tcp comment 'SSH'
      echo -e "已为 SSH 端口 ${YELLOW}$NEW_SSH_PORT${NC} 添加了 UFW 规则。"
    else
      echo -e "${RED}警告：无法确定SSH端口，防火墙规则未配置SSH端口！${NC}"
    fi
    echo -e "${YELLOW}UFW 已安装并配置，但尚未启用。${NC}"
    ufw status verbose
  else
    echo "跳过安装 UFW。"
  fi
}

# 5. 安装 Docker
install_docker() {
  echo -e "\n${GREEN}=== 5. 安装 Docker ===${NC}"
  read -p "您想安装 Docker 吗？ (y/n): " choice
  if [[ "$choice" =~ ^[Yy]$ ]]; then
    echo "正在安装 Docker..."
    apt-get update &>/dev/null
    apt-get install -y ca-certificates curl gnupg
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
      tee /etc/apt/sources.list.d/docker.list > /dev/null
    apt-get update &>/dev/null
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    if systemctl is-active --quiet docker; then
      echo -e "${GREEN}Docker 安装成功并已启动。${NC}"
    else
      echo -e "${RED}Docker 安装可能遇到问题，服务未运行。${NC}"
    fi
  else
    echo "跳过安装 Docker。"
  fi
}

# 6. 安装 Web 服务器
install_web_server() {
  echo -e "\n${GREEN}=== 6. 安装 Web 服务器 ===${NC}"
  PS3="请选择要安装的 Web 服务器 (输入数字): "
  options=("Caddy2" "Nginx" "跳过")
  select opt in "${options[@]}"
  do
    case $opt in
      "Caddy2")
        echo "正在安装 Caddy2..."
        apt-get install -y debian-keyring debian-archive-keyring apt-transport-https &>/dev/null
        curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
        curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
        apt-get update &>/dev/null
        apt-get install -y caddy
        echo -e "${GREEN}Caddy2 安装完成。${NC}"
        break
        ;;
      "Nginx")
        echo "正在安装 Nginx..."
        apt-get install -y nginx
        systemctl enable nginx &>/dev/null
        systemctl start nginx
        echo -e "${GREEN}Nginx 安装完成。${NC}"
        break
        ;;
      "跳过")
        echo "跳过安装 Web 服务器。"
        break
        ;;
      *) echo "无效选项 $REPLY";;
    esac
  done
}

# 7. 修改 Root 密码
change_root_password() {
  echo -e "\n${GREEN}=== 7. 修改 Root 密码 ===${NC}"
  read -p "您想现在修改 root 用户的密码吗？ (y/n): " choice
  if [[ "$choice" =~ ^[Yy]$ ]]; then
    echo "接下来请输入新的 root 密码："
    passwd root
    echo -e "${GREEN}Root 密码修改完成。${NC}"
  else
    echo -e "跳过修改 root 密码。${YELLOW}强烈建议您稍后手动运行 'sudo passwd root' 命令设置一个强密码。${NC}"
  fi
}

# 8. 最终激活与重启
activate_and_reboot() {
  echo -e "\n${GREEN}=========================================${NC}"
  echo -e "${GREEN}=== 所有配置步骤已完成 ===${NC}"
  echo -e "${GREEN}=========================================${NC}"
  echo -e "\n最后一步，您可以选择立即启用防火墙并重启系统以应用所有更改。"

  read -p "您想现在进行激活和重启吗？ (y/n): " choice
  if [[ "$choice" =~ ^[Yy]$ ]]; then
    # 启用 UFW (如果已安装)
    if command -v ufw &> /dev/null; then
       echo -e "${YELLOW}警告：即将启用防火墙！请再次确认您可以通过 SSH 端口 (${NEW_SSH_PORT}) 访问服务器。${NC}"
       read -p "确认启用防火墙吗？配置错误可能导致您永久失去服务器访问权限！ (y/n): " confirm_ufw
       if [[ "$confirm_ufw" =~ ^[Yy]$ ]]; then
         echo "正在启用 UFW 防火墙..."
         yes | ufw enable
         echo "UFW 已启用。当前状态："
         ufw status verbose
       else
         echo "已取消启用防火墙。您可以稍后手动运行 'sudo ufw enable'。"
       fi
    fi

    # 重启系统
    read -p "现在确认要重启系统吗？ (y/n): " confirm_reboot
    if [[ "$confirm_reboot" =~ ^[Yy]$ ]]; then
      echo "系统将在 5 秒后重启..."
      sleep 5
      reboot
    else
      echo "已取消重启。请注意，SSH端口、内核参数等重要更改需要重启才能完全生效。"
    fi
  else
    echo -e "\n${GREEN}操作完成，但未激活。${NC}"
    echo "请记得稍后手动执行以下操作："
    if command -v ufw &> /dev/null; then
        echo "1. 启用防火墙: ${YELLOW}sudo ufw enable${NC}"
    fi
    echo "2. 重启系统: ${YELLOW}sudo reboot${NC}"
  fi
  echo -e "\n${GREEN}祝您使用愉快！${NC}"
}


# --- 主逻辑 ---
main() {
  update_system
  enable_bbr_cake
  change_ssh_port
  setup_ufw
  install_docker
  install_web_server
  change_root_password
  activate_and_reboot
}

# 运行主函数
main