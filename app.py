from flask import Flask, request, jsonify, render_template
from flask_cors import CORS
import torch
from transformers import AutoTokenizer, AutoModel
from sklearn.metrics.pairwise import cosine_similarity
import numpy as np
import json
import os
import sqlite3
from datetime import datetime
from contextlib import closing
import logging
from logging.handlers import RotatingFileHandler
import socket
import sys

app = Flask(__name__)
CORS(app)

# Database configuration
DATABASE = os.getenv('DATABASE_PATH', 'patients.db')

# Configure logging for ELK Stack integration
def setup_logging():
    """Configure application logging to feed into ELK Stack"""
    log_level = os.getenv('LOG_LEVEL', 'INFO').upper()
    log_dir = os.getenv('LOG_DIR', 'logs')
    
    # Create log directory if it doesn't exist
    os.makedirs(log_dir, exist_ok=True)
    
    # Configure root logger
    logger = logging.getLogger()
    logger.setLevel(getattr(logging, log_level))
    
    # File handler with rotation
    file_handler = RotatingFileHandler(
        os.path.join(log_dir, 'disease-detector.log'),
        maxBytes=10485760,  # 10MB
        backupCount=5
    )
    file_handler.setLevel(logging.INFO)
    
    # JSON formatter for Logstash
    class JSONFormatter(logging.Formatter):
        def format(self, record):
            log_data = {
                'timestamp': datetime.utcnow().isoformat(),
                'level': record.levelname,
                'logger': record.name,
                'message': record.getMessage(),
                'module': record.module,
                'function': record.funcName,
                'line': record.lineno,
                'hostname': socket.gethostname(),
                'service': 'disease-detector'
            }
            
            # Add exception info if present
            if record.exc_info:
                log_data['exception'] = self.formatException(record.exc_info)
            
            # Add extra fields from record
            if hasattr(record, 'patient_id'):
                log_data['patient_id'] = record.patient_id
            if hasattr(record, 'disease'):
                log_data['disease'] = record.disease
            if hasattr(record, 'symptoms'):
                log_data['symptoms'] = record.symptoms
            
            return json.dumps(log_data)
    
    file_handler.setFormatter(JSONFormatter())
    logger.addHandler(file_handler)
    
    # Console handler for development
    console_handler = logging.StreamHandler(sys.stdout)
    console_handler.setLevel(logging.DEBUG)
    console_formatter = logging.Formatter(
        '%(asctime)s - %(name)s - %(levelname)s - %(message)s'
    )
    console_handler.setFormatter(console_formatter)
    logger.addHandler(console_handler)
    
    return logger

# Initialize logging
logger = setup_logging()

# Initialize multiple models for ensemble prediction
# Using multiple medical models for better accuracy
# Note: Some models may fail to load, but we'll use what's available
MODELS_CONFIG = [
    {
        'name': 'Bio_ClinicalBERT',
        'model_name': 'emilyalsentzer/Bio_ClinicalBERT',
        'weight': 0.40,  # Higher weight for clinical model
        'tokenizer': None,
        'model': None
    },
    {
        'name': 'PubMedBERT',
        'model_name': 'microsoft/BiomedNLP-PubMedBERT-base-uncased-abstract-fulltext',
        'weight': 0.35,
        'tokenizer': None,
        'model': None
    },
    {
        'name': 'BioBERT',
        'model_name': 'dmis-lab/biobert-v1.1',
        'weight': 0.25,
        'tokenizer': None,
        'model': None
    }
]

# Fallback to simpler models if some fail to load
FALLBACK_MODELS = [
    {
        'name': 'Bio_ClinicalBERT',
        'model_name': 'emilyalsentzer/Bio_ClinicalBERT',
        'weight': 1.0,
        'tokenizer': None,
        'model': None
    }
]

# Common diseases and their typical symptoms (for fallback/demo)
DISEASE_SYMPTOMS = {
    "Common Cold": ["runny nose", "sneezing", "cough", "sore throat", "congestion"],
    "Flu": ["fever", "chills", "body aches", "fatigue", "cough", "headache"],
    "Migraine": ["severe headache", "nausea", "sensitivity to light", "sensitivity to sound"],
    "Strep Throat": ["sore throat", "fever", "swollen lymph nodes", "white patches on tonsils"],
    "Pneumonia": ["cough", "fever", "shortness of breath", "chest pain", "fatigue"],
    "Bronchitis": ["persistent cough", "mucus production", "fatigue", "shortness of breath"],
    "Sinusitis": ["facial pain", "nasal congestion", "headache", "post-nasal drip"],
    "Gastroenteritis": ["nausea", "vomiting", "diarrhea", "abdominal pain", "fever"],
    "Urinary Tract Infection": ["frequent urination", "burning sensation", "cloudy urine", "pelvic pain"],
    "Allergic Rhinitis": ["sneezing", "runny nose", "itchy eyes", "nasal congestion"]
}

