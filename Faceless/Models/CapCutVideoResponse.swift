import Foundation

/// RapidAPI üzerinden dönen yanıtın en dış katmanını temsil eden model.
/// Not: Kullandığınız spesifik CapCut API'sinin yanıt formatına göre `CodingKeys` ve özellikleri güncelleyebilirsiniz.
struct CapCutVideoResponse: Codable {
    let code: Int?
    let msg: String?
    let data: CapCutVideoData?
}

/// Video verilerini (URL, başlık vb.) içeren iç model.
struct CapCutVideoData: Codable {
    let title: String?
    let cover: String?
    let noWatermark: String? // Filigransız video linki
    let watermark: String?
    
    // JSON'daki key isimlerini Swift standartlarına uydurmak için CodingKeys kullanımı
    enum CodingKeys: String, CodingKey {
        case title
        case cover
        case noWatermark = "no_watermark"
        case watermark
    }
}
