# ALOS CTS 测试环境搭建 BKC

**平台**: ALOS (Android-on-x86) / DMR  
**日期**: 2026-05-30  
**作者**: sjh  
**ECG 跳板机**: alos-ecg-1@10.239.58.154  
**DUT**: 10.239.58.115:5555  
**CTS 版本**: android-cts (~/sjh/android-cts)  

---

## 1. 环境说明

| 角色 | 地址 | 备注 |
|------|------|------|
| 跳板机 (ECG) | alos-ecg-1@10.239.58.154 | Ubuntu，运行 cts-tradefed |
| DUT | 10.239.58.115:5555 | ALOS 设备，通过 adb over TCP 连接 |
| CTS 目录 | ~/sjh/android-cts/ | 已解压，tools/ 下有启动脚本 |

---

## 2. 前置条件

### 2.1 Java 版本要求

CTS 运行需要 **Java 21**，默认系统 Java 版本不够时需手动安装：

```bash
sudo apt install openjdk-21-jdk -y
export JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64
export PATH=$JAVA_HOME/bin:$PATH
java -version  # 确认 openjdk 21
```

> **注意**：Java 版本不对会导致 `DevicePolicyUsersPreparer` 报错。

### 2.2 adb 连接 DUT

```bash
adb connect 10.239.58.115:5555
adb devices  # 确认设备在线
```

### 2.3 设置 DUT 永不休眠、不灭屏

```bash
adb shell settings put system screen_off_timeout 2147483647
adb shell svc power stayon true
# 验证
adb shell settings get system screen_off_timeout  # 应返回 2147483647
```

---

## 3. 代理配置

### 3.1 ECG 跳板机代理（/etc/environment）

ECG 默认无法直连 Google，需配置代理：

```bash
sudo tee -a /etc/environment << 'EOF'
http_proxy="http://child-prc.intel.com:913"
https_proxy="http://child-prc.intel.com:913"
HTTP_PROXY="http://child-prc.intel.com:913"
HTTPS_PROXY="http://child-prc.intel.com:913"
no_proxy="localhost,127.0.0.1,10.0.0.0/8,192.168.0.0/16,172.16.0.0/12,intel.com,*.intel.com"
NO_PROXY="localhost,127.0.0.1,10.0.0.0/8,192.168.0.0/16,172.16.0.0/12,intel.com,*.intel.com"
EOF
```

重新 SSH 登录后生效，验证：

```bash
source /etc/environment
curl -s -o /dev/null -w "%{http_code}" https://www.google.com  # 应返回 200
```

### 3.2 DUT 代理配置（Android 系统层）

让 Android Java 层（HttpURLConnection）走代理：

```bash
adb shell settings put global http_proxy child-prc.intel.com:913
# 验证
adb shell settings get global http_proxy  # 应返回 child-prc.intel.com:913
```

> **说明**：Android shell 层的 curl 不读此配置，需用 `http_proxy=xxx curl ...` 显式指定。  
> CTS 测试用的 Java 网络层（HttpURLConnection）会读取此 settings。

---

## 4. CTS JAR 修复（关键！）

### 4.1 问题一：DynamicConfigPusher 超时

**现象**：cts-tradefed 启动测试时卡住，尝试从 Google 服务器拉取动态配置超时。

**解决方案**：在 `cts-tradefed.jar` 中注入空的 `cts.dynamic` 配置文件，绕过网络请求：

```bash
cd /tmp
mkdir -p dcp-fix/config && cd dcp-fix
cat > config/cts.dynamic << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<dynamicConfig><entries></entries></dynamicConfig>
EOF
cp ~/sjh/android-cts/tools/cts-tradefed.jar ~/sjh/android-cts/tools/cts-tradefed.jar.bak
cd /tmp/dcp-fix && zip ~/sjh/android-cts/tools/cts-tradefed.jar config/cts.dynamic
```

### 4.2 问题二：ReportIntegrityCollector 超时（关键修复）

**现象**：测试 setUp 阶段卡住约 3 分钟后退出，日志显示 `cmd remote_provisioning csr` 命令超时。

**根因**：`ReportIntegrityCollector.setUp()` 调用了 `adb shell cmd remote_provisioning csr`，ALOS 设备不支持此命令导致超时。

**⚠️ 重要**：该 class 存在于**两个 JAR** 中，必须同时 patch，否则仍会超时：
- `cts-tradefed.jar`
- `compatibility-tradefed.jar`

**解决步骤**：

