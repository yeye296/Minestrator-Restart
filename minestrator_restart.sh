#!/bin/bash
# ===== 公共配置 =====
SITE_URL="https://minestrator.com"
SERVER_ID=""
SERVER_NAME="MineStrator-FR 🇫🇷"
API_BASE="https://mine.sttr.io"
USER_ID=""
MYBOX_ID=""
RENEW_THRESHOLD_DAYS=7

# ===== Authorization Token =====
API_KEY_B64="${MINESTRATOR_APIKEY:?❌ 环境变量 MINESTRATOR_APIKEY 未设置}"

# ===== 代理配置 =====
if [ -n "$GOST_PROXY" ]; then
  PROXY="-x http://127.0.0.1:8080"
  echo "🛡️ 使用代理模式"
else
  PROXY=""
  echo "🌐 直连模式"
fi

# ===== 验证出口 IP =====
echo "🌐 验证出口IP..."
IP_RAW=$(curl -s $PROXY "https://api.ipify.org?format=json" | grep -o '"ip":"[^"]*"' | cut -d'"' -f4)
IP_MASKED=$(echo "$IP_RAW" | sed 's/\([0-9]*\.[0-9]*\.\).*/\1**.**/') 
echo "✅ 出口IP确认：${IP_MASKED}"
echo ""

# ===== TG 通知函数 =====
notify_and_exit() {
  if [ -n "$TG_BOT" ]; then
    TG_CHAT_ID=$(echo "$TG_BOT" | cut -d',' -f1)
    TG_TOKEN=$(echo "$TG_BOT" | cut -d',' -f2)
    RUN_TIME=$(date '+%Y-%m-%d %H:%M:%S')

    RENEW_LINE="${RENEW_RESULT:-➖ 未触发} (${TEND:-?}d)"

    if [[ "$RESULT" == ✅* ]]; then
      RESTART_LINE="✅ 成功 (4h 0m)"
    else
      RESTART_LINE="${RESULT}"
    fi

    MESSAGE="🎮 Minestrator 日常通知
🕐 运行时间: ${RUN_TIME}
🖥️ 服务器: ${SERVER_NAME}
📅 续期情况: ${RENEW_LINE}
🚀 重启结果: ${RESTART_LINE}"

    curl -s -X POST "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" \
      -d chat_id="${TG_CHAT_ID}" \
      -d text="${MESSAGE}" > /dev/null
    echo "📨 TG 推送成功"
  fi
  echo "========================================"
  if [[ "$RESULT" == ✅* ]]; then
    echo "🎉 任务完成！"
    exit 0
  else
    echo "💀 任务失败！"
    exit 1
  fi
}

# ===== 续期函数 =====
try_renew() {
  echo "🔄 正在发送续期请求..."
  RENEW_RESP=$(curl -s -w "\n%{http_code}" $PROXY \
    -X POST "${API_BASE}/mybox/${MYBOX_ID}/free/renew" \
    -H "accept: */*" \
    -H "authorization: Bearer ${API_KEY_B64}" \
    -H "content-type: application/json" \
    -H "origin: ${SITE_URL}" \
    -H "user-agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36")

  RENEW_CODE=$(echo "$RENEW_RESP" | tail -n1)
  RENEW_BODY=$(echo "$RENEW_RESP" | head -n-1)
  echo "   响应码: ${RENEW_CODE}"
  echo "   响应体: ${RENEW_BODY}"

  case "$RENEW_CODE" in
    200)
      echo "   ✅ 续期成功！"
      RENEW_RESULT="✅ 续期成功"
      ;;
    401)
      echo "   ❌ 续期失败：鉴权失败（token 已过期）"
      RENEW_RESULT="❌ 续期失败"
      ;;
    402)
      echo "   ⌛️ 续期太早，尚未到续期窗口"
      RENEW_RESULT="⌛️ 期限未至"
      ;;
    403)
      echo "   ❌ 续期失败：无权限"
      RENEW_RESULT="❌ 续期失败"
      ;;
    409)
      echo "   ⌛️ 尚未到续期窗口"
      RENEW_RESULT="⌛️ 期限未至"
      ;;
    429)
      echo "   ⚠️ 触发频率限制"
      RENEW_RESULT="❌ 续期失败"
      ;;
    *)
      echo "   ❌ 续期失败：未知状态码 ${RENEW_CODE}"
      RENEW_RESULT="❌ 续期失败"
      ;;
  esac
}

