from fastapi import APIRouter
from pydantic import BaseModel
router = APIRouter()
class SummaryRequest(BaseModel):
    conversation: str
class SummaryResponse(BaseModel):
    summary: str
@router.post("/summary", response_model=SummaryResponse)
def summarize(req: SummaryRequest):
    text = req.conversation
    return SummaryResponse(summary=(text[:200] + "...") if len(text) > 200 else text)
class ClearRequest(BaseModel):
    conversation_id: str
@router.post("/clear")
def clear(_: ClearRequest):
    return {"status": "cleared"}
