# ELKFileSaver - 南网 eLink 聊天文件导出插件

任意页面右上角「📤 导出」→ 文件浏览器（搜索 / 分类 / 多选 / 预览）→ 导出到 iPhone 的「文件」App。

> 适用于 TrollStore (巨魔商店) + TrollFools 用户，iOS 14+，无需越狱。

---

## 功能特性

| 功能 | 说明 |
|------|------|
| 🔍 文件搜索 | 输入关键词实时过滤 |
| 🏷️ 分类标签 | 全部 / 📄文档 / 📊表格 / 🖼️图片 / 📦压缩包 / 📐CAD |
| 👆 长按预览 | 长按文件行 → QuickLook 预览内容 |
| ✅ 多选导出 | 批量勾选 → 一次性导出多个文件 |
| 🔄 下拉刷新 | 传了新文件不用退出，下拉刷新即可 |
| ⚡ 10 秒缓存 | 关闭浏览器后 10 秒内重开不复扫 |
| 🔔 角标计数 | 按钮显示文件数量 `📤 导出 (26)` |
| 🐱 随机问候 | 每次启动弹窗随机提示语 + 时间段问候 |

---

## 工作原理

```
eLink 接收到的文件存储在 App 沙箱固定目录中：
  Documents/Profiles/*/Decript/  （解密文件）
  Documents/Profiles/*/Files/    （原始文件）

插件扫描这些目录 → 文件浏览器列出所有文件
→ 搜索 / 分类 / 预览 / 多选 → 系统分享 → 保存到文件 ✅
```

**核心思路：纯文件系统直读，不碰 App 内部对象。**

---

## 你需要准备

| 材料 | 说明 |
|------|------|
| 一个 GitHub 账号 | 免费注册: https://github.com/signup |
| iPhone 已装 TrollStore | iOS 14-16.x / 17.0 |
| iPhone 已装 TrollFools | 巨魔注入器: https://github.com/Lessica/TrollFools |
| 南网 eLink | 手机上已安装即可，不需要 IPA 文件 |

---

## 使用方法（4 步）

### 第 1 步：Fork 仓库

点击本仓库右上角的 **Fork** 按钮，把代码复制到你的 GitHub 账号下。

### 第 2 步：编译 dylib

1. 在你的 Fork 仓库中，点击顶部的 **Actions** 标签
2. 左侧选 **Build ELKFileSaver dylib**
3. 点击右侧 **Run workflow** → 再点绿色 **Run workflow**
4. 等待约 **1 分钟**，构建完成
5. 页面底部 **Artifacts** 区域出现 `ELKFileSaver_v17`，点击下载
6. 解压得到 `ELKFileSaver_v17.dylib`

### 第 3 步：注入到 eLink

1. 把 `ELKFileSaver_v17.dylib` 传到 iPhone（微信/QQ/AirDrop/爱思助手均可）
2. 打开 **TrollFools**
3. 在应用列表中找到 **eLink**（或南网eLink）
4. 点击 → 选择注入 → 找到 dylib 文件
5. 注入完成 ✅

### 第 4 步：使用

1. 打开 eLink → 看到「🐱 喵喵插件 v17」弹窗确认注入成功
2. 右上角出现 **「📤 导出 (N)」** 按钮
3. 点击 → 文件浏览器 → 搜索或分类 → 选择文件
4. 系统分享菜单 → **存储到文件** ✅

> 提示：点「一天内别说了 🐱」可以 24 小时内不再弹窗。

---

## 支持的文件类型

| 文件类型 | 图标 | 支持 |
|----------|:---:|:---:|
| PDF 文件 | 📕 | ✅ |
| Word 文档 | 📝 | ✅ |
| Excel 表格 | 📊 | ✅ |
| PPT 演示 | 📽️ | ✅ |
| 图片 (PNG/JPG/GIF 等) | 🖼️ | ✅ |
| 视频 (MP4/MOV) | 🎬 | ✅ |
| 音频 (MP3/M4A) | 🎵 | ✅ |
| 压缩包 (ZIP/RAR/7Z) | 📦 | ✅ |
| CAD 图纸 (DWG/DXF/DGN) | 📐 | ✅ |
| 其他文件 | 📎 | ✅ |
| 纯文本消息 | — | ❌ |
| 链接卡片 | — | ❌ |

---

## 升级版本

升级插件版本只需改一处：

1. 在仓库根目录打开 **`VERSION`** 文件
2. 把数字改成新版本号（如 `18`）
3. Commit → Actions 重跑

dylib 文件名、Artifact 名、弹窗标题会**自动更新**为新版本号。

---

## 项目结构

```
elink-file-saver/
├── VERSION                       ← 版本号（一处改，全局生效）
├── .github/workflows/build.yml   ← GitHub Actions 配置
├── dylib/
│   ├── entry.m                   ← dylib 入口 + 弹窗
│   ├── ELKMenuHook.m             ← 按钮注入
│   ├── ELKFileExporter.m         ← 文件浏览器 + 文件操作
│   ├── ELKRuntimeHelper.m        ← 工具方法
│   ├── *.h                       ← 头文件
│   └── Makefile                  ← dylib 编译
├── build.sh                      ← 构建脚本
└── README.md
```

---

## 常见问题

**Q: 会封号吗？**
A: 这是本地注入，只读取 App 沙箱中的文件，不修改任何网络协议。TrollStore 安装的 App 无法检测注入。

**Q: eLink 更新后还能用吗？**
A: 可以。更新 App 后，重新用 TrollFools 注入一次 dylib 即可。

**Q: 不登录能构建吗？**
A: 可以。GitHub Actions 对公开仓库免费且无限使用。

**Q: 文件浏览器里出现很多无效文件？**
A: v15 起已加入智能过滤，纯数字文件名和无后缀小文件会自动排除。

**Q: 导出文件名是数字？**
A: v13 起直接读取沙箱固定目录中的文件（Decript/Files），保留原始文件名。

**Q: 支持 eLink 3.3.0 吗？**
A: 支持。插件不依赖 eLink 版本，通过文件系统扫描工作，所有版本通用。

---

## License

仅供学习和个人使用。请遵守南方电网公司相关政策。
