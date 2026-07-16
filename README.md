# ELKFileSaver - 南网 eLink 聊天文件导出插件

长按 eLink 聊天中的文件/图片/视频消息，菜单中会多出一个「**保存到文件**」选项，点击即可导出到 iPhone 的「文件」App。

> 适用于 TrollStore (巨魔商店) 用户，iOS 14+，无需越狱。

---

## 工作原理

```
长按聊天文件消息
    ↓
菜单弹出（转发 / 收藏 / ... / 保存到文件 ← 新增！）
    ↓ 点击"保存到文件"
自动获取已解密文件
    ↓
弹出系统文件选择器 → 选择保存位置 → 完成 ✅
```

文件在 eLink 中是 AES 加密存储的。插件在文件**已解密**的阶段（`localPath`）进行拦截，因此导出的文件可以直接使用。

---

## 你需要准备

| 材料 | 说明 |
|------|------|
| 一个 GitHub 账号 | 免费注册: https://github.com/signup |
| 南网 eLink IPA | 就是你手头的 `南网eLink-2.6.850001.ipa` |
| iPhone 已装 TrollStore | iOS 14-16.x, CoreTrust 漏洞范围 |

---

## 使用方法（3 步）

### 第 1 步：Fork 仓库

点击本仓库右上角的 **Fork** 按钮，把代码复制到你的 GitHub 账号下。

### 第 2 步：上传 IPA + 运行

1. 在你的 Fork 仓库中，进入 `ipa/` 目录
2. 点击 **Add file → Upload files**，把你的 `南网eLink-2.6.850001.ipa` 拖进去
3. 提交 (Commit)
4. 点击仓库顶部的 **Actions** 标签 → 左侧选 **Build ELKFileSaver IPA** → 点击 **Run workflow** 蓝色按钮 → 再次点 **Run workflow** 确认
5. 等待约 **3 分钟**，构建完成
6. 页面底部 **Artifacts** 区域会出现 `eLink_FileSaver`，点击下载

### 第 3 步：安装到手机

1. 解压下载的 `eLink_FileSaver.zip`，得到 `eLink_FileSaver.ipa`
2. 把 IPA 传到 iPhone（微信/QQ/AirDrop/爱思助手 均可）
3. 在 iPhone 上打开 **TrollStore** → **Install from file** → 选择 IPA
4. 安装完成，打开 eLink，试试长按一个文件消息！

---

## 如果菜单没出现？

由于无法在真机上调试，Hook 方法名是基于二进制分析**推测**的。如果菜单没有出现：

1. 在 iPhone 上安装 **Frida**（TrollStore 可直接装 frida-server）
2. 连接电脑运行以下命令，查看调用栈：
   ```
   frida -U -l debug.js 南网eLink
   ```
3. 把日志发给我，我会修正 Hook 点

---

## 仅支持的文件类型

| 消息类型 | 支持 |
|----------|------|
| 图片 | ✅ |
| 视频 | ✅ |
| 文件 (Word/Excel/PDF 等) | ✅ |
| 语音 | ✅ |
| 文本 | ❌ (不是文件) |
| 链接卡片 | ❌ |

---

## 项目结构

```
elink-file-saver/
├── .github/workflows/build.yml   ← GitHub Actions 配置
├── dylib/
│   ├── entry.m                   ← dylib 入口
│   ├── ELKMenuHook.m             ← 菜单 Hook
│   ├── ELKFileExporter.m         ← 文件导出
│   ├── ELKRuntimeHelper.m        ← Swizzling 工具
│   └── Makefile                  ← dylib 编译
├── tools/                        ← insert_dylib 源码（自动克隆）
├── ipa/                          ← 放原始 IPA
├── build.sh                      ← 完整构建脚本
└── README.md
```

---

## 常见问题

**Q: 会封号吗？**
A: 这是本地注入，只修改了 App 本地行为，不涉及网络协议。TrollStore 安装的 App 无法检测注入。

**Q: eLink 更新后还能用吗？**
A: 把新版本 IPA 放到 `ipa/` 目录，重新跑一次 Actions 即可。

**Q: 不登录能构建吗？**
A: 可以。GitHub Actions 对公开仓库免费且无限使用。

---

## License

仅供学习和个人使用。请遵守南方电网公司相关政策。
