"""Medical Orchestrator Flow (skeleton)
- Intake happens in medical_frontdoor_agent
- This flow coordinates Emergency → Specialty → Coordinator
"""
from ibm_watsonx_orchestrate.flow_builder import Flow, START, END, Branch, Expression

def build_flow():
    aflow = Flow(name="medical_orchestrator_flow", description="Route medical cases through triage and specialty")
    # Steps
    emergency = aflow.agent(
        name="emergency_step",
        agent="emergency_triage_agent",
        description="Screen for emergencies",
    )
    router = aflow.agent(
        name="route_to_specialist",
        agent="medical_coordinator_agent",
        description="Route to proper specialist and compose final answer",
    )

    # Edges
    aflow.edge(START, emergency)
    aflow.edge(emergency, router)
    aflow.edge(router, END)

    return aflow
