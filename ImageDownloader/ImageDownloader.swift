import UIKit
import Combine

final class ImageDownloader {
    typealias ImageCompletion = (UIImage) -> Void
    
    static let sharedInstance = ImageDownloader()
    
    static var runningTasks: [String: State] = [:]
    
    static let cache = NSCache<NSString, UIImage>()
    
    static let parallelQueue = DispatchQueue.global(qos: .utility)
    
    static let fileManager = FileManager.default
    
    private init() {}
    
    // MARK: - Public
    
    func image(by url: String, completion: @escaping ImageCompletion) -> Cancellable {
        let id = UUID()
        DispatchQueue.main.async {
            if let image = ImageDownloader.getFromCache(with: url) {
                completion(image)
            } else if let image = ImageDownloader.getImageFromDisk(with: String(url.hash) + "_2") {
                completion(image)
            } else {
                ImageDownloader.downloadImage(with: url, completion: (id, completion))
            }
        }
        return ControlState(url: url, with: id)
    }
    
    
    // MARK: - Private
    
    static func downloadImage(with url: String, completion: (UUID, ImageCompletion)) -> Void {
        if let state = ImageDownloader.runningTasks[url] {
            state.completionBlocks.append(completion)
        } else {
            let state = State(url: url, with: completion)
            ImageDownloader.runningTasks[url] = state
            ImageDownloader.parallelQueue.async {
                state.start()
            }
        }
    }
    
    static func getFromCache(with url: String) -> UIImage? {
        return ImageDownloader.cache.object(forKey: url as NSString)
    }
    
    static func getImageFromDisk(with name: String) -> UIImage? {
        guard let dir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil;
        }
        let fileURL = dir.appendingPathComponent(name)
        return UIImage(contentsOfFile: fileURL.absoluteString)
    }
    
    static func saveImageToDisk(with name: String, from image: UIImage) -> Void {
        guard let dir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return;
        }
        let fileURL = dir.appendingPathComponent(name)
        fileManager.createFile(atPath: fileURL.path, contents: image.jpegData(compressionQuality: 1), attributes: [:])
    }
    
    class ControlState: Cancellable {
        var id: UUID
        var url: String
        
        init(url: String, with id: UUID) {
            self.id = id
            self.url = url
        }
        
        func cancel() {
            DispatchQueue.main.async {
                if let task = ImageDownloader.runningTasks[self.url] {
                    task.completionBlocks = task.completionBlocks.filter( { $0.0 != self.id } )
                    task.cancel()
                }
            }
        }
    }
    
    class State: Cancellable {
        var completionBlocks: [(UUID, ImageCompletion)]
        var url: String
        var task: URLSessionDataTask?
        
        init(url: String, with completion: (UUID, ImageCompletion)) {
            self.completionBlocks = [completion]
            self.url = url
        }
        
        func start() {
            ImageDownloader.parallelQueue.async {
                guard let url = URL(string: self.url) else {
                    print("Unvalid url: \(self.url)")
                    return
                }
                self.task = URLSession.shared.dataTask(with: url) { (data, response, error) in
                    if let data = data {
                        ImageDownloader.parallelQueue.async {
                            guard let image = UIImage(data: data) else {
                                print("Unvalid data at url: \(self.url)")
                                ImageDownloader.runningTasks[self.url] = nil
                                return
                            }
                            ImageDownloader.saveImageToDisk(with: String(self.url.hash) + "_1", from: image)
                            let miniImage = ImageDownloader.resizeImage(image: image, targetSize: .init(width: 50, height: 50))
                            ImageDownloader.saveImageToDisk(with: String(self.url.hash) + "_2", from: miniImage)
                            DispatchQueue.main.async {
                                ImageDownloader.runningTasks[self.url]?.completionBlocks.forEach { $0.1(miniImage) }
                                ImageDownloader.cache.setObject(miniImage, forKey: self.url as NSString)
                                ImageDownloader.runningTasks[self.url] = nil
                            }
                        }
                    }
                }
                self.task!.resume()
            }
        }
        
        func cancel() {
            if completionBlocks.count == 0 {
                ImageDownloader.runningTasks[self.url] = nil
                task?.cancel()
            }
        }
    }
    
    static func resizeImage(image: UIImage, targetSize: CGSize) -> UIImage {
        let size = image.size

        let widthRatio  = targetSize.width  / size.width
        let heightRatio = targetSize.height / size.height

        // Figure out what our orientation is, and use that to form the rectangle
        var newSize: CGSize
        if(widthRatio > heightRatio) {
            newSize = CGSize(width: size.width * heightRatio, height: size.height * heightRatio)
        } else {
            newSize = CGSize(width: size.width * widthRatio, height: size.height * widthRatio)
        }

        // This is the rect that we've calculated out and this is what is actually used below
        let rect = CGRect(x: 0, y: 0, width: newSize.width, height: newSize.height)

        // Actually do the resizing to the rect using the ImageContext stuff
        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        image.draw(in: rect)
        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return newImage!
    }

}
