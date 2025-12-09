const predictBtn = document.getElementById('predictBtn');
const symptomsInput = document.getElementById('symptoms');
const resultsSection = document.getElementById('results');
const predictionsContainer = document.getElementById('predictionsContainer');
const errorDiv = document.getElementById('error');
const btnText = document.getElementById('btnText');
const btnLoader = document.getElementById('btnLoader');

// Patient management elements
const patientIdInput = document.getElementById('patientId');
const patientNameInput = document.getElementById('patientName');
const registerBtn = document.getElementById('registerBtn');
const loadHistoryBtn = document.getElementById('loadHistoryBtn');
const patientInfo = document.getElementById('patientInfo');
const patientNameDisplay = document.getElementById('patientNameDisplay');
const historySection = document.getElementById('historySection');
const historyContainer = document.getElementById('historyContainer');
const clearHistoryBtn = document.getElementById('clearHistoryBtn');

let currentPatientId = null;
let currentPatientName = null;

// Check if patient ID exists when input changes
patientIdInput.addEventListener('input', () => {
    const patientId = patientIdInput.value.trim();
    if (patientId) {
        // Show name input and register button
        patientNameInput.style.display = 'block';
        registerBtn.style.display = 'inline-block';
    } else {
        patientNameInput.style.display = 'none';
        registerBtn.style.display = 'none';
        currentPatientId = null;
        currentPatientName = null;
        patientInfo.style.display = 'none';
        historySection.style.display = 'none';
    }
});

// Register new patient
registerBtn.addEventListener('click', async () => {
    const patientId = patientIdInput.value.trim();
    const name = patientNameInput.value.trim();
    
    if (!patientId) {
        showError('Please enter a Patient ID');
        return;
    }
    
    try {
        const response = await fetch('/patient/register', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
            },
            body: JSON.stringify({
                patient_id: patientId,
                name: name || patientId
            })
        });
        
        const data = await response.json();
        
        if (!response.ok) {
            throw new Error(data.error || 'Failed to register patient');
        }
        
        currentPatientId = patientId;
        currentPatientName = name || patientId;
        patientNameDisplay.textContent = `${currentPatientName} (${currentPatientId})`;
        patientInfo.style.display = 'block';
        showSuccess('Patient registered successfully!');
        
        // Auto-load history
        loadPatientHistory();
        
    } catch (error) {
        showError(error.message);
    }
});

// Load patient history
loadHistoryBtn.addEventListener('click', () => {
    loadPatientHistory();
});

async function loadPatientHistory() {
    const patientId = patientIdInput.value.trim();
    
    if (!patientId) {
        showError('Please enter a Patient ID first');
        return;
    }
    
    try {
        const response = await fetch(`/patient/${patientId}`);
        const data = await response.json();
        
        if (!response.ok) {
            if (response.status === 404) {
                showError('Patient not found. Please register first.');
                return;
            }
            throw new Error(data.error || 'Failed to load patient history');
        }
        
        currentPatientId = patientId;
        currentPatientName = data.name || patientId;
        patientNameDisplay.textContent = `${currentPatientName} (${currentPatientId})`;
        patientInfo.style.display = 'block';
        
        // Display history
        displayHistory(data.history || []);
        
    } catch (error) {
        showError(error.message);
    }
}

function displayHistory(history) {
    historyContainer.innerHTML = '';
    
    if (history.length === 0) {
        historyContainer.innerHTML = '<div class="no-history">No medical history available for this patient.</div>';
        historySection.style.display = 'block';
        clearHistoryBtn.style.display = 'none'; // Hide clear button if no history
        return;
    }
    
    // Show clear button when history exists
    clearHistoryBtn.style.display = 'inline-block';
    
    history.forEach(record => {
        const historyItem = document.createElement('div');
        historyItem.className = 'history-item';
        
        const date = new Date(record.created_at).toLocaleString();
        
        historyItem.innerHTML = `
            <h4>${record.predicted_disease || 'No prediction'}</h4>
            <p><strong>Symptoms:</strong> ${record.symptoms}</p>
            ${record.confidence ? `<p><strong>Confidence:</strong> ${(record.confidence * 100).toFixed(2)}%</p>` : ''}
            <p class="history-date">${date}</p>
        `;
        
        historyContainer.appendChild(historyItem);
    });
    
    historySection.style.display = 'block';
}

// Clear history button handler
clearHistoryBtn.addEventListener('click', async () => {
    if (!currentPatientId) {
        showError('No patient selected');
        return;
    }
    
    // Confirmation dialog
    const confirmed = confirm(
        `Are you sure you want to clear all medical history for patient ${currentPatientId}?\n\n` +
        `This action cannot be undone.`
    );
    
    if (!confirmed) {
        return;
    }
    
    try {
        const response = await fetch(`/patient/${currentPatientId}/history`, {
            method: 'DELETE',
            headers: {
                'Content-Type': 'application/json',
            }
        });
        
        const data = await response.json();
        
        if (!response.ok) {
            throw new Error(data.error || 'Failed to clear history');
        }
        
        showSuccess(`Successfully cleared ${data.deleted_count} history record(s)`);
        
        // Reload history (will be empty now)
        await loadPatientHistory();
        
    } catch (error) {
        showError(error.message || 'Failed to clear history');
    }
});

