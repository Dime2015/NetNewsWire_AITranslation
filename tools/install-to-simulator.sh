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
BUNDLE_ID="com.ranchero.NetNewsWire.iOS-DEBUG"

BUILT=$(find ~/Library/Developer/Xcode/DerivedData/NetNewsWire-*/Build/Products/Debug-iphonesimulator \
  -maxdepth 1 -name "NetNewsWire.app" -type d | head -1)
[ -z "$BUILT" ] && { echo "❌ 找不到构建产物,先编译"; exit 1; }

xcrun simctl terminate booted "$BUNDLE_ID" 2>/dev/null || true
xcrun simctl install booted "$BUILT"

ACTIVE=$(xcrun simctl get_app_container booted "$BUNDLE_ID" app)

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

xcrun simctl launch booted "$BUNDLE_ID"