def get_db():
    """Get database connection"""
    conn = sqlite3.connect(DATABASE)
    conn.row_factory = sqlite3.Row
    return conn

def init_db():
    """Initialize database with tables"""
    with closing(get_db()) as conn:
        cursor = conn.cursor()
        # Patients table
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS patients (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                patient_id TEXT UNIQUE NOT NULL,
                name TEXT,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        ''')
        # Medical history table
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS medical_history (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                patient_id TEXT NOT NULL,
                symptoms TEXT NOT NULL,
                predicted_disease TEXT,
                confidence REAL,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                FOREIGN KEY (patient_id) REFERENCES patients(patient_id)
            )
        ''')
        conn.commit()
    print("Database initialized successfully!")

def load_models():
    """Load multiple models for ensemble prediction"""
    global MODELS_CONFIG, FALLBACK_MODELS
    loaded_models = []
    
    print("Loading ensemble of medical models for improved accuracy...")
    
    for model_config in MODELS_CONFIG:
        try:
            print(f"Loading {model_config['name']}...")
            tokenizer = AutoTokenizer.from_pretrained(model_config['model_name'])
            model = AutoModel.from_pretrained(model_config['model_name'])
            model.eval()
            
            model_config['tokenizer'] = tokenizer
            model_config['model'] = model
            loaded_models.append(model_config['name'])
            print(f"✓ {model_config['name']} loaded successfully!")
            
        except Exception as e:
            print(f"✗ Failed to load {model_config['name']}: {e}")
            print(f"  Continuing with other models...")
            model_config['tokenizer'] = None
            model_config['model'] = None
    
    # If no models loaded, try fallback
    if not loaded_models:
        print("No models loaded, trying fallback...")
        for model_config in FALLBACK_MODELS:
            try:
                print(f"Loading fallback {model_config['name']}...")
                tokenizer = AutoTokenizer.from_pretrained(model_config['model_name'])
                model = AutoModel.from_pretrained(model_config['model_name'])
                model.eval()
                
                model_config['tokenizer'] = tokenizer
                model_config['model'] = model
                loaded_models.append(model_config['name'])
                print(f"✓ Fallback model loaded!")
                break
            except Exception as e:
                print(f"✗ Fallback failed: {e}")
    
    if loaded_models:
        print(f"\n✓ Successfully loaded {len(loaded_models)} model(s): {', '.join(loaded_models)}")
        print("Using ensemble prediction for improved accuracy!")
    else:
        print("\n⚠ No models loaded. Using fallback symptom matching only.")
    
    return loaded_models

def get_loaded_models():
    """Get list of successfully loaded models"""
    loaded = []
    for model_config in MODELS_CONFIG:
        if model_config['model'] is not None and model_config['tokenizer'] is not None:
            loaded.append(model_config)
    if not loaded:
        for model_config in FALLBACK_MODELS:
            if model_config['model'] is not None and model_config['tokenizer'] is not None:
                loaded.append(model_config)
    return loaded

def predict_disease_simple(symptoms_text):
    """Simple symptom matching approach"""
    symptoms_lower = symptoms_text.lower()
    scores = {}
    
    for disease, typical_symptoms in DISEASE_SYMPTOMS.items():
        score = 0
        for symptom in typical_symptoms:
            if symptom.lower() in symptoms_lower:
                score += 1
        if score > 0:
            scores[disease] = score / len(typical_symptoms)
    
    # Sort by score
    sorted_diseases = sorted(scores.items(), key=lambda x: x[1], reverse=True)
    return sorted_diseases[:3]  # Return top 3

def get_embedding(text, tokenizer, model):
    """Get embedding vector for text using a specific model"""
    inputs = tokenizer(
        text,
        return_tensors="pt",
        truncation=True,
        max_length=512,
        padding=True
    )
    
    with torch.no_grad():
        outputs = model(**inputs)
        # Use mean pooling of last hidden state
        embeddings = outputs.last_hidden_state.mean(dim=1).squeeze()
    
    return embeddings.numpy()

