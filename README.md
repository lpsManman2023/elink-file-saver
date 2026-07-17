# ELKFileSaver - 南网 eLink 聊天文件导出插件

点开 eLink 聊天中的文件/图片/视频预览，右上角出现「📤导出」按钮，点击即可导出到 iPhone 的「文件」App。

> 适用于 TrollStore (巨魔商店) + TrollFools 用户，iOS 14+，无需越狱。

---

## 工作原理

```
点一下聊天文件消息 → 进入预览页（eLink 解密文件到临时目录）
    ↓
插件检测到预览页 → 拍文件系统快照
    ↓
等待 0.8 秒 → 对比快照，找到新增的解密文件
    ↓
预览页右上角出现「📤导出」按钮
    ↓
点击导出 → 系统分享菜单 → 存储到文件 ✅
```

**核心思路：纯文件系统监控，不碰 App 内部对象。**

---

## 你需要准备

| 材料 | 说明 |
|------|------|
| 一个 GitHub 账号 | 免费注册: https://github.com/signup |
| iPhone 已装 TrollStore | iOS 14-16.x / 17.0 |
| iPhone 已装 TrollFools | 巨魔注入器，用于注入 dylib 到 App |
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
5. 页面底部 **Artifacts** 区域出现 `ELKFileSaver_dylib`，点击下载
6. 解压得到 `ELKFileSaver.dylib`

### 第 3 步：注入到 eLink

1. 把 `ELKFileSaver.dylib` 传到 iPhone（微信/QQ/AirDrop/爱思助手均可）
2. 打开 **TrollFools**
3. 在应用列表中找到 **eLink**（或南网eLink）
4. 点击 → 选择注入 → 找到 `ELKFileSaver.dylib`
5. 注入完成 ✅

### 第 4 步：使用

1. 打开 eLink → 看到「🐱 喵喵插件」弹窗确认注入成功
2. 进入任意聊天 → **点一下**文件/图片/视频消息（打开预览）
3. 预览页右上角出现 **「📤导出」** 按钮
4. 点击导出 → 系统分享菜单 → **存储到文件** ✅

---

## 支持的文件类型

| 消息类型 | 支持 |
|----------|:---:|
| PDF 文件 | ✅ |
| Word / Excel / PPT | ✅ |
| 图片 | ✅ |
| 视频 | ✅ |
| 语音 | ✅ |
| 压缩包 (ZIP/RAR/7Z) | ✅ |
| CAD 图纸 (DWG/DXF/DGN) | ✅ |
| 文本 | ❌ (非文件类型) |
| 链接卡片 | ❌ |

---

## 项目结构

```
elink-file-saver/
├── .github/workflows/build.yml   ← GitHub Actions 配置
├── dylib/
│   ├── entry.m                   ← dylib 入口
│   ├── ELKMenuHook.m             ← 预览页检测 + 导出按钮
│   ├── ELKFileExporter.m         ← 文件系统监控 + 导出
│   ├── ELKRuntimeHelper.m        ← 工具方法
│   ├── ELKMenuHook.h
│   ├── ELKFileExporter.h
│   ├── ELKRuntimeHelper.h
│   └── Makefile                  ← dylib 编译
├── build.sh                      ← 构建脚本（仅编译 dylib）
└── README.md
```

---

## 常见问题

**Q: 会封号吗？**
A: 这是本地注入，只读取文件系统临时目录中的解密文件，不修改任何网络协议。TrollStore 安装的 App 无法检测注入。

**Q: eLink 更新后还能用吗？**
A: 可以。更新 App 后，重新用 TrollFools 注入一次 dylib 即可（TrollFools 支持重新注入）。

**Q: 不登录能构建吗？**
A: 可以。GitHub Actions 对公开仓库免费且无限使用。

**Q: 点导出后提示"未找到解密文件"？**
A: 请确保文件已在预览中**完整加载**后再点导出。可以先看完文件内容，再点按钮。

**Q: 导出文件名是数字/哈希？**
A: eLink 内部用哈希命名解密文件，这是已知限制。文件内容正确可用，可以通过重命名修改。

**Q: 安装到 3.3.0 版本能工作吗？**
A: 可以。插件不依赖 eLink 版本，通过文件系统监控工作，所有版本通用。

---

## License

仅供学习和个人使用。请遵守南方电网公司相关政策。
