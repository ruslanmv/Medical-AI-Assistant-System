from fastapi import FastAPI
from .symptom_analyzer_service import router as symptom_router
from .medical_kb_service import router as kb_router
from .drug_interactions_service import router as drug_router
from .appointment_scheduler_service import router as appt_router
from .conversation_service import router as convo_router
app = FastAPI(title="Medical Tool Services")
app.include_router(symptom_router, prefix="/symptoms")
app.include_router(kb_router, prefix="/kb")
app.include_router(drug_router, prefix="/drugs")
app.include_router(appt_router, prefix="/schedule")
app.include_router(convo_router, prefix="/conversation")
