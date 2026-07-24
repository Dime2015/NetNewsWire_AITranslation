//
//  sim-sse.swift
//  翻译流式输出 —— SSE 逐行解析的离线验证
//
//  ## 怎么跑
//
//  ```bash
//  swiftc -o /tmp/sim-sse \
//    "Shared/Translation/SSEStreamParser.swift" "tools/sim-sse.swift" && /tmp/sim-sse
//  ```
//
//  ## 为什么要有它(L63 的纪律)
//
//  流式解析只有发真请求才走得到,出了 bug 会和网络问题搅在一起没法定位。
//  这里喂罐头数据把解析层单独验干净 —— 验的是**真代码**(上面那行把
//  SSEStreamParser.swift 原样编译进来),不是抄一份副本。
//
//  ⚠️ 验不了的:真实网络的分包时序、取消传播、赛跑逻辑。那些靠用户实测。
//

import Foundation

@main
struct SimSSE {

	static var failures = 0

	static func check(_ label: String, line: String, expect: SSELineEvent) {
		let got = SSEStreamParser.parse(line: line)
		let ok = got == expect
		if !ok { failures += 1 }
		print("\(ok ? "✅" : "❌")  \(label)")
		if !ok {
			print("      输入: \(line)")
			print("      得到: \(got) / 期望: \(expect)")
		}
	}

	static func main() {

		print("=== 正常内容帧 ===")
		check("标准 delta", line: #"data: {"choices":[{"delta":{"content":"你"}}]}"#, expect: .delta("你"))
		check("data: 后没空格", line: #"data:{"choices":[{"delta":{"content":"好"}}]}"#, expect: .delta("好"))
		check("内容含 HTML 标签", line: #"data: {"choices":[{"delta":{"content":"<p>段落"}}]}"#, expect: .delta("<p>段落"))
		check("内容含转义引号", line: #"data: {"choices":[{"delta":{"content":"他说\"好\""}}]}"#, expect: .delta("他说\"好\""))
		check("行尾带回车(\\r\\n 换行的流)", line: "data: {\"choices\":[{\"delta\":{\"content\":\"字\"}}]}\r", expect: .delta("字"))

		print("")
		print("=== 结束与忽略 ===")
		check("[DONE]", line: "data: [DONE]", expect: .done)
		check("空行(事件分隔)", line: "", expect: .ignore)
		check("OpenRouter 心跳注释", line: ": OPENROUTER PROCESSING", expect: .ignore)
		check("role 帧(第一帧常见,无内容)", line: #"data: {"choices":[{"delta":{"role":"assistant"}}]}"#, expect: .ignore)
		check("空内容帧", line: #"data: {"choices":[{"delta":{"content":""}}]}"#, expect: .ignore)
		check("usage 帧(结尾常见,choices 为空)", line: #"data: {"choices":[],"usage":{"total_tokens":42}}"#, expect: .ignore)
		check("坏 JSON 不炸、不断流", line: "data: {oops", expect: .ignore)
		check("event: 字段行", line: "event: message", expect: .ignore)

		print("")
		print("=== 整条流拼装(模拟真实顺序)===")
		let stream = [
			": OPENROUTER PROCESSING",
			#"data: {"choices":[{"delta":{"role":"assistant"}}]}"#,
			#"data: {"choices":[{"delta":{"content":"<p>"}}]}"#,
			#"data: {"choices":[{"delta":{"content":"谷歌"}}]}"#,
			"",
			#"data: {"choices":[{"delta":{"content":"被罚款了。</p>"}}]}"#,
			#"data: {"choices":[],"usage":{"total_tokens":9}}"#,
			"data: [DONE]"
		]
		var accumulated = ""
		var sawDone = false
		for line in stream {
			switch SSEStreamParser.parse(line: line) {
			case .delta(let text): accumulated += text
			case .done: sawDone = true
			case .ignore: break
			}
		}
		let assembled = accumulated == "<p>谷歌被罚款了。</p>" && sawDone
		if !assembled { failures += 1 }
		print("\(assembled ? "✅" : "❌")  八行流拼出完整译文且识别到结束(得到:\(accumulated))")

		print("")
		print(String(repeating: "─", count: 56))
		if failures == 0 {
			print("🎉 全部通过")
			exit(0)
		} else {
			print("💥 有 \(failures) 条没过")
			exit(1)
		}
	}
}
