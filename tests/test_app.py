"""
Unit tests for Disease Detector Application
These tests are run during CI/CD pipeline
"""

import pytest
import json
from app import app, DISEASE_SYMPTOMS

@pytest.fixture
def client():
    """Create test client"""
    app.config['TESTING'] = True
    with app.test_client() as client:
        yield client

def test_health_endpoint(client):
    """Test health check endpoint"""
    response = client.get('/health')
    assert response.status_code == 200
    data = json.loads(response.data)
    assert 'status' in data
    assert data['status'] == 'healthy'

def test_predict_endpoint_missing_symptoms(client):
    """Test predict endpoint with missing symptoms"""
    response = client.post('/predict', 
                         json={},
                         content_type='application/json')
    assert response.status_code == 400
    data = json.loads(response.data)
    assert 'error' in data

def test_predict_endpoint_with_symptoms(client):
    """Test predict endpoint with symptoms"""
    response = client.post('/predict',
                         json={'symptoms': 'fever, cough, headache'},
                         content_type='application/json')
    assert response.status_code == 200
    data = json.loads(response.data)
    assert 'predictions' in data
    assert len(data['predictions']) > 0

def test_disease_symptoms_defined():
    """Test that disease symptoms are properly defined"""
    assert len(DISEASE_SYMPTOMS) > 0
    for disease, symptoms in DISEASE_SYMPTOMS.items():
        assert isinstance(symptoms, list)
        assert len(symptoms) > 0

def test_predict_with_patient_id(client):
    """Test predict endpoint with patient ID"""
    # First register a patient
    register_response = client.post('/patient/register',
                                   json={'patient_id': 'TEST001', 'name': 'Test Patient'},
                                   content_type='application/json')
    
    # Then make prediction
    response = client.post('/predict',
                         json={
                             'symptoms': 'fever, cough',
                             'patient_id': 'TEST001'
                         },
                         content_type='application/json')
    assert response.status_code == 200
    data = json.loads(response.data)
    assert 'predictions' in data


