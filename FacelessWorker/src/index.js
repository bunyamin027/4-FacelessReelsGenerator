export default {
  async fetch(request, env, ctx) {
    // Handle CORS preflight requests
    if (request.method === "OPTIONS") {
      return new Response(null, {
        headers: {
          "Access-Control-Allow-Origin": "*",
          "Access-Control-Allow-Methods": "POST, OPTIONS",
          "Access-Control-Allow-Headers": "Content-Type",
        },
      });
    }

    // Must only accept POST requests
    if (request.method !== "POST") {
      return new Response(JSON.stringify({ error: "Method not allowed. Only POST is accepted." }), {
        status: 405,
        headers: {
          "Content-Type": "application/json",
          "Access-Control-Allow-Origin": "*",
        },
      });
    }

    try {
      const body = await request.json();
      const userPrompt = body.prompt;

      if (!userPrompt) {
        return new Response(JSON.stringify({ error: "Missing 'prompt' in request body." }), {
          status: 400,
          headers: {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*",
          },
        });
      }

      const systemInstruction = `Sen Instagram, TikTok ve YouTube Shorts için milyonlarca izlenme alan, yüzsüz (faceless) videolar üreten dahi bir Yaratıcı Yönetmensin.
Görevin, kullanıcının verdiği uygulama adını ve konusunu alıp, 20-30 saniyelik, son derece profesyonel, dinamik ve çok sahneli bir video taslağı (JSON) oluşturmaktır.

SİSTEM KURALLARI VE VİRAL VİDEO MATEMATİĞİ:

1. YAPISAL ZORUNLULUKLAR:
- Sadece ve sadece geçerli bir JSON formatı döndür. Ekstra hiçbir metin yazma.
- Video toplam 20 ile 30 saniye arasında olmalıdır.
- Videoyu en az 4, en fazla 6 farklı sahneye (Scene) böl. İzleyicinin sıkılmaması için her sahnenin 'duration' değeri 3 ile 6 saniye arasında değişmelidir.

2. İÇERİK VE METİN (KOPYA) PSİKOLOJİSİ:
- KULLANICI GİRDİSİ KURALI: Kullanıcının sana gönderdiği metin okunacak bir metin değildir, bir talimattır (brief). Kullanıcının yazdığını ASLA 'voiceover_script' içine kopyalama. Bu talimatı al ve sıfırdan, kancası (hook) çok güçlü, TikTok/Reels dinamiklerine uygun yepyeni bir senaryo yaz.
- 1. Sahne (Hook): Asla "Bu uygulama..." diye başlama. Çok güçlü, merak uyandıran veya acı noktasına dokunan bir soruyla/iddialı bir cümleyle başla.
- 2. ve 3. Sahneler (Body): Problemi derinleştir veya çok ilginç bir istatistik/bilgi ver.
- Son Sahne (CTA): Uygulamanın adını vererek net bir çözüm ve eylem çağrısı sun.
- Seslendirme (voiceover_script) çok doğal, samimi ve ikna edici olmalı.
- Ekranda yazan metin (on_screen_text) seslendirmenin aynısı olmak zorunda değil; daha kısa, vurucu ve büyük puntolarla okunacak özet kelimeler olmalı.

3. GÖRSEL YÖNETMENLİK VE KÜLTÜREL HASSASİYET (PEXELS/PIXABAY API):
- 'video_search_keyword' KESİNLİKLE İNGİLİZCE olmalıdır.
- Her sahnenin 'video_search_keyword' değeri birbirinden TAMAMEN FARKLI olmalıdır ki video sürekli aksın.
- B-ROLL GÖRSEL KURALI: Kullanıcı Zikrify, din veya soyut bir kavram verdiğinde Pexels/Pixabay'de bu kelimeleri doğrudan aratma. Bunun yerine ruh halini yansıtan 'rainy window coffee, macro water drops, peaceful misty forest, aesthetic dark desk' gibi son derece premium, estetik ve soyut İngilizce B-Roll arama kelimeleri (video_search_keyword) üret.
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
}`;

      const geminiPayload = {
        contents: [
          {
            role: "user",
            parts: [
              { text: `${systemInstruction}\n\nKullanıcı Konusu: ${userPrompt}` }
            ]
          }
        ]
      };

      const apiKey = env.GEMINI_API_KEY;
      if (!apiKey) {
        return new Response(JSON.stringify({ error: "GEMINI_API_KEY secret is not configured." }), {
          status: 500,
          headers: {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*",
          },
        });
      }

      const geminiUrl = `https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:generateContent?key=${apiKey}`;

      const response = await fetch(geminiUrl, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify(geminiPayload),
      });

      const data = await response.json();

      return new Response(JSON.stringify(data), {
        status: response.status,
        headers: {
          "Content-Type": "application/json",
          "Access-Control-Allow-Origin": "*",
        },
      });

    } catch (error) {
      return new Response(JSON.stringify({ error: "Internal Server Error", details: error.message }), {
        status: 500,
        headers: {
          "Content-Type": "application/json",
          "Access-Control-Allow-Origin": "*",
        },
      });
    }
  },
};
