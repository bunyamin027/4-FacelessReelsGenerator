//
//  BlueprintService.swift
//  Faceless
//

import Foundation
import os

// MARK: - Blueprint Error
enum BlueprintError: LocalizedError, Sendable {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int, data: Data?)
    case encodingError(Error)
    case decodingError(Error)
    case networkError(Error)
    case maxRetriesReached(Error?)
    case missingAPIKey
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The endpoint URL is invalid."
        case .invalidResponse:
            return "The server response was invalid."
        case .httpError(let statusCode, _):
            return "HTTP Error with status code: \(statusCode)"
        case .encodingError(let error):
            return "Failed to encode request body: \(error.localizedDescription)"
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .networkError(let error):
            return "Network error occurred: \(error.localizedDescription)"
        case .maxRetriesReached(let lastError):
            if let lastError = lastError {
                return "Failed to generate blueprint after maximum retries. Last error: \(lastError.localizedDescription)"
            }
            return "Failed to generate blueprint after maximum retries."
        case .missingAPIKey:
            return "Groq API Key is missing. Please add GROQ_API_KEY to your Info.plist."
        }
    }
}

// MARK: - Blueprint Request
fileprivate struct BlueprintRequest: Codable {
    let prompt: String
}

// MARK: - Blueprint Service Protocol
protocol BlueprintServiceProtocol: Sendable {
    func generateBlueprint(for prompt: String) async throws -> ReelsBlueprint
}

