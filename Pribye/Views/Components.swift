#if canImport(GoogleMobileAds)
import GoogleMobileAds
#endif
import SwiftUI

struct EmptyStateView: View {
  var title: String
  var systemImage: String
  var actionTitle: String?
  var action: (() -> Void)?

  var body: some View {
    ContentUnavailableView {
      Label(title, systemImage: systemImage)
    } description: {
      Text("必要な行動だけをタスクとして残します。")
    } actions: {
      if let actionTitle, let action {
        Button(actionTitle, action: action)
          .buttonStyle(.borderedProminent)
      }
    }
  }
}

struct AdBannerPlaceholder: View {
  @AppStorage("adsRemoved") private var adsRemoved = false

  var body: some View {
    if !adsRemoved {
      #if canImport(GoogleMobileAds)
      GeometryReader { proxy in
        let width = Swift.max(proxy.size.width, CGFloat(320))
        let adSize = largeAnchoredAdaptiveBanner(width: width)
        AdMobBannerContainer(adSize: adSize)
          .frame(width: adSize.size.width, height: adSize.size.height)
          .frame(maxWidth: .infinity)
      }
      .frame(height: 90)
      .accessibilityIdentifier("ad_banner")
      #else
      Text("広告エリア")
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .frame(height: 64)
        .background(.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityIdentifier("ad_banner")
      #endif
    }
  }
}

#if canImport(GoogleMobileAds)
private struct AdMobBannerContainer: UIViewRepresentable {
  var adSize: AdSize

  func makeUIView(context: Context) -> BannerView {
    let banner = BannerView(adSize: adSize)
    banner.adUnitID = AdMobConfiguration.bannerAdUnitID
    banner.load(Request())
    return banner
  }

  func updateUIView(_ banner: BannerView, context: Context) {
    guard banner.adSize.size != adSize.size else {
      return
    }
    banner.adSize = adSize
    banner.load(Request())
  }
}

private enum AdMobConfiguration {
  static var bannerAdUnitID: String {
    Bundle.main.object(forInfoDictionaryKey: "PribyeAdMobBannerAdUnitID") as? String ?? ""
  }
}
#endif

struct StatusPill: View {
  var text: String
  var color: Color

  var body: some View {
    Text(text)
      .font(.caption.weight(.semibold))
      .foregroundStyle(color)
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .background(color.opacity(0.12), in: Capsule())
  }
}

struct DueDateText: View {
  var start: Date?
  var end: Date?

  var body: some View {
    if let start, let end {
      Text("\(start.formatted(.dateTime.month().day()))〜\(end.formatted(.dateTime.month().day())) 毎日")
        .foregroundStyle(.red)
    } else if let start {
      Text("\(start.formatted(.dateTime.month().day())) まで")
        .foregroundStyle(.red)
    } else if let end {
      Text("\(end.formatted(.dateTime.month().day())) まで")
        .foregroundStyle(.red)
    } else {
      Text("期限なし")
        .foregroundStyle(.secondary)
    }
  }
}