def extract_symptoms_keywords(symptoms_text):
    """Extract key symptom keywords for better matching"""
    symptoms_lower = symptoms_text.lower()
    keywords = []
    
    # Common symptom keywords
    symptom_keywords = [
        'fever', 'cough', 'headache', 'pain', 'ache', 'sore', 'throat',
        'nausea', 'vomiting', 'diarrhea', 'fatigue', 'tired', 'weak',
        'congestion', 'runny nose', 'sneezing', 'itchy', 'burning',
        'shortness of breath', 'chest pain', 'abdominal pain', 'stomach',
        'chills', 'sweating', 'dizziness', 'light sensitive', 'sound sensitive',
        'swollen', 'red', 'inflamed', 'mucus', 'phlegm', 'urination',
        'frequent', 'cloudy', 'pelvic', 'facial', 'nasal', 'post-nasal'
    ]
    
    for keyword in symptom_keywords:
        if keyword in symptoms_lower:
            keywords.append(keyword)
    
    return keywords

def get_patient_history(patient_id):
    """Get patient's medical history"""
    with closing(get_db()) as conn:
        cursor = conn.cursor()
        cursor.execute('''
            SELECT symptoms, predicted_disease, confidence, created_at
            FROM medical_history
            WHERE patient_id = ?
            ORDER BY created_at DESC
            LIMIT 10
        ''', (patient_id,))
        return [dict(row) for row in cursor.fetchall()]

def predict_disease_ml(symptoms_text, patient_history=None):
    """Ensemble ML-based prediction using multiple models with optional patient history"""
    loaded_models = get_loaded_models()
    
    if not loaded_models:
        return predict_disease_simple(symptoms_text)
    
    try:
        # Combine current symptoms with historical context if available
        if patient_history and len(patient_history) > 0:
            # Extract previous symptoms and diseases from history
            history_text = ""
            previous_diseases = {}
            for record in patient_history[:5]:  # Use last 5 records
                history_text += f"Previous: {record['symptoms']}. "
                if record['predicted_disease']:
                    prev_disease = record['predicted_disease']
                    prev_conf = record.get('confidence', 0) or 0
                    if prev_disease not in previous_diseases:
                        previous_diseases[prev_disease] = []
                    previous_diseases[prev_disease].append(prev_conf)
            
            # Combine history with current symptoms
            enhanced_symptoms = f"{history_text}Current symptoms: {symptoms_text}"
        else:
            enhanced_symptoms = symptoms_text
            previous_diseases = {}
        
        # Extract symptom keywords for enhanced matching
        symptom_keywords = extract_symptoms_keywords(symptoms_text)
        
        # Ensemble prediction: get predictions from all loaded models
        ensemble_scores = {}
        total_weight = 0
        
        for model_config in loaded_models:
            try:
                tokenizer = model_config['tokenizer']
                model = model_config['model']
                weight = model_config['weight']
                
                # Get embedding for input symptoms
                symptom_embedding = get_embedding(enhanced_symptoms, tokenizer, model)
                symptom_embedding = symptom_embedding.reshape(1, -1)
                
                # Get embeddings for each disease's typical symptoms
                disease_scores = {}
                for disease, typical_symptoms in DISEASE_SYMPTOMS.items():
                    # Create a text description of the disease and its symptoms
                    disease_text = f"{disease}: {', '.join(typical_symptoms)}"
                    disease_emb = get_embedding(disease_text, tokenizer, model)
                    disease_emb = disease_emb.reshape(1, -1)
                    
                    # Calculate cosine similarity
                    similarity = cosine_similarity(symptom_embedding, disease_emb)[0][0]
                    disease_scores[disease] = max(0, similarity)
                
                # Weight and accumulate scores
                for disease, score in disease_scores.items():
                    if disease not in ensemble_scores:
                        ensemble_scores[disease] = 0
                    ensemble_scores[disease] += score * weight
                
                total_weight += weight
                
            except Exception as e:
                print(f"Error in {model_config['name']}: {e}")
                continue
        
        # Normalize by total weight
        if total_weight > 0:
            for disease in ensemble_scores:
                ensemble_scores[disease] /= total_weight
        
        # Combine with symptom matching (weighted combination)
        simple_scores = predict_disease_simple(symptoms_text)
        simple_dict = dict(simple_scores)
        
        # Enhanced keyword matching
        keyword_scores = {}
        for disease, typical_symptoms in DISEASE_SYMPTOMS.items():
            keyword_match = 0
            for symptom in typical_symptoms:
                if any(keyword in symptom.lower() for keyword in symptom_keywords):
                    keyword_match += 1
            if keyword_match > 0:
                keyword_scores[disease] = keyword_match / len(typical_symptoms)
        
        # Merge ensemble, simple, and keyword scores
        final_scores = {}
        for disease in DISEASE_SYMPTOMS.keys():
            ensemble_score = ensemble_scores.get(disease, 0)
            simple_score = simple_dict.get(disease, 0)
            keyword_score = keyword_scores.get(disease, 0)
            
            # Weighted combination: 50% ensemble, 30% simple, 20% keyword matching
            base_score = (ensemble_score * 0.5) + (simple_score * 0.3) + (keyword_score * 0.2)
            
            # Boost score if patient has history of this disease
            if disease in previous_diseases:
                avg_prev_confidence = sum(previous_diseases[disease]) / len(previous_diseases[disease])
                # Boost by up to 25% based on previous occurrences
                history_boost = min(0.25, avg_prev_confidence * 0.25)
                base_score = min(1.0, base_score + history_boost)
            
            final_scores[disease] = base_score
        
        # Filter out zero scores and sort
        final_scores = {k: v for k, v in final_scores.items() if v > 0}
        sorted_diseases = sorted(final_scores.items(), key=lambda x: x[1], reverse=True)
        
        # Normalize scores to 0-1 range
        if sorted_diseases:
            max_score = sorted_diseases[0][1]
            if max_score > 0:
                sorted_diseases = [(d, float(min(1.0, s / max_score))) for d, s in sorted_diseases]
        
        return sorted_diseases[:3]
    
    except Exception as e:
        print(f"Ensemble ML prediction error: {e}")
        import traceback
        traceback.print_exc()
        return predict_disease_simple(symptoms_text)

