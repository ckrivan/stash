import SwiftUI
import UIKit
import Combine

/// High-performance image loader with NSCache, disk caching, and automatic downsampling
/// Optimized for Stash server image paths with ?width= parameter support
class CachedImageLoader: ObservableObject {
  @Published var image: UIImage?
  @Published var isLoading = false

  private var cancellable: AnyCancellable?
  private static let cache = NSCache<NSString, UIImage>()
  private static let diskCacheURL: URL = {
    let paths = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
    return paths[0].appendingPathComponent("ImageCache")
  }()

  private static let session: URLSession = {
    let config = URLSessionConfiguration.default
    config.requestCachePolicy = .returnCacheDataElseLoad
    config.urlCache = URLCache(memoryCapacity: 50 * 1024 * 1024, diskCapacity: 200 * 1024 * 1024)
    return URLSession(configuration: config)
  }()

  static func configure() {
    // Configure cache limits
    cache.countLimit = 200  // Max 200 images in memory
    cache.totalCostLimit = 100 * 1024 * 1024  // 100 MB

    // Create disk cache directory
    try? FileManager.default.createDirectory(at: diskCacheURL, withIntermediateDirectories: true)
  }

  /// Load image with optional width parameter for Stash server
  /// - Parameters:
  ///   - url: Image URL
  ///   - width: Target width (Stash supports ?width= parameter for downsampling)
  func load(url: URL?, width: CGFloat? = nil) {
    guard let url = url else {
      self.image = nil
      return
    }

    // Add width parameter if supported and requested
    let finalURL: URL
    if let width = width, url.absoluteString.contains("/performer/") || url.absoluteString.contains("/scene/") {
      if url.absoluteString.contains("?") {
        finalURL = URL(string: "\(url.absoluteString)&width=\(Int(width))") ?? url
      } else {
        finalURL = URL(string: "\(url.absoluteString)?width=\(Int(width))") ?? url
      }
    } else {
      finalURL = url
    }

    let cacheKey = finalURL.absoluteString as NSString

    // Check memory cache first
    if let cached = Self.cache.object(forKey: cacheKey) {
      self.image = cached
      self.isLoading = false
      return
    }

    // Check disk cache
    if let diskImage = loadFromDisk(key: cacheKey as String) {
      Self.cache.setObject(diskImage, forKey: cacheKey)
      self.image = diskImage
      self.isLoading = false
      return
    }

    // Download image
    isLoading = true
    cancellable = Self.session.dataTaskPublisher(for: finalURL)
      .map { UIImage(data: $0.data) }
      .replaceError(with: nil)
      .receive(on: DispatchQueue.main)
      .sink { [weak self] downloadedImage in
        guard let self = self else { return }
        self.isLoading = false

        if let downloadedImage = downloadedImage {
          // Downsample if needed
          let finalImage: UIImage
          if let targetWidth = width, downloadedImage.size.width > targetWidth {
            finalImage = self.downsample(image: downloadedImage, to: CGSize(width: targetWidth, height: targetWidth * downloadedImage.size.height / downloadedImage.size.width))
          } else {
            finalImage = downloadedImage
          }

          // Store in caches
          Self.cache.setObject(finalImage, forKey: cacheKey)
          self.saveToDisk(image: finalImage, key: cacheKey as String)
          self.image = finalImage
        }
      }
  }

  func cancel() {
    cancellable?.cancel()
  }

  // MARK: - Disk Cache

  private func diskCachePath(for key: String) -> URL {
    let filename = key.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? UUID().uuidString
    return Self.diskCacheURL.appendingPathComponent(filename)
  }

  private func loadFromDisk(key: String) -> UIImage? {
    let path = diskCachePath(for: key)
    guard let data = try? Data(contentsOf: path) else { return nil }
    return UIImage(data: data)
  }

  private func saveToDisk(image: UIImage, key: String) {
    guard let data = image.jpegData(compressionQuality: 0.8) else { return }
    let path = diskCachePath(for: key)
    try? data.write(to: path)
  }

  // MARK: - Downsampling

  private func downsample(image: UIImage, to size: CGSize) -> UIImage {
    let renderer = UIGraphicsImageRenderer(size: size)
    return renderer.image { _ in
      image.draw(in: CGRect(origin: .zero, size: size))
    }
  }

  static func clearCache() {
    cache.removeAllObjects()
    try? FileManager.default.removeItem(at: diskCacheURL)
    try? FileManager.default.createDirectory(at: diskCacheURL, withIntermediateDirectories: true)
  }
}

/// Drop-in replacement for AsyncImage with caching and downsampling
struct CachedAsyncImage<Content: View, Placeholder: View>: View {
  let url: URL?
  let width: CGFloat?
  let content: (Image) -> Content
  let placeholder: () -> Placeholder

  @StateObject private var loader = CachedImageLoader()

  init(
    url: URL?,
    width: CGFloat? = nil,
    @ViewBuilder content: @escaping (Image) -> Content,
    @ViewBuilder placeholder: @escaping () -> Placeholder
  ) {
    self.url = url
    self.width = width
    self.content = content
    self.placeholder = placeholder
  }

  var body: some View {
    Group {
      if let image = loader.image {
        content(Image(uiImage: image))
      } else if loader.isLoading {
        placeholder()
      } else {
        placeholder()
      }
    }
    .onAppear {
      loader.load(url: url, width: width)
    }
    .onDisappear {
      loader.cancel()
    }
  }
}

// Convenience initializer matching AsyncImage syntax
extension CachedAsyncImage where Content == Image, Placeholder == Color {
  init(url: URL?, width: CGFloat? = nil) {
    self.url = url
    self.width = width
    self.content = { $0 }
    self.placeholder = { Color.gray.opacity(0.2) }
  }
}
