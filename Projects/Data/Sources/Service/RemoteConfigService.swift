//
//  RemoteConfigService.swift
//  Data
//
//  Created by sanghyeon on 8/3/26.
//  Copyright © 2026 sanghyeon. All rights reserved.
//

import Foundation
import FirebaseCore
import FirebaseInstallations

public final class RemoteConfigService {

    private struct FetchResponse: Decodable {
        let entries: [String: String]?
    }

    public init() {}

    // FirebaseRemoteConfig SDK의 fetchAndActivate()가 이 환경에서 끝나지 않아(firebase-ios-sdk#11770) REST 엔드포인트를 직접 호출한다
    public func fetchMinAndRecommendVersion() async throws -> (min: String, recommend: String) {
        let entries = try await fetchEntries()
        return (
            entries["ios_min_version"] ?? "",
            entries["ios_recommend_version"] ?? ""
        )
    }

    private func fetchEntries() async throws -> [String: String] {
        guard let options = FirebaseApp.app()?.options, let apiKey = options.apiKey else {
            throw URLError(.badServerResponse)
        }
        let projectNumber = options.gcmSenderID
        let appId = options.googleAppID

        let fid = try await installationID()
        let authToken = try await installationAuthToken()

        guard let url = URL(
            string: "https://firebaseremoteconfig.googleapis.com/v1/projects/\(projectNumber)/namespaces/firebase:fetch?key=\(apiKey)"
        ) else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("FIREBASE_INSTALLATIONS_AUTH \(authToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "appId": appId,
            "appInstanceId": fid,
            "appVersion": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "",
            "packageName": Bundle.main.bundleIdentifier ?? "",
            "platformVersion": ProcessInfo.processInfo.operatingSystemVersionString
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(FetchResponse.self, from: data).entries ?? [:]
    }

    private func installationID() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            Installations.installations().installationID { id, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: id ?? "")
                }
            }
        }
    }

    private func installationAuthToken() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            Installations.installations().authToken { result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: result?.authToken ?? "")
                }
            }
        }
    }
}
