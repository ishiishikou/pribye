import Combine
import Foundation
import StoreKit

final class PurchaseService: ObservableObject {
  static let removeAdsProductID = "com.pribye.remove_ads"

  @MainActor
  @Published private(set) var removeAdsProduct: Product?
  @MainActor
  @Published private(set) var statusMessage: String?
  @MainActor
  @Published private(set) var isLoading = false

  @MainActor
  func loadRemoveAdsProduct() async {
    isLoading = true
    defer { isLoading = false }

    do {
      removeAdsProduct = try await Product.products(for: [Self.removeAdsProductID]).first
      if removeAdsProduct == nil {
        statusMessage = "広告非表示の課金項目がApp Store Connectで見つかりません"
      }
    } catch {
      statusMessage = "課金情報を読み込めませんでした"
    }
  }

  @MainActor
  func refreshEntitlement() async -> Bool {
    for await result in Transaction.currentEntitlements {
      guard case .verified(let transaction) = result,
            transaction.productID == Self.removeAdsProductID,
            transaction.revocationDate == nil else {
        continue
      }
      return true
    }
    return false
  }

  @MainActor
  func restoreRemoveAds() async -> Bool {
    let hasEntitlement = await refreshEntitlement()
    statusMessage = hasEntitlement ? "購入を復元しました" : "復元できる購入はありません"
    return hasEntitlement
  }

  @MainActor
  func updatedRemoveAdsEntitlements() -> AsyncStream<Bool> {
    AsyncStream { continuation in
      let task = Task {
        for await result in Transaction.updates {
          guard case .verified(let transaction) = result,
                transaction.productID == Self.removeAdsProductID else {
            continue
          }
          continuation.yield(await refreshEntitlement())
          await transaction.finish()
        }
      }

      continuation.onTermination = { _ in
        task.cancel()
      }
    }
  }

  @MainActor
  func purchaseRemoveAds() async -> Bool {
    guard let product = removeAdsProduct else {
      await loadRemoveAdsProduct()
      guard removeAdsProduct != nil else {
        return false
      }
      return await purchaseRemoveAds()
    }

    isLoading = true
    defer { isLoading = false }

    do {
      let result = try await product.purchase()
      switch result {
      case .success(let verification):
        guard case .verified(let transaction) = verification else {
          statusMessage = "購入を確認できませんでした"
          return false
        }
        await transaction.finish()
        statusMessage = "広告を非表示にしました"
        return true
      case .userCancelled:
        statusMessage = nil
        return false
      case .pending:
        statusMessage = "購入は保留中です"
        return false
      @unknown default:
        statusMessage = "購入を完了できませんでした"
        return false
      }
    } catch {
      statusMessage = "購入を完了できませんでした"
      return false
    }
  }
}
