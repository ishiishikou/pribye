import Foundation
import XCTest
@testable import Pribye

final class GemmaEnginePoolTests: XCTestCase {
  private let modelURL = URL(fileURLWithPath: "/tmp/test-model.litertlm")
  private let modelSHA256 = "test-model-sha"

  func testConsecutiveRequestsInitializeSameEngineOnce() async throws {
    let factory = TestGemmaInferenceEngineFactory()
    let pool = GemmaEnginePool(factory: factory)

    _ = try await generate(using: pool, backend: .gpu)
    _ = try await generate(using: pool, backend: .gpu)

    let initializationCount = await factory.initializationCount(for: .gpu)
    XCTAssertEqual(initializationCount, 1)
  }

  func testEachRequestCreatesConversationEquivalentWork() async throws {
    let factory = TestGemmaInferenceEngineFactory()
    let pool = GemmaEnginePool(factory: factory)

    _ = try await generate(using: pool, backend: .gpu)
    _ = try await generate(using: pool, backend: .gpu)

    let generationCount = await factory.generationCount(for: .gpu)
    XCTAssertEqual(generationCount, 2)
  }

  func testInitializationFailureLeavesNoCachedEngine() async throws {
    let factory = TestGemmaInferenceEngineFactory()
    await factory.failNextInitialization(for: .gpu)
    let pool = GemmaEnginePool(factory: factory)

    do {
      _ = try await generate(using: pool, backend: .gpu)
      XCTFail("Expected Engine initialization to fail.")
    } catch TestGemmaEngineError.initializationFailed {
      // Expected.
    }

    let failedSnapshot = await pool.snapshot()
    XCTAssertNil(failedSnapshot.cachedBackend)

    _ = try await generate(using: pool, backend: .gpu)
    let initializationCount = await factory.initializationCount(for: .gpu)
    XCTAssertEqual(initializationCount, 2)
  }

  func testBackendFailureDiscardsCachedEngine() async throws {
    let factory = TestGemmaInferenceEngineFactory()
    let pool = GemmaEnginePool(factory: factory)

    _ = try await generate(using: pool, backend: .gpu)
    await factory.failNextGeneration(for: .gpu)

    do {
      _ = try await generate(using: pool, backend: .gpu)
      XCTFail("Expected the generated response to fail.")
    } catch TestGemmaEngineError.generationFailed {
      // Expected.
    }

    let failedSnapshot = await pool.snapshot()
    XCTAssertNil(failedSnapshot.cachedBackend)

    _ = try await generate(using: pool, backend: .gpu)
    let initializationCount = await factory.initializationCount(for: .gpu)
    XCTAssertEqual(initializationCount, 2)
  }

  func testBackendSwitchDoesNotReuseOldEngine() async throws {
    let factory = TestGemmaInferenceEngineFactory()
    let pool = GemmaEnginePool(factory: factory)

    _ = try await generate(using: pool, backend: .gpu)
    _ = try await generate(using: pool, backend: .cpu)
    _ = try await generate(using: pool, backend: .gpu)

    let gpuInitializationCount = await factory.initializationCount(for: .gpu)
    let cpuInitializationCount = await factory.initializationCount(for: .cpu)
    XCTAssertEqual(gpuInitializationCount, 2)
    XCTAssertEqual(cpuInitializationCount, 1)
  }

  func testIdleTimeoutReleasesEngine() async throws {
    let factory = TestGemmaInferenceEngineFactory()
    let sleeper = ManualGemmaEngineIdleSleeper()
    let pool = GemmaEnginePool(
      factory: factory,
      idleTimeout: .seconds(300),
      idleSleeper: sleeper
    )

    _ = try await generate(using: pool, backend: .gpu)
    await waitUntil { await sleeper.pendingSleepCount() == 1 }

    await sleeper.resumeNextSleep()
    await waitUntil { await pool.snapshot().cachedBackend == nil }
  }

  func testReuseBeforeTimeoutPostponesRelease() async throws {
    let factory = TestGemmaInferenceEngineFactory()
    let sleeper = ManualGemmaEngineIdleSleeper()
    let pool = GemmaEnginePool(
      factory: factory,
      idleTimeout: .seconds(300),
      idleSleeper: sleeper
    )

    _ = try await generate(using: pool, backend: .gpu)
    await waitUntil { await sleeper.pendingSleepCount() == 1 }

    _ = try await generate(using: pool, backend: .gpu)
    await waitUntil { await sleeper.pendingSleepCount() == 2 }

    await sleeper.resumeNextSleep()
    await settleActorWork()
    let snapshotAfterOldTimer = await pool.snapshot()
    XCTAssertEqual(snapshotAfterOldTimer.cachedBackend, .gpu)

    await sleeper.resumeNextSleep()
    await waitUntil { await pool.snapshot().cachedBackend == nil }
  }