@app.route('/')
def index():
    """Serve the main page"""
    return render_template('index.html')

@app.route('/dashboard')
def dashboard():
    """Serve the performance dashboard"""
    return render_template('dashboard.html')

@app.route('/predict', methods=['POST'])
def predict():
    """API endpoint for disease prediction with patient history support"""
    import time
    start_time = time.time()
    
    try:
        data = request.json
        symptoms = data.get('symptoms', '')
        patient_id = data.get('patient_id', None)
        
        # Log prediction request
        logger.info("Prediction request received", extra={
            'patient_id': patient_id or 'anonymous',
            'symptoms': symptoms[:100] if symptoms else ''  # Log first 100 chars
        })
        
        if not symptoms:
            logger.warning("Prediction request missing symptoms")
            return jsonify({
                'error': 'Please provide symptoms'
            }), 400
        
        # Get patient history if patient_id is provided
        patient_history = None
        if patient_id:
            patient_history = get_patient_history(patient_id)
        
        # Get predictions (with history if available)
        predictions = predict_disease_ml(symptoms, patient_history)
        
        # Format response
        results = []
        top_prediction = None
        for disease, confidence in predictions:
            # Convert NumPy float32 to Python float for JSON serialization
            confidence_float = float(confidence)
            result = {
                'disease': disease,
                'confidence': round(confidence_float * 100, 2),
                'typical_symptoms': DISEASE_SYMPTOMS.get(disease, [])
            }
            results.append(result)
            if top_prediction is None:
                top_prediction = result
        
        # Update performance metrics (for real-time dashboard)
        import time
        if not hasattr(app, 'prediction_stats'):
            from collections import Counter
            app.prediction_stats = {
                'total_predictions': 0,
                'successful_predictions': 0,
                'failed_predictions': 0,
                'disease_counts': Counter(),
                'avg_confidence': 0.0,
                'response_times': [],
                'start_time': time.time()
            }
        
        if top_prediction:
            stats = app.prediction_stats
            stats['total_predictions'] += 1
            stats['successful_predictions'] += 1
            stats['disease_counts'][top_prediction['disease']] += 1
            
            # Update rolling average confidence
            current_avg = stats['avg_confidence']
            new_confidence = top_prediction['confidence'] / 100.0
            stats['avg_confidence'] = (current_avg * (stats['total_predictions'] - 1) + new_confidence) / stats['total_predictions']
        
        response = {
            'predictions': results,
            'input_symptoms': symptoms
        }
        
        # Save to database if patient_id is provided
        if patient_id and top_prediction:
            try:
                with closing(get_db()) as conn:
                    cursor = conn.cursor()
                    cursor.execute('''
                        INSERT INTO medical_history (patient_id, symptoms, predicted_disease, confidence)
                        VALUES (?, ?, ?, ?)
                    ''', (patient_id, symptoms, top_prediction['disease'], top_prediction['confidence'] / 100.0))
                    conn.commit()
            except Exception as e:
                logger.error(f"Error saving to database: {e}")
        
        # Track response time
        response_time = time.time() - start_time
        if hasattr(app, 'prediction_stats'):
            stats = app.prediction_stats
            stats['response_times'].append(response_time)
            # Keep only last 1000 response times to avoid memory issues
            if len(stats['response_times']) > 1000:
                stats['response_times'] = stats['response_times'][-1000:]
        
        return jsonify(response)
    
    except Exception as e:
        # Track failed predictions
        if hasattr(app, 'prediction_stats'):
            app.prediction_stats['total_predictions'] += 1
            app.prediction_stats['failed_predictions'] += 1
        
        logger.error(f"Prediction error: {str(e)}", exc_info=True)
        return jsonify({
            'error': str(e)
        }), 500

