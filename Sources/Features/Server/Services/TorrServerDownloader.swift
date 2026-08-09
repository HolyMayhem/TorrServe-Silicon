import Foundation

final class TorrServerDownloader {
    private let latestReleaseURL = URL(
        string: "https://api.github.com/repos/YouROK/TorrServer/releases/latest"
    )!
    private let assetName = torrServerExecutableName

    func downloadLatestDarwinArm64(completion: @escaping (Result<URL, Error>) -> Void) {
        URLSession.shared.dataTask(with: latestReleaseURL) { [assetName] data, _, error in
            if let error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }

            do {
                guard let data else {
                    throw AppError("GitHub не вернул данные релиза.")
                }

                let assetURL = try self.findAssetURL(named: assetName, in: data)
                self.downloadAsset(from: assetURL, completion: completion)
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }.resume()
    }

    private func findAssetURL(named assetName: String, in data: Data) throws -> URL {
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let assets = json["assets"] as? [[String: Any]]
        else {
            throw AppError("Не удалось прочитать список файлов последнего релиза.")
        }

        guard
            let asset = assets.first(where: { $0["name"] as? String == assetName }),
            let downloadString = asset["browser_download_url"] as? String,
            let downloadURL = URL(string: downloadString)
        else {
            throw AppError("В последнем релизе не найден файл \(assetName).")
        }

        return downloadURL
    }

    private func downloadAsset(
        from url: URL,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        URLSession.shared.downloadTask(with: url) { temporaryURL, _, error in
            if let error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }

            do {
                guard let temporaryURL else {
                    throw AppError("Загрузка завершилась без файла.")
                }

                let destination = try self.downloadDestinationURL()
                let directory = destination.deletingLastPathComponent()
                try FileManager.default.createDirectory(
                    at: directory,
                    withIntermediateDirectories: true
                )

                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }

                try FileManager.default.moveItem(at: temporaryURL, to: destination)
                try FileManager.default.setAttributes(
                    [.posixPermissions: NSNumber(value: 0o755)],
                    ofItemAtPath: destination.path
                )

                DispatchQueue.main.async { completion(.success(destination)) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }.resume()
    }

    private func downloadDestinationURL() throws -> URL {
        guard let appSupportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw AppError("Не удалось найти папку Application Support.")
        }

        return appSupportURL
            .appendingPathComponent("TorrServer Manager", isDirectory: true)
            .appendingPathComponent(assetName)
    }
}
