#!/usr/bin/env python3
"""Test the skills API endpoint in isolation."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

# Import just what we need to test
from fastapi import FastAPI
from fastapi.testclient import TestClient

# Create a minimal app
app = FastAPI()

# Import and register the skills router
from server.routes.skills import router as skills_router
app.include_router(skills_router)

# Create test client
client = TestClient(app)


def test_list_skills():
    """Test GET /skill endpoint."""
    print("Testing GET /skill...")
    response = client.get("/skill")
    assert response.status_code == 200, f"Expected 200, got {response.status_code}"

    skills = response.json()
    print(f"✓ Got {len(skills)} skills")
    for skill in skills:
        print(f"  - {skill['name']}: {skill['description']}")

    return len(skills) > 0


def test_search_skills():
    """Test GET /skill?query=python."""
    print("\nTesting GET /skill?query=python...")
    response = client.get("/skill?query=python")
    assert response.status_code == 200

    skills = response.json()
    print(f"✓ Found {len(skills)} skills matching 'python'")
    for skill in skills:
        print(f"  - {skill['name']}")

    return len(skills) > 0


def test_get_skill():
    """Test GET /skill/{skill_name}."""
    print("\nTesting GET /skill/python-best-practices...")
    response = client.get("/skill/python-best-practices")
    assert response.status_code == 200

    skill = response.json()
    if skill:
        print(f"✓ Retrieved skill: {skill['name']}")
        print(f"  Description: {skill['description']}")
        print(f"  File path: {skill['file_path']}")
        return True
    else:
        print("✗ Skill not found")
        return False


def test_reload_skills():
    """Test POST /skill/reload."""
    print("\nTesting POST /skill/reload...")
    response = client.post("/skill/reload")
    assert response.status_code == 200

    result = response.json()
    print(f"✓ Reloaded {result['count']} skills")

    return result['count'] > 0


def main():
    """Run all API tests."""
    print("=" * 60)
    print("Skills API Endpoint Tests")
    print("=" * 60)

    tests = [
        ("List Skills", test_list_skills),
        ("Search Skills", test_search_skills),
        ("Get Skill", test_get_skill),
        ("Reload Skills", test_reload_skills),
    ]

    results = []
    for test_name, test_func in tests:
        try:
            result = test_func()
            results.append((test_name, result))
        except Exception as e:
            print(f"\n✗ {test_name} failed with exception: {e}")
            import traceback
            traceback.print_exc()
            results.append((test_name, False))

    print("\n" + "=" * 60)
    print("API Test Results Summary")
    print("=" * 60)

    passed = sum(1 for _, result in results if result)
    total = len(results)

    for test_name, result in results:
        status = "✓ PASS" if result else "✗ FAIL"
        print(f"{status}: {test_name}")

    print(f"\nTotal: {passed}/{total} tests passed")

    return 0 if passed == total else 1


if __name__ == "__main__":
    sys.exit(main())
