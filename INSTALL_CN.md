# Omarchy 中国地区安装指南

本文档提供了针对中国大陆地区用户优化的安装方法，以解决网络连接问题。

## 快速安装（使用中国镜像）

如果您在中国大陆，可以使用以下命令进行安装，这将自动使用中国友好的镜像源：

```bash
curl -o- https://omarchy.org/install | OMARCHY_USE_CHINA_MIRRORS=1 bash
```

## 环境变量选项

### OMARCHY_USE_CHINA_MIRRORS

设置为 `1` 启用中国镜像源（清华、中科大、阿里云等）：

```bash
export OMARCHY_USE_CHINA_MIRRORS=1
```

### OMARCHY_GIT_MIRROR

指定 Git 仓库镜像站点（如果 GitHub 访问困难）：

```bash
# 使用 Gitee 镜像（需要先在 Gitee 上创建镜像）
export OMARCHY_GIT_MIRROR=gitee.com

# 使用 GitCode 镜像（需要先在 GitCode 上创建镜像）
export OMARCHY_GIT_MIRROR=gitcode.com
```

## 手动切换到中国镜像

如果您已经安装了 Omarchy，可以随时切换到中国镜像：

```bash
omarchy-refresh-pacman china
```

切换回默认镜像：

```bash
omarchy-refresh-pacman stable
```

## 支持的中国镜像源

系统会自动使用以下中国大陆镜像源（按优先级排序）：

1. **清华大学开源镜像站** - https://mirrors.tuna.tsinghua.edu.cn
2. **中国科学技术大学镜像站** - https://mirrors.ustc.edu.cn  
3. **阿里云镜像站** - https://mirrors.aliyun.com
4. **腾讯云镜像站** - https://mirrors.cloud.tencent.com
5. **网易镜像站** - https://mirrors.163.com
6. **华为云镜像站** - https://repo.huaweicloud.com

## GPG 密钥服务器

系统已配置多个 GPG 密钥服务器以提高连接成功率：

- keyserver.ubuntu.com
- pgp.mit.edu
- pgp.surfnet.nl
- keys.mailvelope.com
- keyring.debian.org
- keys.openpgp.org

安装脚本会自动尝试多个密钥服务器，直到成功为止。

## 完整安装示例

```bash
# 设置环境变量
export OMARCHY_USE_CHINA_MIRRORS=1
export OMARCHY_GIT_MIRROR=gitee.com  # 可选，如果 GitHub 访问困难

# 开始安装
curl -o- https://omarchy.org/install | bash
```

## 故障排除

### 如果 GitHub 克隆失败

1. 尝试使用 Gitee 或 GitCode 镜像（需要先在这些平台创建仓库镜像）
2. 或使用代理：`export https_proxy=http://your-proxy:port`

### 如果 GPG 密钥导入失败

脚本会自动尝试多个密钥服务器。如果全部失败，您可以：

1. 检查网络连接
2. 尝试使用代理
3. 手动导入密钥

### 如果包下载速度慢

使用中国镜像命令：

```bash
omarchy-refresh-pacman china
```

## 支持

如有问题，请访问：https://discord.gg/tXFUdasqhY