  func testOldIdleTimerDoesNotReleaseNewEngine() async throws {
    let factory = TestGemmaInferenceEngineFactory()
    let sleeper = ManualGemmaEngineIdleSleeper()
    let pool = GemmaEnginePool(
      factory: factory,
      idleTimeout: .seconds(300),
      idleSleeper: sleeper
    )

    _ = try await generate(using: pool, backend: .gpu)
    await waitUntil { await sleeper.pendingSleepCount() == 1 }

    _ = try await generate(using: pool, backend: .cpu)
    await waitUntil { await sleeper.pendingSleepCount() == 2 }

    await sleeper.resumeNextSleep()
    await settleActorWork()
    let snapshotAfterOldTimer = await pool.snapshot()
    XCTAssertEqual(snapshotAfterOldTimer.cachedBackend, .cpu)

    await sleeper.resumeNextSleep()
    await waitUntil { await pool.snapshot().cachedBackend == nil }
  }

  func testMemoryWarningReleaseClearsCachedEngine() async throws {
    let factory = TestGemmaInferenceEngineFactory()
    let pool = GemmaEnginePool(factory: factory)

    _ = try await generate(using: pool, backend: .gpu)
    await pool.releaseForMemoryWarning()

    let snapshot = await pool.snapshot()
    XCTAssertNil(snapshot.cachedBackend)
  }

  func testReleaseDuringInferenceWaitsForSafeCompletion() async throws {
    let factory = TestGemmaInferenceEngineFactory()
    await factory.holdGeneration(for: .gpu)
    let pool = GemmaEnginePool(factory: factory)

    let modelURL = modelURL
    let modelSHA256 = modelSHA256
    let generationTask = Task {
      try await pool.generate(
        prompt: "test prompt",
        modelURL: modelURL,
        modelSHA256: modelSHA256,
        backend: .gpu
      )
    }
    await waitUntil { await factory.generationCount(for: .gpu) == 1 }

    await pool.releaseForMemoryWarning()
    let inFlightSnapshot = await pool.snapshot()
    XCTAssertEqual(inFlightSnapshot.cachedBackend, .gpu)
    XCTAssertTrue(inFlightSnapshot.isEngineInUse)
    XCTAssertEqual(inFlightSnapshot.pendingReleaseReason, .memoryWarning)

    await factory.resumeHeldGenerations()
    _ = try await generationTask.value

    let completedSnapshot = await pool.snapshot()
    XCTAssertNil(completedSnapshot.cachedBackend)
    XCTAssertFalse(completedSnapshot.isEngineInUse)
  }

  func testModelDeletionWaitsForInferenceAndPreventsOldEngineReuse() async throws {
    let factory = TestGemmaInferenceEngineFactory()
    await factory.holdGeneration(for: .gpu)
    let deletionRecorder = TestModelDeletionRecorder()
    let pool = GemmaEnginePool(factory: factory)

    let modelURL = modelURL
    let modelSHA256 = modelSHA256
    let generationTask = Task {
      try await pool.generate(
        prompt: "test prompt",
        modelURL: modelURL,
        modelSHA256: modelSHA256,
        backend: .gpu
      )
    }
    await waitUntil { await factory.generationCount(for: .gpu) == 1 }

    let deletionTask = Task {
      await pool.releaseForModelDeletion {
        let snapshot = await pool.snapshot()
        await deletionRecorder.record(snapshot: snapshot)
      }
    }
    await settleActorWork()
    let deletionRanDuringInference = await deletionRecorder.didRun()
    XCTAssertFalse(deletionRanDuringInference)

    await factory.resumeHeldGenerations()
    _ = try await generationTask.value
    await deletionTask.value

    let deletionSnapshot = await deletionRecorder.snapshot()
    XCTAssertNil(deletionSnapshot?.cachedBackend)
    XCTAssertTrue(deletionSnapshot?.isEngineInUse == true)

    _ = try await generate(using: pool, backend: .gpu)
    let initializationCount = await factory.initializationCount(for: .gpu)
    XCTAssertEqual(initializationCount, 2)
  }

  func testConcurrentRequestsDoNotUseSameEngineInParallel() async throws {
    let factory = TestGemmaInferenceEngineFactory()
    await factory.holdGeneration(for: .gpu)
    let pool = GemmaEnginePool(factory: factory)

    let modelURL = modelURL
    let modelSHA256 = modelSHA256
    let firstTask = Task {
      try await pool.generate(
        prompt: "test prompt",
        modelURL: modelURL,
        modelSHA256: modelSHA256,
        backend: .gpu
      )
    }
    await waitUntil { await factory.generationCount(for: .gpu) == 1 }

    let secondTask = Task {
      try await pool.generate(
        prompt: "test prompt",
        modelURL: modelURL,
        modelSHA256: modelSHA256,
        backend: .gpu
      )
    }
    await settleActorWork()

    let generationCountWhileHeld = await factory.generationCount(for: .gpu)
    XCTAssertEqual(generationCountWhileHeld, 1)

    await factory.resumeHeldGenerations()
    _ = try await firstTask.value
    _ = try await secondTask.value

    let maximumConcurrentGenerations = await factory.maximumConcurrentGenerations()
    let initializationCount = await factory.initializationCount(for: .gpu)
    let finalGenerationCount = await factory.generationCount(for: .gpu)
    XCTAssertEqual(maximumConcurrentGenerations, 1)
    XCTAssertEqual(initializationCount, 1)
    XCTAssertEqual(finalGenerationCount, 2)
  }

