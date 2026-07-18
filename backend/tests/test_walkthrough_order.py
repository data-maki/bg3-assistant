from app.walkthrough_data import load_walkthrough


def test_duergar_boat_fight_precedes_grymforge_arrival():
    steps = {step.id: step for step in load_walkthrough()}
    boat = steps["walk-duergar-boat"]
    arrival = steps["walk-grymforge-arrival"]

    assert arrival.order == boat.order + 1
    assert boat.phase_order < arrival.phase_order
    assert arrival.prerequisites == [boat.id]
