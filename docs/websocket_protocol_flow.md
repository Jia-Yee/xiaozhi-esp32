# Xiaozhi-ESP32 WebSocket 协议连接流程文档

## 📋 概述

本文档详细描述了 Xiaozhi-ESP32 项目中使用 WebSocket 协议与服务器进行语音交互的完整流程。该协议与 xiaozhi.me 官方 API 使用相同的业务逻辑和消息格式。

---

## 🔄 完整连接流程

### 1. 打开音频通道 (OpenAudioChannel)

#### 步骤 1: 创建 WebSocket 连接
```cpp
// 从 NVS 读取配置，如果未配置则使用默认值
std::string url = "ws://192.168.3.231:8080";
websocket_ = network->CreateWebSocket(1);
websocket_->Connect(url.c_str());
```

#### 步骤 2: 设置请求头
```cpp
websocket_->SetHeader("Protocol-Version", "1");
websocket_->SetHeader("Device-Id", "<MAC 地址>");
websocket_->SetHeader("Client-Id", "<设备 UUID>");
// 如果有 token，添加 Authorization header
if (!token.empty()) {
    websocket_->SetHeader("Authorization", "Bearer " + token);
}
```

#### 步骤 3: 发送 Hello 消息（JSON）
```json
{
  "type": "hello",
  "version": 1,
  "features": {
    "mcp": true,
    "aec": true  // 可选，如果启用了 AEC
  },
  "transport": "websocket",
  "audio_params": {
    "format": "opus",
    "sample_rate": 16000,
    "channels": 1,
    "frame_duration": 60  // 单位：毫秒
  }
}
```

#### 步骤 4: 等待服务器 Hello 响应
```cpp
// 等待服务器返回 hello 响应，超时时间 10 秒
EventBits_t bits = xEventGroupWaitBits(
    event_group_handle_, 
    WEBSOCKET_PROTOCOL_SERVER_HELLO_EVENT, 
    pdTRUE, 
    pdFALSE, 
    pdMS_TO_TICKS(10000)
);
```

**服务器响应示例：**
```json
{
  "type": "hello",
  "session_id": "abc123xyz",
  "transport": "websocket",
  "audio_params": {
    "sample_rate": 24000,
    "frame_duration": 60
  }
}
```

#### 步骤 5: 触发 OnAudioChannelOpened 回调
```cpp
if (on_audio_channel_opened_ != nullptr) {
    on_audio_channel_opened_();
}
```

---

### 2. 语音交互流程

#### 2.1 唤醒词检测 → 发送 Listen 消息

**当检测到唤醒词时：**
```cpp
// SendWakeWordDetected("你好小智")
SendText("{\"session_id\":\"abc123xyz\",\"type\":\"listen\",\"state\":\"detect\",\"text\":\"你好小智\"}");
```

**消息格式：**
```json
{
  "session_id": "abc123xyz",
  "type": "listen",
  "state": "detect",
  "text": "你好小智"
}
```

#### 2.2 开始监听 → 发送 Start Listening

**根据监听模式发送不同的消息：**
```cpp
// SendStartListening(kListeningModeRealtime)
SendText("{\"session_id\":\"abc123xyz\",\"type\":\"listen\",\"state\":\"start\",\"mode\":\"realtime\"}");
```

**模式选项：**
- `realtime`: 实时模式（需要 AEC 支持）
- `auto`: 自动停止模式（依赖 VAD 检测）
- `manual`: 手动停止模式

**消息格式：**
```json
{
  "session_id": "abc123xyz",
  "type": "listen",
  "state": "start",
  "mode": "realtime"  // 或 "auto" / "manual"
}
```

#### 2.3 发送音频流 → 二进制 Opus 数据

**发送音频帧：**
```cpp
// SendAudio(packet)
if (version_ == 2) {
    // 协议版本 2：带二进制头
    BinaryProtocol2 bp2;
    bp2.version = htons(version_);
    bp2.type = 0;  // 0 表示 Opus 音频
    bp2.timestamp = htonl(packet->timestamp);
    bp2.payload_size = htonl(packet->payload.size());
    websocket_->Send(&bp2, sizeof(bp2) + packet->payload.size(), true);
} else if (version_ == 3) {
    // 协议版本 3：简化二进制头
    BinaryProtocol3 bp3;
    bp3.type = 0;
    bp3.payload_size = htons(packet->payload.size());
    websocket_->Send(&bp3, sizeof(bp3) + packet->payload.size(), true);
} else {
    // 协议版本 1：直接发送原始 Opus 数据
    websocket_->Send(packet->payload.data(), packet->payload.size(), true);
}
```

**音频参数：**
- **编码格式**: Opus
- **采样率**: 16000 Hz
- **声道**: 单声道
- **帧时长**: 60ms
- **应用模式**: OPUS_APPLICATION_AUDIO

#### 2.4 停止监听 → 发送 Stop Listening