// MARK: - Blueprint Service
actor BlueprintService: BlueprintServiceProtocol {
    private let endpointURL: URL
    private let urlSession: URLSession
    private let logger = Logger(subsystem: "com.faceless.app", category: "BlueprintService")
    
    // Configuration for retries
    private let maxRetries: Int = 3
    private let baseDelay: TimeInterval = 1.0 // seconds
    
    init(
        endpointString: String = "https://api.groq.com/openai/v1/chat/completions",
        urlSession: URLSession = .shared
    ) {
        guard let url = URL(string: endpointString) else {
            fatalError("Invalid endpoint URL string provided to BlueprintService.")
        }
        self.endpointURL = url
        self.urlSession = urlSession
    }
    
    func generateBlueprint(for prompt: String) async throws -> ReelsBlueprint {
        logger.info("Starting blueprint generation via Groq for prompt: \(prompt, privacy: .private)")
        
        let apiKey = APIEnvironment.groqApiKey
        guard !apiKey.isEmpty else {
            logger.error("Groq API Key is missing. Cannot generate blueprint.")
            throw BlueprintError.missingAPIKey
        }

        var currentAttempt = 0
        var lastError: Error?

        while currentAttempt <= maxRetries {
            do {
                return try await performOpenAIRequest(prompt: prompt)
            } catch {
                lastError = error
                currentAttempt += 1
                logger.warning("Attempt \(currentAttempt) failed: \(error.localizedDescription)")

                if currentAttempt > maxRetries {
                    logger.error("Max retries reached.")
                    throw BlueprintError.maxRetriesReached(lastError)
                }

                let delay = baseDelay * pow(2.0, Double(currentAttempt - 1))
                logger.info("Retrying in \(delay) seconds...")
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }

        throw BlueprintError.maxRetriesReached(lastError)
    }

    private func performOpenAIRequest(prompt: String) async throws -> ReelsBlueprint {
        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(APIEnvironment.groqApiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let systemPrompt = """
        Sen Instagram, TikTok ve YouTube Shorts için milyonlarca izlenme alan, yüzsüz (faceless) videolar üreten dahi bir Yaratıcı Yönetmensin.
        Görevin, kullanıcının konusunu alıp, 20-30 saniyelik, son derece profesyonel, dinamik ve çok sahneli bir video taslağı (JSON) oluşturmaktır.

        SİSTEM KURALLARI VE VİRAL VİDEO MATEMATİĞİ:

        1. YAPISAL ZORUNLULUKLAR:
        - Sadece ve sadece geçerli bir JSON formatı döndür. Ekstra hiçbir metin yazma.
        - Video toplam 20 ile 30 saniye arasında olmalıdır.
        - Videoyu en az 4, en fazla 6 farklı sahneye (Scene) böl. İzleyicinin sıkılmaması için her sahnenin 'duration' değeri 3 ile 6 saniye arasında değişmelidir.

        2. İÇERİK VE METİN (KOPYA) PSİKOLOJİSİ:
        - KULLANICI GİRDİSİ KURALI: Kullanıcının sana gönderdiği metin okunacak bir metin değildir, bir talimattır (brief). Kullanıcının yazdığını ASLA 'voiceover_script' veya 'on_screen_text' içine kopyalama. Bu talimatı al ve sıfırdan, kancası (hook) çok güçlü, TikTok/Reels dinamiklerine uygun yepyeni bir senaryo yaz.
        - 1. Sahne (Hook): Asla "Bu uygulama..." diye başlama. Çok güçlü, merak uyandıran veya acı noktasına dokunan bir soruyla/iddialı bir cümleyle başla.
        - 2. ve 3. Sahneler (Body): Problemi derinleştir veya çok ilginç bir istatistik/bilgi ver.
        - Son Sahne (CTA): Net bir çözüm ve eylem çağrısı sun. Kaydet, yorum yap vs.
        - Seslendirme (voiceover_script) çok doğal, samimi ve ikna edici olmalı.
        - Ekranda yazan metin (on_screen_text) seslendirmenin aynısı olmak zorunda değil; daha kısa, vurucu ve büyük puntolarla okunacak özet kelimeler olmalı.

        3. GÖRSEL YÖNETMENLİK VE KÜLTÜREL HASSASİYET (PEXELS/PIXABAY API):
        - 'video_search_keyword' KESİNLİKLE İNGİLİZCE olmalıdır.
        - Her sahnenin 'video_search_keyword' değeri birbirinden TAMAMEN FARKLI olmalıdır ki video sürekli aksın.
        - B-ROLL GÖRSEL KURALI: Kullanıcı soyut bir kavram verdiğinde Pexels/Pixabay'de bu kelimeleri doğrudan aratma. Bunun yerine ruh halini yansıtan 'rainy window coffee, macro water drops, peaceful misty forest, aesthetic dark desk' gibi son derece premium, estetik ve soyut İngilizce B-Roll arama kelimeleri (video_search_keyword) üret.
        - ÇOK ÖNEMLİ KÜLTÜREL KURAL: Eğer konu "Zikir, dua, İslam, ibadet, maneviyat" içeriyorsa ASLA "yoga, meditation, zen, buddha" gibi kelimeler KULLANMA. Bunun yerine "peaceful nature, sunset clouds, macro leaf, forest light, beautiful mosque architecture, abstract particles, calm water, starry night" gibi kültürel olarak tarafsız, estetik, huzur verici ve premium sinematik kelimeler seç.
        - Anahtar kelimeler kısa (1-3 kelime) ve dikey formata uygun hisler barındırmalıdır (Örn: "dark aesthetic coding", "exhausted person night", "peaceful forest").

        BEKLENEN JSON FORMATI:
        {
          "format": "POV | Listicle | Storytime | Question",
          "audio_mood": "lofi_melancholic | cinematic_ambient | upbeat_tech",
          "text_animation_style": "karaoke | typewriter | pop",
          "scenes": [
            {
              "duration": 4.5,
              "on_screen_text": "Kısa ve vurucu metin",
              "voiceover_script": "Seslendirme metni buraya",
              "video_search_keyword": "english pexels query"
            }
          ]
        }
        """
        
        let parameters: [String: Any] = [
            "model": "llama-3.1-8b-instant",
            "response_format": ["type": "json_object"],
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": prompt]
            ]
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: parameters)
        } catch {
            throw BlueprintError.encodingError(error)
        }
        
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            throw BlueprintError.networkError(error)
        }
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BlueprintError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            throw BlueprintError.httpError(statusCode: httpResponse.statusCode, data: data)
        }
        
        do {
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard let choices = json?["choices"] as? [[String: Any]],
                  let message = choices.first?["message"] as? [String: Any],
                  let content = message["content"] as? String,
                  let contentData = content.data(using: .utf8) else {
                throw BlueprintError.decodingError(NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid JSON structure"]))
            }
            
            let blueprint = try JSONDecoder().decode(ReelsBlueprint.self, from: contentData)
            logger.info("Successfully generated blueprint from Groq.")
            return blueprint
        } catch {
            throw BlueprintError.decodingError(error)
        }
    }
}
