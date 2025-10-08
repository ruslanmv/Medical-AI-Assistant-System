from fastapi import APIRouter
from pydantic import BaseModel
from uuid import uuid4
router = APIRouter()
class AppointmentRequest(BaseModel):
    specialty: str; patient_name: str; preferred_time: str; location: str
class AppointmentResponse(BaseModel):
    confirmation_id: str; time: str; location: str
@router.post("/appointments", response_model=AppointmentResponse, status_code=201)
def schedule(payload: AppointmentRequest):
    return AppointmentResponse(confirmation_id=str(uuid4()), time=payload.preferred_time, location=payload.location)