**当 VAD 检测到语音结束或用户手动停止时：**
```cpp
// SendStopListening()
SendText("{\"session_id\":\"abc123xyz\",\"type\":\"listen\",\"state\":\"stop\"}");
```

**消息格式：**
```json
{
  "session_id": "abc123xyz",
  "type": "listen",
  "state": "stop"
}
```

#### 2.5 打断说话 → 发送 Abort

**当检测到新的唤醒词需要打断当前对话时：**
```cpp
// SendAbortSpeaking(kAbortReasonWakeWordDetected)
SendText("{\"session_id\":\"abc123xyz\",\"type\":\"abort\",\"reason\":\"wake_word_detected\"}");
```

**消息格式：**
```json
{
  "session_id": "abc123xyz",
  "type": "abort",
  "reason": "wake_word_detected"  // 可选
}
```

---

### 3. 接收服务器消息

#### 3.1 TTS 文本 → 播放语音

**收到服务器的 TTS 消息：**
```json
{
  "type": "tts",
  "text": "您好，我是小智，有什么可以帮您？"
}
```

**处理逻辑：**
1. 将文本添加到 TTS 引擎
2. 开始播放语音
3. 状态切换到 `speaking`

#### 3.2 TTS 结束 → 停止播放

**收到服务器的 TTS 停止消息：**
```json
{
  "type": "tts_stop"
}
```

**处理逻辑：**
1. 停止 TTS 播放
2. 状态切换回 `listening`（多轮对话）或 `idle`（单次对话）

#### 3.3 服务器再见 → 关闭通道

**收到服务器的 goodbye 消息：**
```json
{
  "type": "goodbye",
  "session_id": "abc123xyz"
}
```

**处理逻辑：**
1. 关闭 WebSocket 连接
2. 清理资源
3. 状态重置为 `idle`

---

## 📊 状态机流转图

```
┌─────────────┐
│    Idle     │ ←──────────────────────────────┐
│   (空闲)     │                                │
└──────┬──────┘                                │
       │ 唤醒词检测                             │
       ▼                                        │
┌─────────────┐                                │
│ Connecting  │                                │
│  (连接中)    │                                │
└──────┬──────┘                                │
       │ 发送 wake_word_detected                │
       ▼                                        │
┌─────────────┐                                │
│  Listening  │                                │
│   (监听中)   │                                │
└──────┬──────┘                                │
       │                                        │
       ├─→ 发送 start_listening                 │
       │   发送音频流                           │
       │                                        │
       ├─→ 收到 tts                             │
       ▼                                        │
┌─────────────┐                                │
│  Speaking   │                                │
│   (说话中)   │                                │
└──────┬──────┘                                │
       │                                        │
       ├─→ 收到 tts_stop                        │
       │   └────────────────────────────────────┘
       │        (多轮对话：回到 listening)
       │
       ├─→ 超时 10 分钟无活动
       ▼
┌─────────────┐
│    Idle     │
│   (空闲)     │
└─────────────┘
```

---

## 🔍 WebSocket vs MQTT 对比

| 特性 | WebSocket 协议 | MQTT 协议 |
|------|---------------|-----------|
| **连接方式** | `ws://host:port` | `mqtt://host:8883` (TLS) |
| **消息格式** | JSON + 二进制帧 | JSON (MQTT) + UDP (音频) |
| **音频传输** | WebSocket 二进制消息 | UDP 数据包 |
| **认证方式** | Header (Authorization) | MQTT username/password |
| **Hello 消息** | 包含 audio_params | 基本相同 |
| **Listen 消息** | `{"type":"listen",...}` | **完全相同** |
| **TTS 消息** | `{"type":"tts",...}` | **完全相同** |
| **状态流转** | idle→connecting→listening→speaking | **完全相同** |

---

## 💡 关键实现细节

### 1. 协议版本兼容性

```cpp
// 协议版本 1：原始 Opus 数据（最简单）
websocket_->Send(opus_data, size, true);

// 协议版本 2：带完整二进制头（支持时间戳）
struct BinaryProtocol2 {
    uint16_t version;      // 版本号 (2)
    uint16_t type;         // 消息类型 (0=Opus)
    uint32_t reserved;     // 保留字段
    uint32_t timestamp;    // 时间戳（用于 AEC）
    uint32_t payload_size; // 负载大小
    uint8_t payload[];     // Opus 数据
};

// 协议版本 3：简化二进制头
struct BinaryProtocol3 {
    uint8_t type;          // 消息类型 (0=Opus)
    uint8_t reserved;      // 保留字段
    uint16_t payload_size; // 负载大小
    uint8_t payload[];     // Opus 数据
};
```

### 2. Server Hello 解析

