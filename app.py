import httpx
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

app = FastAPI()

RSPAMD_URL = "http://127.0.0.1:11333/checkv2"

class CheckRequest(BaseModel):
    content: str

def normalize_rspamd(data: dict) -> dict:
    raw_score = float(data.get("score", 0))
    threshold = float(data.get("required_score", 15.0))

    normalized_score = max(0, min(100, round(100 - (raw_score / threshold) * 50)))
    verdict = "pass" if normalized_score >= 70 else "warn" if normalized_score >= 40 else "fail"

    symbols = data.get("symbols", {}) or {}
    rules = []

    for name, details in symbols.items():
        score = float(details.get("score", 0) or 0)
        description = details.get("description") or details.get("name") or name
        if score != 0:
            rules.append({
                "name": name,
                "score": score,
                "description": description,
            })

    rules.sort(key=lambda x: abs(x["score"]), reverse=True)

    return {
        "provider": "rspamd",
        "raw_score": raw_score,
        "threshold": threshold,
        "normalized_score": normalized_score,
        "verdict": verdict,
        "rules": rules[:20],
        "action": data.get("action"),
        "summary": f"Rspamd score {raw_score} against threshold {threshold}.",
        "version": "Rspamd external service"
    }

@app.get("/health")
async def health():
    return {"ok": True}

@app.post("/check")
async def check(req: CheckRequest):
    if not req.content.strip():
        raise HTTPException(status_code=400, detail="content is required")

    try:
        async with httpx.AsyncClient(timeout=12.0) as client:
            response = await client.post(
                RSPAMD_URL,
                content=req.content.encode("utf-8"),
                headers={
                    "Content-Type": "message/rfc822"
                }
            )

        if response.status_code >= 400:
            raise HTTPException(status_code=502, detail=f"Rspamd returned {response.status_code}")

        data = response.json()
        return normalize_rspamd(data)

    except httpx.TimeoutException:
        raise HTTPException(status_code=504, detail="Rspamd timeout")
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
