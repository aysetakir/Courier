# Courier

Swift için async/await tabanlı HTTP istemcisi. Öğrenme amaçlı yazılıyor.

## Kurulum

Swift Package Manager:

```swift
.package(url: "https://github.com/aysetakir/Courier.git", from: "0.1.0")
```

## Kullanım

Bir API ucunu `Endpoint` ile tarif et:

```swift
enum UserAPI: Endpoint {
    case profile(id: String)

    var baseURL: URL { URL(string: "https://api.example.com")! }

    var path: String {
        switch self {
        case .profile(let id): return "/users/\(id)"
        }
    }
}
```

Sonra çağır:

```swift
let client = HTTPClient()
let user: User = try await client.send(UserAPI.profile(id: "42"))
```

Hatalar `NetworkError` olarak gelir ve sunucunun gövdesini korur:

```swift
do {
    let user: User = try await client.send(UserAPI.profile(id: "42"))
} catch let error as NetworkError {
    if case .server(let statusCode, let data) = error {
        print(statusCode, String(decoding: data, as: UTF8.self))
    }
}
```

## Durum

- [x] v0.1 — `Endpoint`, `URLRequest` üretimi, `HTTPClient`, hata taksonomisi, `URLProtocol` ile testler
- [ ] v1.0 — Interceptor zinciri, auth header, single-flight token refresh, retry + backoff
- [ ] v1.1 — Multipart upload, request/response logger
