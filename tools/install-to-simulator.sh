#!/bin/bash
# 把刚编译的 app 装进模拟器,**并验证系统真的在用这一份**。
#
# ⚠️ 为什么需要这个脚本(2026-07-21 踩过,见 NOTES-lessons L41):
# `xcrun simctl install` 有时会把新版装进一个**新的容器**,
# 而系统注册的仍是旧容器 —— install 照样返回成功,app 照样能启动,
# 但跑的是旧代码。表现为「改了没生效」,而且极难往安装上想:
# 为此排查了一整轮 bug,验证的全是 40 分钟前的旧二进制。
#
# 所以装完必须 cmp 一次;不一致就 rsync 覆盖到系统正在用的那个容器
# (非破坏性,不动数据容器,订阅源和 Keychain 都不会丢)。
#
# ⚠️ 2026-07-22 加固(见 NOTES-lessons L42):Debug 版真正的代码在
# `NetNewsWire.debug.dylib` 里,主可执行文件 `NetNewsWire` 只是个 ~57KB 的 stub。
# 原来只 cmp 主 stub —— 若哪次只有 dylib 变、stub 没变,cmp 会误判「已是新版」
# 而跳过覆盖,又回到那个「测旧代码」的坑。现在把 stub 和 .debug.dylib 都比一遍,
# 任一不一致就整目录覆盖。

set -e
# 模拟器上长期使用的那个 app 的身份。**所有数据(87 个订阅源、已读状态、Keychain 里的
# API Key)都在它名下**,所以不能换成别的,换了等于从空 app 重来。
BUNDLE_ID="com.ranchero.NetNewsWire.iOS-DEBUG"

# ⚠️ 2026-08-05 加的闸门(当天被咬过一次,见 NOTES-lessons L123):
# 本脚本全程用 `simctl ... booted`,而 **`booted` 在有多台模拟器同时启动时是有歧义的** ——
# 它会挑其中一台,而且不告诉你挑了哪台。
# 那天同时开着 iOS 26 和 iOS 27 两台,脚本把新版装到了 27 那台,
# 于是"在 iOS 26 上验证没退化"量的其实是**旧二进制**,得出了一个错误结论。
#
# 现在:多于一台就直接停,并把该用的精确命令打出来。宁可多打一行,也不要静默装错设备。
BOOTED_COUNT=$(xcrun simctl list devices booted | grep -c "Booted" || true)
if [ "$BOOTED_COUNT" -gt 1 ]; then
  echo "❌ 有 $BOOTED_COUNT 台模拟器同时启动着,\`booted\` 会装错设备(见脚本里的说明)。"
  echo "   现在启动着的是:"
  xcrun simctl list devices booted | grep "Booted" | sed 's/^/     /'
  echo ""
  echo "   两条路,选一条:"
  echo "   ① 关掉多余的:  xcrun simctl shutdown <UDID>"
  echo "   ② 指定目标:    SIM_UDID=<UDID> ./tools/install-to-simulator.sh"
  [ -z "${SIM_UDID:-}" ] && exit 1
  echo "   ✅ 已指定 SIM_UDID=$SIM_UDID,继续。"
fi
# 后面所有 simctl 都用这个目标(默认还是 booted,保持原有习惯)
SIM_TARGET="${SIM_UDID:-booted}"

BUILT=$(find ~/Library/Developer/Xcode/DerivedData/NetNewsWire-*/Build/Products/Debug-iphonesimulator \
  -maxdepth 1 -name "NetNewsWire.app" -type d | head -1)
[ -z "$BUILT" ] && { echo "❌ 找不到构建产物,先编译"; exit 1; }

# ⚠️ 2026-07-22 修正(见 NOTES-lessons L49):构建产物的 bundle id 未必等于上面那个。
# 为了装真机,仓库外的 DeveloperSettings.xcconfig 把 ORGANIZATION_IDENTIFIER 改成了
# com.wenbopan(见 T6),于是编译出来的 app 身份变成 com.wenbopan.NetNewsWire.iOS-DEBUG。
# 原来这里无条件跑 `simctl install`,后果是**每次装机都在模拟器上多装出一个同名分身**
# (主屏出现两个 Babel),而真正被覆盖、被启动的仍是 com.ranchero 那个 ——
# 这也是原来「每次都报『系统注册的仍是旧容器』」的真正原因:
# **装的和比的根本是两个不同的 app**,不是 simctl 的毛病(原 L41 的判断需要更正)。
BUILT_ID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$BUILT/Info.plist" 2>/dev/null || echo "")

xcrun simctl terminate "$SIM_TARGET" "$BUNDLE_ID" 2>/dev/null || true

if xcrun simctl get_app_container "$SIM_TARGET" "$BUNDLE_ID" app >/dev/null 2>&1; then
  # 目标 app 已经在模拟器上了 —— **不要再 install**,否则会按构建产物的 id 装出一个分身。
  # 直接把新代码覆盖进它的容器(下面的 rsync 干这件事)。
  [ "$BUILT_ID" != "$BUNDLE_ID" ] && \
    echo "ℹ️  构建产物的 id 是 $BUILT_ID,与模拟器上使用的 $BUNDLE_ID 不同 —— 跳过 install,改为直接覆盖(避免装出分身)"
else
  # 全新模拟器,目标 app 还不存在 → 正常装一次,并以构建产物的 id 为准
  echo "ℹ️  模拟器上还没有这个 app,首次安装"
  xcrun simctl install "$SIM_TARGET" "$BUILT"
  BUNDLE_ID="$BUILT_ID"
fi

ACTIVE=$(xcrun simctl get_app_container "$SIM_TARGET" "$BUNDLE_ID" app)

# 要比对的「带代码的文件」:主可执行文件 + Debug 版的 .debug.dylib(存在才比)。
# Release 版没有 .debug.dylib,代码就在主可执行文件里 —— 那时只比主文件即可。
CODE_FILES=("NetNewsWire")
[ -f "$BUILT/NetNewsWire.debug.dylib" ] && CODE_FILES+=("NetNewsWire.debug.dylib")

matches_all() {
  for f in "${CODE_FILES[@]}"; do
    cmp -s "$ACTIVE/$f" "$BUILT/$f" || return 1
  done
  return 0
}

if ! matches_all; then
  echo "⚠️  系统注册的仍是旧容器(stub 或 dylib 不一致),改用覆盖方式"
  rsync -a --delete "$BUILT/" "$ACTIVE/"
fi

if matches_all; then
  echo "✅ 已确认系统正在用刚编译的这一份(stub + dylib 均一致)"
else
  echo "❌ 仍然不一致,别相信接下来的测试结果"; exit 1
fi

xcrun simctl launch "$SIM_TARGET" "$BUNDLE_ID"
