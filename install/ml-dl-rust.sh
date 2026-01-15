#!/usr/bin/env bash
#
# ML/DL/Rust Installation Script for Omarchy
# Add this file to your Omarchy fork at: install/ml-dl-rust.sh
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "================================================"
echo "Installing ML/DL/Rust Development Environment"
echo "================================================"

# Install Rust toolchain
echo ""
echo "→ Installing Rust and Cargo..."
sudo pacman -S --needed --noconfirm rust cargo rustup

# Set up Rust stable as default
echo "→ Setting up Rust stable toolchain..."
rustup default stable

# Install Python ML/DL packages from Arch repos
echo ""
echo "→ Installing Python ML/DL packages from Arch repositories..."
sudo pacman -S --needed --noconfirm \
    python-pytorch \
    python-scikit-learn \
    python-pandas \
    python-numpy \
    python-scipy \
    python-matplotlib \
    python-seaborn \
    python-pillow \
    python-pip \
    python-virtualenv \
    python-pipenv

# Install Jupyter
echo "→ Installing Jupyter Notebook environment..."
sudo pacman -S --needed --noconfirm jupyter-notebook

# Optional: CUDA support (uncomment if needed)
# Uncomment the following lines if you have NVIDIA GPU and want GPU acceleration
# echo ""
# echo "→ Installing CUDA and cuDNN for GPU support..."
# sudo pacman -S --needed --noconfirm cuda cudnn
# echo "Note: CUDA installed. You may need to install pytorch-cuda instead of pytorch"

# Install additional Python ML/DL packages via pip
echo ""
echo "→ Installing additional Python ML/DL packages via pip..."
echo "   This may take several minutes..."

pip install --break-system-packages \
    tensorflow \
    keras \
    transformers \
    datasets \
    tokenizers \
    accelerate \
    sentence-transformers \
    xgboost \
    lightgbm \
    catboost \
    optuna \
    hyperopt \
    wandb \
    mlflow \
    tensorboard \
    plotly \
    ipywidgets \
    tqdm \
    opencv-python

# Install Rust ML/DL development tools
echo ""
echo "→ Installing Rust ML development tools..."
cargo install cargo-edit

# Create default ML workspace directory
echo ""
echo "→ Setting up ML workspace directory..."
mkdir -p "$HOME/ml-workspace"
mkdir -p "$HOME/ml-workspace/notebooks"
mkdir -p "$HOME/ml-workspace/projects"
mkdir -p "$HOME/ml-workspace/datasets"

# Create a sample Jupyter config
echo "→ Generating Jupyter configuration..."
jupyter notebook --generate-config 2>/dev/null || true

# Create a helpful README in ML workspace
cat > "$HOME/ml-workspace/README.md" <<'EOF'
# ML Workspace

This directory is set up for your machine learning and deep learning projects.

## Structure

- `notebooks/` - Jupyter notebooks
- `projects/` - ML/DL project directories  
- `datasets/` - Store your datasets here

## Quick Start

### Python Virtual Environment (Recommended)

```bash
# Create a virtual environment for a project
cd ~/ml-workspace/projects
python -m venv myproject-env
source myproject-env/bin/activate

# Install packages in the isolated environment
pip install torch torchvision transformers
```

### Jupyter Notebooks

```bash
# Start Jupyter in the notebooks directory
cd ~/ml-workspace/notebooks
jupyter notebook
```

### Rust ML Projects

```bash
# Create a new Rust project
cd ~/ml-workspace/projects
cargo new rust-ml-project
cd rust-ml-project

# Add ML crates
cargo add ndarray
cargo add linfa
cargo add tch  # PyTorch bindings
```

## Installed Libraries

### Python
- PyTorch - Deep learning framework
- TensorFlow/Keras - Deep learning framework
- Scikit-learn - Machine learning algorithms
- Transformers - Hugging Face transformers
- XGBoost, LightGBM, CatBoost - Gradient boosting
- Pandas, NumPy, SciPy - Data manipulation
- Matplotlib, Seaborn, Plotly - Visualization
- Jupyter - Interactive notebooks
- MLflow, Weights & Biases - Experiment tracking

### Rust
- Rust stable toolchain
- Cargo package manager

## Useful Rust ML Crates

Add these to your Cargo.toml as needed:

```toml
[dependencies]
ndarray = "0.15"        # N-dimensional arrays
linfa = "0.7"           # ML algorithms
tch = "0.13"            # PyTorch bindings
burn = "0.13"           # Deep learning framework
smartcore = "0.3"       # ML library
onnxruntime = "0.0.14"  # ONNX inference
```

## GPU Support

If you enabled CUDA during installation:
- Verify installation: `nvidia-smi`
- Use pytorch-cuda instead of pytorch for GPU acceleration
- TensorFlow should auto-detect GPU

## Resources

- PyTorch docs: https://pytorch.org/docs/
- TensorFlow docs: https://www.tensorflow.org/
- Hugging Face: https://huggingface.co/
- Scikit-learn docs: https://scikit-learn.org/
- Rust ML: https://www.arewelearningyet.com/
EOF

# Create a sample Rust ML project template
cat > "$HOME/ml-workspace/rust-ml-template.md" <<'EOF'
# Rust ML Project Template

## Create a new Rust ML project:

```bash
cargo new my-ml-project
cd my-ml-project
```

## Add dependencies to Cargo.toml:

```toml
[dependencies]
ndarray = "0.15"
ndarray-rand = "0.14"
linfa = "0.7"
linfa-linear = "0.7"
csv = "1.2"
serde = { version = "1.0", features = ["derive"] }
```

## Example: Linear Regression

```rust
use linfa::prelude::*;
use linfa_linear::LinearRegression;
use ndarray::Array2;

fn main() {
    // Create sample data
    let x = Array2::from_shape_vec((5, 1), vec![1., 2., 3., 4., 5.]).unwrap();
    let y = Array2::from_shape_vec((5, 1), vec![2., 4., 6., 8., 10.]).unwrap();
    
    // Train model
    let dataset = Dataset::new(x.clone(), y);
    let model = LinearRegression::default().fit(&dataset).unwrap();
    
    // Make predictions
    let predictions = model.predict(&x);
    println!("Predictions: {:?}", predictions);
}
```
EOF

echo ""
echo "================================================"
echo "✓ ML/DL/Rust environment setup complete!"
echo "================================================"
echo ""
echo "Installed components:"
echo "  ✓ Rust (stable) + Cargo"
echo "  ✓ PyTorch"
echo "  ✓ TensorFlow/Keras"
echo "  ✓ Scikit-learn"
echo "  ✓ Transformers (Hugging Face)"
echo "  ✓ Jupyter Notebooks"
echo "  ✓ XGBoost, LightGBM, CatBoost"
echo "  ✓ MLflow, Weights & Biases"
echo "  ✓ Data science stack (Pandas, NumPy, etc.)"
echo ""
echo "ML workspace created at: ~/ml-workspace"
echo "See ~/ml-workspace/README.md for usage instructions"
echo ""
echo "Quick start:"
echo "  - Jupyter: cd ~/ml-workspace/notebooks && jupyter notebook"
echo "  - Python venv: python -m venv ~/ml-workspace/projects/myenv"
echo "  - Rust project: cd ~/ml-workspace/projects && cargo new myproject"
echo ""
