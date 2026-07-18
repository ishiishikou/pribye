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

  func testUnknownEnvironmentTriesGPUThenCPU() {
    let selector = makeSelector(environment: makeEnvironment())

    XCTAssertEqual(selector.orderedBackends(), [.gpu, .cpu])
  }

  func testSuccessfulCPUBackendIsUsedFirstNextTime() {
    let environment = makeEnvironment()
    let selector = makeSelector(environment: environment)

    selector.recordSuccess(.cpu)

    XCTAssertEqual(makeSelector(environment: environment).orderedBackends(), [.cpu, .gpu])
  }

  func testPreferenceIsReevaluatedAfterEnvironmentChanges() {
    let environment = makeEnvironment()
    makeSelector(environment: environment).recordSuccess(.cpu)

    let updatedEnvironment = GemmaBackendEnvironment(
      hardwareIdentifier: environment.hardwareIdentifier,
      operatingSystemVersion: "iOS 26.1",
      liteRTLMVersion: environment.liteRTLMVersion,
      modelSHA256: environment.modelSHA256
    )

    XCTAssertEqual(makeSelector(environment: updatedEnvironment).orderedBackends(), [.gpu, .cpu])
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
