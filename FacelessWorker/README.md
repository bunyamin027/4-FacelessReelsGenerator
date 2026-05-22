# Faceless Reels Generator - Cloudflare Worker

This Cloudflare Worker acts as a secure proxy for the Gemini API. It accepts a POST request with a topic, combines it with an expert creative director system prompt, and returns a structured JSON payload for creating viral short videos.

## Deployment Instructions

1. **Install Wrangler CLI** (if you haven't already):
   ```bash
   npm install -g wrangler
   ```

2. **Deploy the Worker**:
   Navigate to this directory in your terminal and run:
   ```bash
   npx wrangler deploy
   ```

3. **Set the API Key Secret**:
   After the worker is deployed, you must provide your Gemini API key so the worker can authenticate with Google. Run the following command:
   ```bash
   npx wrangler secret put GEMINI_API_KEY
   ```
   When prompted, paste your actual Gemini API key.

## API Usage

Once deployed, you can interact with the worker via POST requests.

**Endpoint:** `https://<YOUR_WORKER_SUBDOMAIN>.workers.dev`
**Method:** `POST`
**Content-Type:** `application/json`

**Request Body:**
```json
{
  "prompt": "Motivation for entrepreneurs"
}
```

**Response:**
Returns the raw JSON response directly from the Gemini API, with CORS headers fully configured so it can be called from your frontend applications.
