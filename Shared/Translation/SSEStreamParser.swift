//
//  SSEStreamParser.swift
//  NetNewsWire — AI 翻译 fork
//
//  [翻译] 流式响应(SSE)的**逐行解析**。本 fork 新增,上游没有。
//
//  ## 为什么单独一个文件
//
//  和 `DropZoneResolver` / `ReadingModeRules` 同一个理由(L63 的纪律):
//  这是纯逻辑、不碰网络也不碰 UI,拆出来之后 `tools/sim-sse.swift` 能把本文件
//  **原样编译**、喂罐头数据跑决策表 —— 流式这种"只有真请求才走到"的路径,
//  解析层必须先离线验完,别把解析 bug 留到线上和网络问题搅在一起。
//
//  ## SSE 是什么样子(OpenAI 兼容格式)
//
//  流式响应是一行行来的:
//      data: {"choices":[{"delta":{"content":"你"}}]}
//      data: {"choices":[{"delta":{"content":"好"}}]}
//      data: [DONE]
//  另外会混着注释行(OpenRouter 的心跳是 ": OPENROUTER PROCESSING")和空行,都要跳过。
//

import Foundation

/// 一行 SSE 数据解析出什么。
enum SSELineEvent: Equatable {
	/// 增量文字(拼起来就是完整回复)
	case delta(String)
	/// 流结束(data: [DONE])
	case done
	/// 该忽略的行:空行、注释/心跳、没有内容的元数据帧(role 帧、usage 帧等)
	case ignore
}

enum SSEStreamParser {

	private struct StreamChunk: Decodable {
		struct Choice: Decodable {
			struct Delta: Decodable {
				let content: String?
			}
			let delta: Delta?
		}
		let choices: [Choice]?
	}

	/// 解析一行。**一次一行**,行的切分交给 `URLSession.bytes.lines`(它保证给的是完整行)。
	static func parse(line: String) -> SSELineEvent {

		let trimmed = line.trimmingCharacters(in: .whitespaces)

		// 空行 = SSE 的事件分隔;":" 开头 = 注释(OpenRouter 拿它当心跳)
		guard !trimmed.isEmpty, !trimmed.hasPrefix(":") else {
			return .ignore
		}

		// 只认 data: 行。event:/id: 这些字段 OpenAI 兼容流里用不到
		guard trimmed.hasPrefix("data:") else {
			return .ignore
		}

		let payload = trimmed.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)

		if payload == "[DONE]" {
			return .done
		}

		// 解不开的 JSON 一律忽略,不让一帧坏数据打断整条流 ——
		// 内容帧丢了会表现为"少几个字",但最终显示用的是完整译文(流完后整块替换),无害
		guard let data = payload.data(using: .utf8),
			  let chunk = try? JSONDecoder().decode(StreamChunk.self, from: data),
			  let content = chunk.choices?.first?.delta?.content,
			  !content.isEmpty else {
			return .ignore
		}

		return .delta(content)
	}
}
