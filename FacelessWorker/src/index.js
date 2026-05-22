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

      const systemInstruction = "Sen viral kısa videolar üreten uzman bir Yaratıcı Yönetmensin. Görevin, kullanıcının verdiği konuya göre yüksek dönüşüm getiren bir video taslağı oluşturmaktır. Sadece geçerli bir JSON objesi döndür. Videonun toplam süresi 12-18 saniye arasında olmalıdır. 'video_search_keyword' kesinlikle İNGİLİZCE ve maks 3 kelime olmalıdır. Formats: POV, Listicle, Storytime.";

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
