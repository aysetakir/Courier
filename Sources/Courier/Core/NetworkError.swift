import Foundation

/// Bir isteğin neden başarısız olduğunu **kaynağına göre** ayıran hata tipi.
///
/// Tek bir `case unknown` yerine bunca case olmasının sebebi: bu hatalar
/// birbirinden farklı tepki gerektiriyor. Çağıran taraf "internet yok" ile
/// "benim modelim API ile uyuşmuyor"u ayırt edemezse ne kullanıcıya doğru
/// mesajı gösterebilir ne de hatayı ayıklayabilir.
public enum NetworkError: Error {

    // MARK: - İstek daha ağa çıkamadan

    /// `baseURL` + `path` + query'den geçerli bir URL kurulamadı.
    case invalidURL

    /// Gövde encode edilemedi. Bu bir sunucu hatası değil, **bizim** hatamız.
    case encoding(any Error)

    // MARK: - Yolda

    /// İstek ağa çıktı ama yanıt gelmeden koptu: internet yok, timeout,
    /// DNS patladı, kullanıcı isteği iptal etti.
    case transport(any Error)

    // MARK: - Yanıt geldi ama

    /// Yanıt `HTTPURLResponse` değil. Pratikte neredeyse hiç olmaz ama
    /// `as?` dönüşümünün `nil` olduğu durumu sessizce yutmak istemiyoruz.
    case invalidResponse

    /// 401. Ayrı bir case, çünkü tek başına farklı bir tepkisi var:
    /// token yenile ve isteği tekrarla (adım 13'te `AuthInterceptor` bunu yapacak).
    case unauthorized

    /// 2xx dışında bir status code.
    ///
    /// Ham `data`'yı neden saklıyoruz: API hata mesajını gövdede döner
    /// (`{"error": "email already registered"}`). Status code'u alıp gövdeyi
    /// çöpe atarsak kullanıcıya gösterilecek asıl mesajı kaybederiz.
    case server(statusCode: Int, data: Data)

    /// Yanıt geldi, 2xx'ti, ama modele çevrilemedi.
    ///
    /// Ham `raw`'ı neden saklıyoruz: decoding hatasını ayıklamanın tek yolu
    /// sunucunun gerçekte ne gönderdiğini görmek. "Expected String but found
    /// null" mesajı tek başına hangi alanın sorun olduğunu söylemez.
    case decoding(any Error, raw: Data)

    /// İsteği tekrar denemenin bir anlamı var mı?
    ///
    /// Adım 9'daki `RetryPolicy` bu kararı buradan okuyacak.
    public var isRetryable: Bool {
        switch self {
        case .transport(let error):
            // İptal edilen istek KESİNLİKLE tekrar denenmez. Kullanıcı hücreyi
            // ekrandan kaydırdığı için iptal ettik; tekrar denemek iptalin
            // bütün amacını yok eder.
            if error is CancellationError { return false }
            if let urlError = error as? URLError, urlError.code == .cancelled { return false }
            // Geri kalan taşıma hataları genelde geçicidir: sinyal kesildi,
            // timeout oldu. Bunlar tekrar denemeye değer.
            return true

        case .server(let statusCode, _):
            // 5xx = sunucu patladı, birazdan düzelebilir.
            // 429 = "çok hızlısın, yavaşla" — tam olarak beklenip tekrar
            // denenmesi gereken durum.
            // 408 = sunucu isteğin gelmesini bekledi, sıkıldı.
            // 400/404 gibi hatalar ise tekrar denemekle düzelmez: istek yanlış,
            // aynısını 5 kez göndermek 5 kez aynı hatayı almak demek.
            return [408, 429, 500, 502, 503, 504].contains(statusCode)

        case .unauthorized:
            // 401 tekrar denenir ama "aynı isteği tekrar at" diyerek değil,
            // önce token yenilenerek. O karar AuthInterceptor'ın işi, burada
            // körü körüne true dönmek sonsuz döngü riski yaratır.
            return false

        case .invalidURL, .encoding, .invalidResponse, .decoding:
            // Hepsi deterministik: girdi değişmeden sonuç değişmez.
            return false
        }
    }
}
