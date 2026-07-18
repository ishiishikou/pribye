import Foundation
import XCTest
@testable import Pribye

final class GemmaInferenceBackendTests: XCTestCase {
  private var suiteName: String!
  private var defaults: UserDefaults!

  override func setUp() {
    super.setUp()
    suiteName = "GemmaInferenceBackendTests.\(UUID().uuidString)"
    defaults = UserDefaults(suiteName: suiteName)
  }

  override func tearDown() {
    defaults.removePersistentDomain(forName: suiteName)
    defaults = nil
    suiteName = nil
    super.tearDown()
  }

  func testUnknownEnvironmentUsesGPUOnly() {
    let selector = makeSelector(environment: makeEnvironment())

    XCTAssertEqual(selector.orderedBackends(), [.gpu])
  }

  func testSuccessfulGPUBackendRemainsPreferred() {
    let environment = makeEnvironment()
    let selector = makeSelector(environment: environment)

    selector.recordSuccess(.gpu)

    XCTAssertEqual(makeSelector(environment: environment).orderedBackends(), [.gpu])
  }

  func testSavedCPUPreferenceIsIgnoredForE4B() {
    let environment = makeEnvironment()
    let store = GemmaBackendPreferenceStore(defaults: defaults)
    store.save(.cpu, for: environment)

    XCTAssertEqual(makeSelector(environment: environment).orderedBackends(), [.gpu])
  }

  func testPreferenceIsReevaluatedAfterEnvironmentChanges() {
    let environment = makeEnvironment()
    makeSelector(environment: environment).recordSuccess(.gpu)

    let updatedEnvironment = GemmaBackendEnvironment(
      hardwareIdentifier: environment.hardwareIdentifier,
      operatingSystemVersion: "iOS 26.1",
      liteRTLMVersion: environment.liteRTLMVersion,
      modelSHA256: environment.modelSHA256
    )

    XCTAssertEqual(makeSelector(environment: updatedEnvironment).orderedBackends(), [.gpu])
  }

  private func makeSelector(
    environment: GemmaBackendEnvironment
  ) -> GemmaInferenceBackendSelector {
    GemmaInferenceBackendSelector(
      environment: environment,
      preferenceStore: GemmaBackendPreferenceStore(defaults: defaults)
    )
  }

  private func makeEnvironment() -> GemmaBackendEnvironment {
    GemmaBackendEnvironment(
      hardwareIdentifier: "iPhone17,3",
      operatingSystemVersion: "iOS 26.0",
      liteRTLMVersion: "0.14.0",
      modelSHA256: "test-model-sha"
    )
  }
}