  private func generate(
    using pool: GemmaEnginePool,
    backend: GemmaInferenceBackend
  ) async throws -> String {
    try await pool.generate(
      prompt: "test prompt",
      modelURL: modelURL,
      modelSHA256: modelSHA256,
      backend: backend
    )
  }

  private func waitUntil(
    _ condition: @escaping () async -> Bool,
    file: StaticString = #filePath,
    line: UInt = #line
  ) async {
    for _ in 0..<200 {
      if await condition() {
        return
      }
      try? await Task.sleep(for: .milliseconds(1))
    }
    XCTFail("Timed out waiting for asynchronous state.", file: file, line: line)
  }

  private func settleActorWork() async {
    for _ in 0..<20 {
      await Task.yield()
    }
  }
}

private enum TestGemmaEngineError: Error {
  case initializationFailed
  case generationFailed
}

private struct TestGemmaInferenceEngine: GemmaInferenceEngine {
  var identifier: Int
  var backend: GemmaInferenceBackend
  var factory: TestGemmaInferenceEngineFactory

  func initialize() async throws {
    try await factory.recordInitialization(for: backend)
  }

  func generate(prompt: String) async throws -> String {
    try await factory.generate(
      engineIdentifier: identifier,
      backend: backend,
      prompt: prompt
    )
  }
}

private actor TestGemmaInferenceEngineFactory: GemmaInferenceEngineFactory {
  private var nextEngineIdentifier = 0
  private var initializationCounts: [GemmaInferenceBackend: Int] = [:]
  private var generationCounts: [GemmaInferenceBackend: Int] = [:]
  private var backendsFailingNextInitialization: Set<GemmaInferenceBackend> = []
  private var backendsFailingNextGeneration: Set<GemmaInferenceBackend> = []
  private var heldBackends: Set<GemmaInferenceBackend> = []
  private var heldGenerationContinuations: [CheckedContinuation<Void, Never>] = []
  private var activeGenerations = 0
  private var maximumActiveGenerations = 0

  func makeEngine(
    modelURL: URL,
    backend: GemmaInferenceBackend
  ) async throws -> any GemmaInferenceEngine {
    nextEngineIdentifier += 1
    return TestGemmaInferenceEngine(
      identifier: nextEngineIdentifier,
      backend: backend,
      factory: self
    )
  }

  func recordInitialization(for backend: GemmaInferenceBackend) throws {
    initializationCounts[backend, default: 0] += 1
    if backendsFailingNextInitialization.remove(backend) != nil {
      throw TestGemmaEngineError.initializationFailed
    }
  }

  func generate(
    engineIdentifier: Int,
    backend: GemmaInferenceBackend,
    prompt: String
  ) async throws -> String {
    generationCounts[backend, default: 0] += 1
    activeGenerations += 1
    maximumActiveGenerations = max(maximumActiveGenerations, activeGenerations)
    defer { activeGenerations -= 1 }

    if heldBackends.contains(backend) {
      await withCheckedContinuation { continuation in
        heldGenerationContinuations.append(continuation)
      }
    }

    if backendsFailingNextGeneration.remove(backend) != nil {
      throw TestGemmaEngineError.generationFailed
    }

    return "engine-\(engineIdentifier)-\(prompt)"
  }

  func initializationCount(for backend: GemmaInferenceBackend) -> Int {
    initializationCounts[backend, default: 0]
  }

  func generationCount(for backend: GemmaInferenceBackend) -> Int {
    generationCounts[backend, default: 0]
  }

  func failNextInitialization(for backend: GemmaInferenceBackend) {
    backendsFailingNextInitialization.insert(backend)
  }

  func failNextGeneration(for backend: GemmaInferenceBackend) {
    backendsFailingNextGeneration.insert(backend)
  }

  func holdGeneration(for backend: GemmaInferenceBackend) {
    heldBackends.insert(backend)
  }

  func resumeHeldGenerations() {
    heldBackends.removeAll()
    let continuations = heldGenerationContinuations
    heldGenerationContinuations.removeAll()
    continuations.forEach { $0.resume() }
  }

  func maximumConcurrentGenerations() -> Int {
    maximumActiveGenerations
  }
}

private actor ManualGemmaEngineIdleSleeper: GemmaEngineIdleSleeper {
  private var continuations: [CheckedContinuation<Void, Never>] = []

  func sleep(for duration: Duration) async {
    await withCheckedContinuation { continuation in
      continuations.append(continuation)
    }
  }

  func pendingSleepCount() -> Int {
    continuations.count
  }

  func resumeNextSleep() {
    guard !continuations.isEmpty else {
      return
    }
    continuations.removeFirst().resume()
  }
}

private actor TestModelDeletionRecorder {
  private var recordedSnapshot: GemmaEnginePoolSnapshot?

  func record(snapshot: GemmaEnginePoolSnapshot) {
    recordedSnapshot = snapshot
  }

  func didRun() -> Bool {
    recordedSnapshot != nil
  }

  func snapshot() -> GemmaEnginePoolSnapshot? {
    recordedSnapshot
  }
}