predictBtn.addEventListener('click', async () => {
    const symptoms = symptomsInput.value.trim();
    
    if (!symptoms) {
        showError('Please enter your symptoms');
        return;
    }
    
    // Hide previous results and errors
    resultsSection.style.display = 'none';
    errorDiv.style.display = 'none';
    
    // Show loading state
    predictBtn.disabled = true;
    btnText.textContent = 'Analyzing...';
    btnLoader.style.display = 'inline-block';
    
    try {
        const requestBody = { symptoms: symptoms };
        
        // Include patient ID if available
        if (currentPatientId) {
            requestBody.patient_id = currentPatientId;
        }
        
        const response = await fetch('/predict', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
            },
            body: JSON.stringify(requestBody)
        });
        
        const data = await response.json();
        
        if (!response.ok) {
            throw new Error(data.error || 'An error occurred');
        }
        
        displayResults(data);
        
        // Reload history if patient ID is set
        if (currentPatientId) {
            loadPatientHistory();
        }
        
    } catch (error) {
        showError(error.message || 'Failed to get prediction. Please try again.');
    } finally {
        // Reset button state
        predictBtn.disabled = false;
        btnText.textContent = 'Detect Disease';
        btnLoader.style.display = 'none';
    }
});

function displayResults(data) {
    predictionsContainer.innerHTML = '';
    
    if (!data.predictions || data.predictions.length === 0) {
        showError('No predictions available. Please try describing your symptoms in more detail.');
        return;
    }
    
    // Show message if using patient history or ensemble
    const infoNotes = [];
    if (currentPatientId) {
        infoNotes.push('📋 Predictions enhanced with patient medical history');
    }
    infoNotes.push('🤖 Using ensemble of multiple medical AI models for improved accuracy');
    
    if (infoNotes.length > 0) {
        const infoNote = document.createElement('div');
        infoNote.style.cssText = 'background: #e3f2fd; padding: 12px; border-radius: 8px; margin-bottom: 15px; color: #1976d2; line-height: 1.6;';
        infoNote.innerHTML = '<strong>ℹ️ Enhanced Prediction:</strong><br>' + infoNotes.join('<br>');
        predictionsContainer.appendChild(infoNote);
    }
    
    data.predictions.forEach((prediction, index) => {
        const card = createPredictionCard(prediction, index === 0);
        predictionsContainer.appendChild(card);
    });
    
    resultsSection.style.display = 'block';
}

function createPredictionCard(prediction, isTop) {
    const card = document.createElement('div');
    card.className = 'prediction-card';
    
    if (isTop) {
        card.style.borderLeftColor = '#4caf50';
        card.style.background = '#f1f8f4';
    }
    
    const diseaseName = document.createElement('h3');
    diseaseName.textContent = prediction.disease;
    if (isTop) {
        diseaseName.innerHTML = `🥇 ${prediction.disease} <span style="font-size: 0.7em; color: #4caf50;">(Most Likely)</span>`;
    }
    
    const confidenceBar = document.createElement('div');
    confidenceBar.className = 'confidence-bar';
    
    const confidenceFill = document.createElement('div');
    confidenceFill.className = 'confidence-fill';
    confidenceFill.style.width = `${Math.min(prediction.confidence, 100)}%`;
    confidenceFill.textContent = `${prediction.confidence}%`;
    
    confidenceBar.appendChild(confidenceFill);
    
    const confidenceText = document.createElement('div');
    confidenceText.className = 'confidence-text';
    confidenceText.textContent = `Confidence: ${prediction.confidence}%`;
    
    const symptomsList = document.createElement('div');
    symptomsList.className = 'symptoms-list';
    
    const symptomsTitle = document.createElement('h4');
    symptomsTitle.textContent = 'Typical Symptoms:';
    
    const symptomsUl = document.createElement('ul');
    prediction.typical_symptoms.forEach(symptom => {
        const li = document.createElement('li');
        li.textContent = symptom;
        symptomsUl.appendChild(li);
    });
    
    symptomsList.appendChild(symptomsTitle);
    symptomsList.appendChild(symptomsUl);
    
    card.appendChild(diseaseName);
    card.appendChild(confidenceBar);
    card.appendChild(confidenceText);
    card.appendChild(symptomsList);
    
    return card;
}

function showError(message) {
    errorDiv.textContent = message;
    errorDiv.style.display = 'block';
    errorDiv.style.background = '#fee';
    errorDiv.style.color = '#c33';
}

function showSuccess(message) {
    errorDiv.textContent = message;
    errorDiv.style.display = 'block';
    errorDiv.style.background = '#efe';
    errorDiv.style.color = '#3c3';
    setTimeout(() => {
        errorDiv.style.display = 'none';
    }, 3000);
}

// Allow Enter key to submit (Ctrl+Enter or Cmd+Enter)
symptomsInput.addEventListener('keydown', (e) => {
    if ((e.ctrlKey || e.metaKey) && e.key === 'Enter') {
        predictBtn.click();
    }
});
