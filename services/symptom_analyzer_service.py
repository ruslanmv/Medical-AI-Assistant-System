from fastapi import APIRouter
from pydantic import BaseModel
from typing import List
router = APIRouter()
class SymptomRequest(BaseModel):
    text: str
class SymptomResponse(BaseModel):
    entities: List[str]
    urgency: str
    red_flags: List[str]
@router.post("/analyze", response_model=SymptomResponse)
def analyze_symptoms(payload: SymptomRequest):
    text = payload.text.lower()
    lex = ["cough","fever","pain","wheeze","dizziness"]
    entities = [w for w in lex if w in text]
    flags = ["crushing chest pain","blue lips","confusion","worst headache"]
    red = [w for w in flags if w in text]
    urgency = "high" if red else ("medium" if any(e in ["pain","dizziness"] for e in entities) else "low")
    return SymptomResponse(entities=entities, urgency=urgency, red_flags=red)