```cpp
void WebsocketProtocol::ParseServerHello(const cJSON* root) {
    // 验证 transport 类型
    auto transport = cJSON_GetObjectItem(root, "transport");
    if (strcmp(transport->valuestring, "websocket") != 0) {
        ESP_LOGE(TAG, "Unsupported transport: %s", transport->valuestring);
        return;
    }

    // 保存 session_id
    auto session_id = cJSON_GetObjectItem(root, "session_id");
    if (cJSON_IsString(session_id)) {
        session_id_ = session_id->valuestring;
        ESP_LOGI(TAG, "Session ID: %s", session_id_.c_str());
    }

    // 解析音频参数
    auto audio_params = cJSON_GetObjectItem(root, "audio_params");
    if (cJSON_IsObject(audio_params)) {
        auto sample_rate = cJSON_GetObjectItem(audio_params, "sample_rate");
        if (cJSON_IsNumber(sample_rate)) {
            server_sample_rate_ = sample_rate->valueint;
        }
        auto frame_duration = cJSON_GetObjectItem(audio_params, "frame_duration");
        if (cJSON_IsNumber(frame_duration)) {
            server_frame_duration_ = frame_duration->valueint;
        }
    }

    // 触发 Server Hello 事件
    xEventGroupSetBits(event_group_handle_, WEBSOCKET_PROTOCOL_SERVER_HELLO_EVENT);
}
```

### 3. 错误处理

```cpp
// 连接失败
if (!websocket_->Connect(url.c_str())) {
    ESP_LOGE(TAG, "Failed to connect to websocket server, code=%d", 
             websocket_->GetLastError());
    SetError(Lang::Strings::SERVER_NOT_CONNECTED);
    return false;
}

// 发送失败
bool WebsocketProtocol::SendText(const std::string& text) {
    if (websocket_ == nullptr || !websocket_->IsConnected()) {
        return false;
    }
    if (!websocket_->Send(text)) {
        ESP_LOGE(TAG, "Failed to send text: %s", text.c_str());
        SetError(Lang::Strings::SERVER_ERROR);
        return false;
    }
    return true;
}

// 超时检测
bool Protocol::IsTimeout() const {
    const int kTimeoutSeconds = 120;
    auto now = std::chrono::steady_clock::now();
    auto duration = std::chrono::duration_cast<std::chrono::seconds>(
        now - last_incoming_time_);
    bool timeout = duration.count() > kTimeoutSeconds;
    if (timeout) {
        ESP_LOGE(TAG, "Channel timeout %ld seconds", (long)duration.count());
    }
    return timeout;
}
```

---

## 🛠️ 调试技巧

### 1. 启用详细日志

```cpp
// 在 websocket_protocol.cc 中添加调试日志
ESP_LOGI(TAG, "=== DEBUG: Received %s message, len=%zu ===", 
         binary ? "BINARY" : "JSON", len);

ESP_LOGI(TAG, "=== DEBUG: Received JSON: %.*s ===", (int)len, data);
```

### 2. 检查关键点

1. **WebSocket 连接是否成功？**
   - 查看日志：`Connecting to websocket server: ws://...`
   - 确认服务器是否运行在正确端口

2. **是否收到 Server Hello？**
   - 查看日志：`Failed to receive server hello`
   - 检查服务器是否正确响应

3. **音频参数是否匹配？**
   - 对比客户端发送的 `audio_params` 和服务器返回的参数
   - 确保采样率、帧时长一致

4. **状态机是否正确流转？**
   - 观察日志中的状态变化
   - 确认每个消息都触发了正确的状态转换

---

## 📝 示例代码

### 完整的语音对话流程

```cpp
// 1. 打开音频通道
if (!protocol_->OpenAudioChannel()) {
    ESP_LOGE(TAG, "Failed to open audio channel");
    return;
}

// 2. 唤醒词检测
protocol_->SendWakeWordDetected("你好小智");

// 3. 开始监听（实时模式）
protocol_->SendStartListening(kListeningModeRealtime);

// 4. 持续发送音频数据
while (is_speaking_) {
    auto packet = audio_service_->PopAudioPacket();
    if (packet) {
        protocol_->SendAudio(std::move(packet));
    }
}

// 5. 停止监听
protocol_->SendStopListening();

// 6. 等待服务器响应（TTS）
// ... 异步接收 on_incoming_json_ 回调 ...

// 7. 如果需要打断
protocol_->SendAbortSpeaking(kAbortReasonWakeWordDetected);

// 8. 关闭音频通道
protocol_->CloseAudioChannel(false);
```

---

## 🎯 总结

WebSocket 协议提供了简单而强大的方式来构建语音交互系统：

1. ✅ **单一连接**: 所有数据（信令 + 音频）通过一个 WebSocket 连接传输
2. ✅ **与 xiaozhi.me 兼容**: 使用相同的消息格式和状态流转
3. ✅ **易于调试**: 可以在浏览器开发者工具中查看完整的通信过程
4. ✅ **灵活扩展**: 支持多种协议版本和监听模式

本地服务器只需要实现标准的 WebSocket 服务端，按照本文档定义的消息格式进行通信即可！
