from app import stores


def test_default_roster_starts_dark_urge_in_camp():
    roster = stores._normalize_roster([])

    dark_urge = next(member for member in roster if member.id == "dark-urge")
    assert dark_urge.name == "Dark Urge"
    assert dark_urge.class_name == "Sorcerer"
    assert dark_urge.status == "camp"
