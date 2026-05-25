import Foundation

/// CapCut API işlemlerinde oluşabilecek hataları tanımlayan özel hata (Error) yapısı.
enum CapCutAPIError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case rateLimitExceeded // HTTP 429 - Too Many Requests
    case serverError(statusCode: Int)
    case decodingError(underlyingError: Error)
    case noData
    case missingNoWatermarkURL
    case unknown(underlyingError: Error)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Geçersiz veya hatalı bir URL sağlandı."
        case .invalidResponse:
            return "Sunucudan geçersiz bir yanıt alındı."
        case .rateLimitExceeded:
            return "API kota sınırı aşıldı (Rate Limit - HTTP 429). Lütfen daha sonra tekrar deneyin."
        case .serverError(let statusCode):
            return "Sunucu hatası oluştu. HTTP Durum Kodu: \(statusCode)"
        case .decodingError(let error):
            return "Gelen veri işlenirken (parse) hata oluştu: \(error.localizedDescription)"
        case .noData:
            return "Sunucudan veri alınamadı."
        case .missingNoWatermarkURL:
            return "Yanıt içerisinde filigransız (no_watermark) video URL'i bulunamadı."
        case .unknown(let error):
            return "Bilinmeyen bir hata oluştu: \(error.localizedDescription)"
        }
    }
}
