from fastapi import APIRouter, Query
from pydantic import BaseModel
from typing import List
router = APIRouter()
class KBResult(BaseModel):
    title: str; url: str; snippet: str
class KBResponse(BaseModel):
    results: List[KBResult]
@router.get("/search", response_model=KBResponse)
def kb_search(q: str = Query(...)):
    hits = [KBResult(title=f"WHO guidance: {q}", url="https://www.who.int/", snippet="Official WHO guidance."),
            KBResult(title=f"CDC overview: {q}", url="https://www.cdc.gov/", snippet="CDC clinical overview.")]
    return KBResponse(results=hits)
