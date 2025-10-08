from fastapi import APIRouter, Query
from pydantic import BaseModel
from typing import List
router = APIRouter()
class Interaction(BaseModel):
    pair: str; severity: str; note: str
class InteractionsResponse(BaseModel):
    interactions: List[Interaction]
@router.get("/interactions", response_model=InteractionsResponse)
def interactions(drugs: List[str] = Query(...)):
    pairs = []
    for i in range(len(drugs)):
        for j in range(i+1, len(drugs)):
            pairs.append(Interaction(pair=f"{drugs[i]} + {drugs[j]}", severity="moderate", note="Check clinician guidance."))
    return InteractionsResponse(interactions=pairs)
