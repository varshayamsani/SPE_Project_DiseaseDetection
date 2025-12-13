# Lazy Loading of ML Models - Explanation

## What is Lazy Loading?

**Lazy loading** means loading resources (like ML models) **only when they're actually needed**, rather than loading everything at startup.

### Current Behavior (Eager Loading)

```python
# In app.py, line 797
if __name__ == '__main__':
    init_db()
    load_models()  # ← Loads ALL models immediately at startup
    app.run(...)
```

**Problems:**
- Models load when the app starts (even if no one uses them)
- Slow startup time (2-5 minutes)
- High memory usage from the start
- Pods may crash with OOMKilled before they're ready
- Wastes resources if the app isn't used immediately

### Lazy Loading Behavior

```python
# Models load only when first prediction is requested
def predict_disease_ml(symptoms_text):
    ensure_models_loaded()  # ← Load models only when needed
    # ... use models ...
```

**Benefits:**
- Fast startup (app starts in seconds)
- Lower initial memory usage
- Models load on first request
- Pods become ready faster
- Better resource utilization

## Implementation

I'll show you how to modify your code to use lazy loading.