@app.route('/patient/register', methods=['POST'])
def register_patient():
    """Register a new patient"""
    try:
        data = request.json
        patient_id = data.get('patient_id', '').strip()
        name = data.get('name', '').strip()
        
        if not patient_id:
            return jsonify({
                'error': 'Patient ID is required'
            }), 400
        
        with closing(get_db()) as conn:
            cursor = conn.cursor()
            try:
                cursor.execute('''
                    INSERT INTO patients (patient_id, name)
                    VALUES (?, ?)
                ''', (patient_id, name))
                conn.commit()
                return jsonify({
                    'message': 'Patient registered successfully',
                    'patient_id': patient_id
                }), 201
            except sqlite3.IntegrityError:
                return jsonify({
                    'error': 'Patient ID already exists'
                }), 400
    
    except Exception as e:
        return jsonify({
            'error': str(e)
        }), 500

@app.route('/patient/<patient_id>', methods=['GET'])
def get_patient(patient_id):
    """Get patient information and history"""
    try:
        with closing(get_db()) as conn:
            cursor = conn.cursor()
            cursor.execute('SELECT * FROM patients WHERE patient_id = ?', (patient_id,))
            patient = cursor.fetchone()
            
            if not patient:
                return jsonify({
                    'error': 'Patient not found'
                }), 404
            
            history = get_patient_history(patient_id)
            
            return jsonify({
                'patient_id': patient['patient_id'],
                'name': patient['name'],
                'created_at': patient['created_at'],
                'history': history
            })
    
    except Exception as e:
        return jsonify({
            'error': str(e)
        }), 500

@app.route('/patient/<patient_id>/history', methods=['GET'])
def get_patient_history_endpoint(patient_id):
    """Get patient's medical history"""
    try:
        history = get_patient_history(patient_id)
        return jsonify({
            'patient_id': patient_id,
            'history': history
        })
    except Exception as e:
        return jsonify({
            'error': str(e)
        }), 500

@app.route('/patient/<patient_id>/history', methods=['DELETE'])
def clear_patient_history(patient_id):
    """Clear patient's medical history"""
    try:
        with closing(get_db()) as conn:
            cursor = conn.cursor()
            # Check if patient exists
            cursor.execute('SELECT * FROM patients WHERE patient_id = ?', (patient_id,))
            patient = cursor.fetchone()
            
            if not patient:
                return jsonify({
                    'error': 'Patient not found'
                }), 404
            
            # Delete all history records for this patient
            cursor.execute('DELETE FROM medical_history WHERE patient_id = ?', (patient_id,))
            deleted_count = cursor.rowcount
            conn.commit()
            
            return jsonify({
                'message': f'Successfully cleared {deleted_count} history record(s)',
                'patient_id': patient_id,
                'deleted_count': deleted_count
        })
    
    except Exception as e:
        return jsonify({
            'error': str(e)
        }), 500

@app.route('/health', methods=['GET'])
def health():
    """Health check endpoint"""
    loaded_models = get_loaded_models()
    return jsonify({
        'status': 'healthy',
        'models_loaded': len(loaded_models),
        'model_names': [m['name'] for m in loaded_models],
        'ensemble_mode': len(loaded_models) > 1
    })

