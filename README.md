# 菜单栏 Cursor 额度

第三方 macOS 菜单栏小工具。读取本机已登录的 Cursor 账号，显示当前账期还剩多少额度。栏里看进度，点击看 Cursor 模型、其他模型和 Grok Bot 周额度。

不是 Cursor 官方产品，和 Cursor / Anysphere 没有关联。

## 功能

菜单栏是圆环加剩余百分比，选中几个额度就横向排几组（最多三组）。

- **彩色弧**：账期里还剩多少用量，弧越短剩得越少
- **径向短线**：账期还剩多少时间，沿圆环走
- **绿色**：剩余用量跟得上剩余时间
- **橙色**：用量比时间花得更快
- **红色**：剩余用量低于 15%
- 刷新失败时保留上次结果
- 数据时间距离现在超过 30 分钟时，圆环旁标橙点

点击打开明细，可刷新或退出。右上角写着上次拉到数的时间；读数过期显示橙色「过期」，完全拉不到显示「不可用」。

明细里三条额度常驻，行首勾选框决定这条是否出现在菜单栏（至少留一个）。没改过时只勾选其他模型。行尾箭头调顺序，没勾的原地置灰。菜单栏按这个顺序横向排出勾选的圆环和各自百分比，最多三组。选择记在本机偏好里，重开仍然有效。

底栏最后一行左侧是「菜单栏 %」和「开机自启」，右侧是重启和退出。「菜单栏 %」关掉后，圆环旁不再写百分比。「开机自启」默认关，打开后下次登录会自动出现在菜单栏。

多显示器时出现在主显示器菜单栏。被挤进 `«` 时，展开或到「系统设置 → 菜单栏」里把「Cursor 额度」拖出来。

### 刷新频率

- **定时**
    - 每 5 分钟拉一次额度
    - 每 1 分钟重算剩余时间刻度
- **Cursor Agent 回答完毕**：收到 hook 调用后 3 秒
- **手动**：立刻拉
    - 点开详情
    - 点「刷新」
    - 命令行

        ```sh
        "$HOME/Applications/Cursor Quota.app/Contents/MacOS/CursorQuota" --refresh
        ```

### 隐私

- 只读本机 `state.vscdb` 里的 `cursorAuth/accessToken` 和套餐类型
- 令牌只留在内存，只发给 `api2.cursor.sh` 的用量接口
- 不跟随重定向，避免令牌落到别的主机
- 不写用量日志，不上报遥测，没有第三方依赖
- Cursor 的 Hooks Output 会记 hook 有没有跑，那是 Cursor 自己的日志

个人用量接口没有公开文档，字段以后可能变。只认当前的双池百分比。

## 安装

- macOS 26 或更新
- 本机已安装、打开并登录过 Cursor
- 能编译 Swift 6 的工具链（Xcode 或 Command Line Tools）

```sh
./install.sh
```

会编译 `Cursor Quota.app` 到 `~/Applications` 并打开，同时写入用户级 Cursor hook。不需要 API key。

不启动应用：

```sh
./install.sh --no-launch
```

### Cursor hook

`./install.sh` 会写入：

- `~/.cursor/hooks.json`（`stop`、`sessionEnd`）
- `~/.cursor/hooks/nudge-cursor-quota.sh`

Cursor 监视这个文件，保存后热加载。没有官方安装命令。

- **`stop`**：Agent 这一轮答完。连续问 3 次会跑 3 次。刷新主要靠它。
- **`sessionEnd`**：整段会话结束（关对话、关窗口），不是每轮回答。关窗口时偶发失败，不影响 `stop`。

查看配置：`Cmd+Shift+P` → **Open Customize** → **Hooks**。不在 Settings 侧栏。

看有没有跑：底部面板 → **Output** → **Hooks**。磁盘日志：

```text
~/Library/Application Support/Cursor/logs/**/cursor.hooks.*.log
```

成功时会出现 `nudge-cursor-quota.sh`、`exit code: 0`、`executed successfully`。

只重装 hook：

```sh
./scripts/install-user-hook.sh
```

### 卸载

1. 打开面板，关掉「开机自启」
2. 从菜单退出应用
3. 删除 `~/Applications/Cursor Quota.app`
4. 从 `~/.cursor/hooks.json` 去掉指向 `./hooks/nudge-cursor-quota.sh` 的 `stop` / `sessionEnd`
5. 删除 `~/.cursor/hooks/nudge-cursor-quota.sh`

勾选、顺序和百分比记在偏好里。开机自启由系统登录项记住，关掉开关才会取消。清掉偏好和菜单栏位置：

```sh
defaults delete com.hnl1.cursorquota
```

## 开发

```sh
./scripts/test.sh
./scripts/build.sh
```