# ===== 读取利用期限函数 =====
fetch_expiry() {
  echo "📡 正在读取服务器利用期限..."
  SERVERS_RESP=$(curl -s $PROXY \
    "${API_BASE}/user/${USER_ID}/servers" \
    -H "accept: */*" \
    -H "authorization: Bearer ${API_KEY_B64}" \
    -H "content-type: application/json" \
    -H "origin: ${SITE_URL}" \
    -H "user-agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/150.0.0.0 Safari/537.36")

  TEND=$(echo "$SERVERS_RESP" | grep -o '"tend_days":[0-9]*' | head -1 | grep -o '[0-9]*')
  TEND_DATE=$(echo "$SERVERS_RESP" | grep -o '"tend":"[^"]*"' | head -1 | sed 's/"tend":"//;s/"//')

  if [ -z "$TEND" ]; then
    echo "   ⚠️ 无法解析利用期限，跳过续期检查"
    TEND_DATE="未知"
    RENEW_RESULT="⚠️ 期限解析失败"
    return
  fi

  echo "   📅 到期时间: ${TEND_DATE}"
  echo "   ⏳ 剩余天数: ${TEND} 天"

  if [ "$TEND" -lt "$RENEW_THRESHOLD_DAYS" ]; then
    echo ""
    echo "⚠️ 剩余天数 (${TEND}) 低于阈值 (${RENEW_THRESHOLD_DAYS})，触发自动续期..."
    try_renew
  else
    echo "   ✅ 剩余天数充足，无需续期"
    RENEW_RESULT="⌛️ 期限未至"
  fi
}

# ===== 重启函数 =====
try_restart() {
  echo "🚀 正在发送重启请求..." >&2
  RESPONSE=$(curl -s -w "\n%{http_code}" $PROXY \
    -X PUT "${API_BASE}/server/${SERVER_ID}/poweraction" \
    -H "accept: application/json" \
    -H "content-type: application/json" \
    -H "authorization: Bearer ${API_KEY_B64}" \
    -H "origin: ${SITE_URL}" \
    -H "user-agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36" \
    -d '{"poweraction":"restart"}')
  local code body
  code=$(echo "$RESPONSE" | tail -n1)
  body=$(echo "$RESPONSE" | head -n-1)
  echo "   响应码: ${code}" >&2
  echo "   响应体: ${body}" >&2
  echo "$code"
}

echo "🔧 Minestrator 日常任务"
echo "========================================"
echo "🕐 运行时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "🖥️ 服务器: ${SERVER_NAME}"
echo ""

# ===== Step 1: 读取期限 & 按需续期 =====
fetch_expiry
echo ""

# ===== Step 2: 发送重启请求 =====
echo "========================================"
START_CODE=$(try_restart)

# ===== 判断重启结果 =====
echo ""
echo "========================================"
case "$START_CODE" in
  200|204)
    RESULT="✅ 成功"
    echo "✅ 服务器重启成功！"
    ;;
  401)
    RESULT="❌ 失败！鉴权失败（token 已过期）"
    ;;
  403)
    RESULT="❌ 失败！无权限操作该服务器"
    ;;
  404)
    RESULT="❌ 失败！服务器 ID 不存在（404）"
    ;;
  409)
    RESULT="❌ 失败！服务器状态冲突（409）"
    ;;
  429)
    RESULT="❌ 失败！触发频率限制（rate limit）"
    ;;
  *)
    RESULT="❌ 失败！未知状态码: ${START_CODE}"
    ;;
esac

notify_and_exit
