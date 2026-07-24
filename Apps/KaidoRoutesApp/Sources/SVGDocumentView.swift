import SwiftUI
import WebKit

struct SVGDocumentView: UIViewRepresentable {
  let resourceName: String

  func makeCoordinator() -> Coordinator {
    Coordinator()
  }

  func makeUIView(context: Context) -> WKWebView {
    let configuration = WKWebViewConfiguration()
    configuration.defaultWebpagePreferences.allowsContentJavaScript = false

    let view = WKWebView(frame: .zero, configuration: configuration)
    view.isOpaque = false
    view.backgroundColor = .clear
    view.scrollView.backgroundColor = .clear
    view.scrollView.isScrollEnabled = false
    view.scrollView.contentInsetAdjustmentBehavior = .never
    view.isUserInteractionEnabled = false
    view.accessibilityElementsHidden = true
    return view
  }

  func updateUIView(_ view: WKWebView, context: Context) {
    guard context.coordinator.loadedResourceName != resourceName else {
      return
    }
    context.coordinator.loadedResourceName = resourceName

    guard
      let url = Bundle.main.url(
        forResource: resourceName,
        withExtension: "svg"
      )
    else {
      assertionFailure("Missing bundled Route Atlas resource: \(resourceName).svg")
      view.loadHTMLString(
        """
        <html><body style="margin:0;background:#162329;color:#f07d6d;\
        font:700 14px -apple-system;padding:24px">MAP RESOURCE MISSING</body></html>
        """,
        baseURL: nil
      )
      return
    }

    view.loadFileURL(
      url,
      allowingReadAccessTo: url.deletingLastPathComponent()
    )
  }

  final class Coordinator {
    var loadedResourceName: String?
  }
}
