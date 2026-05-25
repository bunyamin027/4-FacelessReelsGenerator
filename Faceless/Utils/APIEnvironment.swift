import Foundation

/// API Key ve Host bilgilerini güvenli bir şekilde sağlayan yapı.
/// Bu bilgileri doğrudan koda hardcode etmek yerine Info.plist veya Environment Variables üzerinden çeker.
struct APIEnvironment {
    
    /// Info.plist veya benzeri bir yapılandırma dosyasından Groq API Key'ini okur.
    static var groqApiKey: String {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "GROQ_API_KEY") as? String, !key.isEmpty else {
            #if DEBUG
            print("⚠️ Uyarı: GROQ_API_KEY Info.plist içerisinde bulunamadı. Lütfen ekleyin.")
            #endif
            return ""
        }
        return key
    }
    
    /// Info.plist veya benzeri bir yapılandırma dosyasından RapidAPI Key'ini okur.
    static var rapidApiKey: String {
        // Örnek: Info.plist içine "RAPIDAPI_KEY" adında bir özellik eklendiği varsayılmıştır.
        // Güvenlik için xconfig dosyası kullanıp değerleri oradan Info.plist'e taşıyabilirsiniz.
        guard let key = Bundle.main.object(forInfoDictionaryKey: "RAPIDAPI_KEY") as? String, !key.isEmpty else {
            // Geliştirme ortamında (debug) varsayılan bir uyarı mesajı fırlatılabilir veya fallback yapılabilir.
            #if DEBUG
            print("⚠️ Uyarı: RAPIDAPI_KEY Info.plist içerisinde bulunamadı. Lütfen ekleyin.")
            #endif
            return "" // Config dosyanızdan çektiğiniz key'i doldurduğunuzdan emin olun.
        }
        return key
    }
    
    /// Info.plist veya benzeri bir yapılandırma dosyasından RapidAPI Host bilgisini okur.
    static var rapidApiHost: String {
        guard let host = Bundle.main.object(forInfoDictionaryKey: "RAPIDAPI_HOST") as? String, !host.isEmpty else {
            #if DEBUG
            print("⚠️ Uyarı: RAPIDAPI_HOST Info.plist içerisinde bulunamadı. Lütfen ekleyin.")
            #endif
            return "" // Örnek fallback: "capcut-video-downloader.p.rapidapi.com" (kullandığınız API'ye göre değişir)
        }
        return host
    }
    
    /// Kullandığınız CapCut RapidAPI servisine ait temel URL (Endpoint).
    static var baseURL: String {
        guard let url = Bundle.main.object(forInfoDictionaryKey: "RAPIDAPI_BASE_URL") as? String, !url.isEmpty else {
            // Örnek bir endpoint
            return "https://\(rapidApiHost)/api/download"
        }
        return url
    }
}
