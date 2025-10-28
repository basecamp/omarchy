# Optional: Install all biology packages
# Run this separately if you want biology/bioinformatics support
# Usage: run_logged $OMARCHY_INSTALL/packaging/bio-all.sh

run_logged $OMARCHY_INSTALL/packaging/bio.sh
run_logged $OMARCHY_INSTALL/packaging/python-bio.sh
run_logged $OMARCHY_INSTALL/packaging/r-bio.sh
