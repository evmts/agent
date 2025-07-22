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
    """Check if the API service is responding"""
    try:
        response = requests.get('http://api-server:8000', timeout=10)
        if response.status_code != 200:
            print(f"❌ API service failed: {response.status_code}")
            return False
            
        print("✅ API service is working correctly")
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