@app.route('/metrics', methods=['GET'])
def metrics():
    """Prometheus-compatible metrics endpoint for monitoring"""
    import time
    from collections import Counter
    
    # Get prediction statistics (in-memory, could be moved to Redis/DB)
    if not hasattr(app, 'prediction_stats'):
        app.prediction_stats = {
            'total_predictions': 0,
            'successful_predictions': 0,
            'failed_predictions': 0,
            'disease_counts': Counter(),
            'avg_confidence': 0.0,
            'response_times': [],
            'start_time': time.time()
        }
    
    stats = app.prediction_stats
    uptime = time.time() - stats['start_time']
    
    # Calculate average response time
    avg_response_time = sum(stats['response_times'][-100:]) / len(stats['response_times']) if stats['response_times'] else 0
    
    # Prometheus format metrics
    metrics_output = f"""# HELP disease_detector_total_predictions Total number of predictions made
# TYPE disease_detector_total_predictions counter
disease_detector_total_predictions {stats['total_predictions']}

# HELP disease_detector_successful_predictions Number of successful predictions
# TYPE disease_detector_successful_predictions counter
disease_detector_successful_predictions {stats['successful_predictions']}

# HELP disease_detector_failed_predictions Number of failed predictions
# TYPE disease_detector_failed_predictions counter
disease_detector_failed_predictions {stats['failed_predictions']}

# HELP disease_detector_avg_confidence Average prediction confidence
# TYPE disease_detector_avg_confidence gauge
disease_detector_avg_confidence {stats['avg_confidence']}

# HELP disease_detector_avg_response_time Average response time in seconds
# TYPE disease_detector_avg_response_time gauge
disease_detector_avg_response_time {avg_response_time}

# HELP disease_detector_uptime_seconds Application uptime in seconds
# TYPE disease_detector_uptime_seconds gauge
disease_detector_uptime_seconds {uptime}

# HELP disease_detector_models_loaded Number of ML models loaded
# TYPE disease_detector_models_loaded gauge
disease_detector_models_loaded {len(get_loaded_models())}
"""
    
    # Add disease-specific metrics
    for disease, count in stats['disease_counts'].most_common(10):
        disease_safe = disease.lower().replace(' ', '_')
        metrics_output += f"""
# HELP disease_detector_disease_predictions Predictions per disease
# TYPE disease_detector_disease_predictions counter
disease_detector_disease_predictions{{disease="{disease_safe}"}} {count}
"""
    
    return metrics_output, 200, {'Content-Type': 'text/plain; version=0.0.4'}

@app.route('/api/performance', methods=['GET'])
def performance_dashboard():
    """Real-time performance dashboard data"""
    import time
    
    if not hasattr(app, 'prediction_stats'):
        return jsonify({'error': 'No statistics available'}), 404
    
    stats = app.prediction_stats
    uptime = time.time() - stats['start_time']
    
    # Calculate success rate
    success_rate = (stats['successful_predictions'] / stats['total_predictions'] * 100) if stats['total_predictions'] > 0 else 0
    
    # Calculate average response time
    avg_response_time = sum(stats['response_times'][-100:]) / len(stats['response_times']) if stats['response_times'] else 0
    
    # Get top predicted diseases
    top_diseases = [{'disease': disease, 'count': count} 
                   for disease, count in stats['disease_counts'].most_common(5)]
    
    return jsonify({
        'total_predictions': stats['total_predictions'],
        'successful_predictions': stats['successful_predictions'],
        'failed_predictions': stats['failed_predictions'],
        'success_rate': round(success_rate, 2),
        'average_confidence': round(stats['avg_confidence'], 2),
        'average_response_time_ms': round(avg_response_time * 1000, 2),
        'uptime_seconds': round(uptime, 2),
        'uptime_human': f"{int(uptime // 3600)}h {int((uptime % 3600) // 60)}m {int(uptime % 60)}s",
        'models_loaded': len(get_loaded_models()),
        'top_diseases': top_diseases,
        'requests_per_minute': round((stats['total_predictions'] / uptime * 60) if uptime > 0 else 0, 2)
    })

if __name__ == '__main__':
    # Setup logging first
    logger = setup_logging()
    logger.info("Initializing application...")
    
    # Initialize database
    init_db()
    logger.info("Database initialized")
    
    # Load ML models
    load_models()
    logger.info("Models loaded, starting application")
    
    # Run application
    app.run(debug=False, host='0.0.0.0', port=5001)