```bash
TOOLS=~/sjh/android-cts/tools
mkdir -p /tmp/ric-stub
cat > /tmp/ric-stub/ReportIntegrityCollector.java << 'EOF'
package com.android.compatibility.common.tradefed.targetprep;
import com.android.tradefed.config.Option;
import com.android.tradefed.device.DeviceNotAvailableException;
import com.android.tradefed.invoker.TestInformation;
import com.android.tradefed.targetprep.BuildError;
import com.android.tradefed.targetprep.ITargetPreparer;
import com.android.tradefed.targetprep.TargetSetupError;
public class ReportIntegrityCollector implements ITargetPreparer {
    @Option(name = "src-dir", description = "stub") private String mSrcDir = "";
    @Option(name = "dest-dir", description = "stub") private String mDestDir = "";
    @Option(name = "temp-dir", description = "stub") private String mTempDir = "";
    @Override
    public void setUp(TestInformation info)
            throws TargetSetupError, BuildError, DeviceNotAvailableException {}
}
EOF

cd /tmp/ric-stub
javac -cp "$TOOLS/cts-tradefed.jar:$TOOLS/compatibility-tradefed.jar:$TOOLS/tradefed.jar" \
    -source 8 -target 8 ReportIntegrityCollector.java

mkdir -p com/android/compatibility/common/tradefed/targetprep
cp ReportIntegrityCollector.class com/android/compatibility/common/tradefed/targetprep/

# 备份并 patch 两个 jar（缺一不可！）
cp $TOOLS/cts-tradefed.jar $TOOLS/cts-tradefed.jar.bak2
cp $TOOLS/compatibility-tradefed.jar $TOOLS/compatibility-tradefed.jar.bak

zip $TOOLS/cts-tradefed.jar \
    com/android/compatibility/common/tradefed/targetprep/ReportIntegrityCollector.class
zip $TOOLS/compatibility-tradefed.jar \
    com/android/compatibility/common/tradefed/targetprep/ReportIntegrityCollector.class
```

---

## 5. 运行 CTS 测试

### 5.1 在 tmux 中启动 cts-tradefed

```bash
# 创建 tmux session
tmux new-session -d -s cts

# 设置 Java 21 环境并启动
tmux send-keys -t cts "export JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64 && export PATH=\$JAVA_HOME/bin:\$PATH" Enter
tmux send-keys -t cts "cd ~/sjh/android-cts/tools && ./cts-tradefed" Enter

# 等待出现 cts-tf > 提示符后 attach 查看
tmux attach -t cts
```

### 5.2 连接设备并运行模块

在 `cts-tf >` 提示符下：

```
add-device 10.239.58.115:5555
run cts -m CtsOsTestCases
```

### 5.3 查看结果

```
list results
```

### 5.4 从 tmux 外部查看进度（不 attach）

```bash
tmux capture-pane -t cts -p | tail -20
```

---

## 6. cts-tradefed 重启注意事项

- 在 `cts-tf >` 下执行 `exit` 会同时关闭 cts-tradefed 进程和 tmux bash session
- 正确重启方式：先 `Ctrl+C` 中断，再在 bash 下重新运行 `./cts-tradefed`
- 从外部发命令：`tmux send-keys -t cts 'command' Enter`

---

## 7. 已知 Fail 项说明

| 测试项 | 原因 | 是否平台 Bug |
|--------|------|-------------|
| `StrictModeTest#testEncryptedNetwork` | 代理环境下网络行为与预期不符 | 否，环境原因 |
| `testUntaggedSocketsRaw` | ALOS 上 socket tagging 支持不完整 | 待确认 |

---

## 8. 测试结果（参考）

**模块**: `CtsOsTestCases`  
**日期**: 2026-05-30  
**Build**: `CL2B.260326.001` (ocelot / x86_64)  

| 指标 | 数值 |
|------|------|
| Pass | 1701 |
| Fail | 15 |
| Modules 完成 | 3/3 |

**结果路径**：
```
~/sjh/android-cts/results/2026.05.30_05.10.20/
~/sjh/android-cts/results/2026.05.30_05.10.20.zip
```

---

## 9. 修改文件清单

| 文件（ECG 上） | 修改内容 |
|----------------|---------|
| `/etc/environment` | 新增 Intel 代理配置 |
| `~/sjh/android-cts/tools/cts-tradefed.jar` | 注入 DynamicConfigPusher 绕过 + ReportIntegrityCollector stub |
| `~/sjh/android-cts/tools/compatibility-tradefed.jar` | 注入 ReportIntegrityCollector stub |
| DUT `settings global http_proxy` | 设置 Android 代理（adb 命令，重启后需重设） |

**备份文件**：
- `cts-tradefed.jar.bak2`
- `compatibility-tradefed.jar.bak`
