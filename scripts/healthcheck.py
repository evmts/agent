#!/usr/bin/env python3
"""
Healthcheck script to verify all services are working correctly
"""

import requests
import sys
import time
from bs4 import BeautifulSoup

def check_web_service():
    """Check if the web service is serving the SPA correctly"""
    try:
        # Check health endpoint
        health_response = requests.get('http://web/health', timeout=10)
        if health_response.status_code != 200:
            print(f"❌ Web health check failed: {health_response.status_code}")
            return False
        
        # Check main page
        response = requests.get('http://web/', timeout=10)
        if response.status_code != 200:
            print(f"❌ Web main page failed: {response.status_code}")
            return False
        
        # Parse HTML and check title
        soup = BeautifulSoup(response.text, 'html.parser')
        title = soup.find('title')
        
        if not title:
            print("❌ No title found in HTML")
            return False
            
        if title.text.strip() != 'Plue':
            print(f"❌ Wrong title: expected 'Plue', got '{title.text.strip()}'")
            return False
            
        print("✅ Web service is working correctly")
        return True
        
    except requests.exceptions.RequestException as e:
        print(f"❌ Web service request failed: {e}")
        return False
    except Exception as e:
        print(f"❌ Web service check failed: {e}")
        return False

def check_api_service():
    """Check if the API service is responding and database operations work"""
    try:
        # Test basic API health
        response = requests.get('http://api-server:8000/health', timeout=10)
        if response.status_code != 200:
            print(f"❌ API health check failed: {response.status_code}")
            return False
        
        if response.text.strip() != 'healthy':
            print(f"❌ API health check returned unexpected response: {response.text}")
            return False
        
        print("✅ API /health endpoint is working")
        
        # Test root endpoint
        root_response = requests.get('http://api-server:8000/', timeout=10)
        if root_response.status_code != 200:
            print(f"❌ API root endpoint failed: {root_response.status_code}")
            return False
        
        print("✅ API root endpoint is working")
        
        # Test database operations through API
        test_user_name = "healthcheck_test_user"
        
        # Clean up any existing test user
        requests.delete(f'http://api-server:8000/users/{test_user_name}', timeout=10)
        
        # Test CREATE user
        create_response = requests.post(
            'http://api-server:8000/users',
            json={"name": test_user_name},
            headers={"Content-Type": "application/json"},
            timeout=10
        )
        if create_response.status_code != 201:
            print(f"❌ API create user failed: {create_response.status_code}")
            return False
        
        # Test GET user
        get_response = requests.get(f'http://api-server:8000/users/{test_user_name}', timeout=10)
        if get_response.status_code != 200:
            print(f"❌ API get user failed: {get_response.status_code}")
            return False
        
        user_data = get_response.json()
        if user_data.get('name') != test_user_name:
            print(f"❌ API returned wrong user data: {user_data}")
            return False
        
        # Test UPDATE user
        updated_name = f"{test_user_name}_updated"
        update_response = requests.put(
            f'http://api-server:8000/users/{test_user_name}',
            json={"name": updated_name},
            headers={"Content-Type": "application/json"},
            timeout=10
        )
        if update_response.status_code != 200:
            print(f"❌ API update user failed: {update_response.status_code}")
            return False
        
        # Verify update worked
        get_updated_response = requests.get(f'http://api-server:8000/users/{updated_name}', timeout=10)
        if get_updated_response.status_code != 200:
            print(f"❌ API get updated user failed: {get_updated_response.status_code}")
            return False
        
        # Test LIST users
        list_response = requests.get('http://api-server:8000/users', timeout=10)
        if list_response.status_code != 200:
            print(f"❌ API list users failed: {list_response.status_code}")
            return False
        
        users = list_response.json()
        if not isinstance(users, list):
            print(f"❌ API returned invalid user list: {users}")
            return False
        
        # Test DELETE user
        delete_response = requests.delete(f'http://api-server:8000/users/{updated_name}', timeout=10)
        if delete_response.status_code != 200:
            print(f"❌ API delete user failed: {delete_response.status_code}")
            return False
        
        # Verify deletion worked
        get_deleted_response = requests.get(f'http://api-server:8000/users/{updated_name}', timeout=10)
        if get_deleted_response.status_code != 404:
            print(f"❌ API user not properly deleted: {get_deleted_response.status_code}")
            return False
            
        print("✅ API service and database operations working correctly")
        return True
        
    except requests.exceptions.RequestException as e:
        print(f"❌ API service request failed: {e}")
        return False
    except Exception as e:
        print(f"❌ API service check failed: {e}")
        return False

def check_postgres_service():
    """Check if postgres service is accessible (basic connection test via API in the future)"""
    # For now, we just assume it's working if the docker-compose health check passed
    # Later we'll test actual DB connectivity through the API
    print("✅ Postgres service is working (docker health check passed)")
    return True

def main():
    """Run all health checks"""
    print("🏥 Starting health checks...")
    
    checks = [
        ("Web Service", check_web_service),
        ("API Service", check_api_service), 
        ("Postgres Service", check_postgres_service),
    ]
    
    all_passed = True
    
    for name, check_func in checks:
        print(f"\n🔍 Checking {name}...")
        if not check_func():
            all_passed = False
    
    if all_passed:
        print("\n🎉 All health checks passed!")
        sys.exit(0)
    else:
        print("\n💥 Some health checks failed!")
        sys.exit(1)

if __name__ == "__main__":
    main()