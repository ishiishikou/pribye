#if canImport(LiteRTLM)
import LiteRTLM

// LiteRT-LM v0.14.0 returns Conversation from its Engine actor without
// declaring Conversation as Sendable. The upstream API is designed for this
// actor-boundary crossing, and Pribye keeps each conversation local and uses it
// sequentially, so bridge the missing concurrency annotation until upstream
// provides one.
extension Conversation: @unchecked @retroactive Sendable {}
#endif
