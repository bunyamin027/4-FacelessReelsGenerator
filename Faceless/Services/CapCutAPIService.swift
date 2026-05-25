import Foundation

/// CapCut API ile iletişim kurmaktan sorumlu olan servis sınıfı.
/// Tek Sorumluluk Prensibi (SRP) gereği sadece API isteklerini yönetir ve ağ işlemlerinden sorumludur.
final class CapCutAPIService: Sendable {
    
    /// Ortak bir kullanım sunmak için Singleton örneği (isteğe bağlı, Dependency Injection da kullanılabilir).
    static let shared = CapCutAPIService()
    
    // Sınıfın sadece kendi içinde veya Dependency Injection ile üretilmesini zorunlu kılmak için
    private init() {}
    
    /// Belirtilen CapCut URL'i için asenkron olarak filigransız video indirme linkini getirir.
    /// - Parameter url: İndirilecek olan hedef CapCut video URL'i (Örn: "https://www.capcut.com/t/...")
    /// - Returns: Parse edilmiş filigransız video linki (String)
    func downloadVideo(url: String) async throws -> String {
        
        // 1. URL'i doğrulama ve API Endpoint'ini oluşturma
        // İstek atacağımız RapidAPI servisine ait tam adresi oluşturuyoruz.
        // Bazı API'lerde URL parametresi Query olarak iletilir (örnek: ?url=...).
        // API dökümantasyonunuza göre bu query parametresi ismini ("url", "link" vb.) ayarlamanız gerekebilir.
        var urlComponents = URLComponents(string: APIEnvironment.baseURL)
        urlComponents?.queryItems = [
            URLQueryItem(name: "url", value: url)
        ]
        
        guard let requestURL = urlComponents?.url else {
            throw CapCutAPIError.invalidURL
        }
        
        // 2. HTTP İsteği (Request) yapılandırması
        var request = URLRequest(url: requestURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 30.0 // İstek zaman aşımı süresi
        
        // Header'ların güvenli bir şekilde eklenmesi
        request.addValue(APIEnvironment.rapidApiKey, forHTTPHeaderField: "x-rapidapi-key")
        request.addValue(APIEnvironment.rapidApiHost, forHTTPHeaderField: "x-rapidapi-host")
        
        // 3. Ağ (Network) İsteği Gönderme
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw CapCutAPIError.unknown(underlyingError: error)
        }
        
        // 4. HTTP Yanıtını Kontrol Etme
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CapCutAPIError.invalidResponse
        }
        
        // Status code (Durum kodu) kontrolü
        switch httpResponse.statusCode {
        case 200...299:
            break // Başarılı
        case 429:
            throw CapCutAPIError.rateLimitExceeded // RapidAPI Kota aşımı
        default:
            throw CapCutAPIError.serverError(statusCode: httpResponse.statusCode)
        }
        
        // 5. Veri kontrolü
        guard !data.isEmpty else {
            throw CapCutAPIError.noData
        }
        
        // 6. JSON Parse (Decode) İşlemi
        do {
            let decoder = JSONDecoder()
            let decodedResponse = try decoder.decode(CapCutVideoResponse.self, from: data)
            
            // Modele uygun filigransız URL'i çekiyoruz
            guard let noWatermarkURL = decodedResponse.data?.noWatermark, !noWatermarkURL.isEmpty else {
                throw CapCutAPIError.missingNoWatermarkURL
            }
            
            return noWatermarkURL
            
        } catch let decodeError {
            // Eğer JSON formatı beklenenden farklıysa özel bir decoding hatası fırlatılır
            throw CapCutAPIError.decodingError(underlyingError: decodeError)
        }
    }
}
