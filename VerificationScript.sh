#!/bin/bash

# MCRL2 Model Processing Script - Batch Processing for .mcf files
# This script processes an MCRL2 model through multiple transformation steps for each .mcf file in the directory

# Array to store results
declare -a results

echo "Starting MCRL2 batch model processing..."
echo "========================================"

# Check if model.lps exists
if [ ! -f "model.lps" ]; then
    echo "Error: model.lps not found in current directory"
    exit 1
fi

# Find all .mcf files in the current directory
mcf_files=$(find . -maxdepth 1 -name "*.mcf" -type f)

if [ -z "$mcf_files" ]; then
    echo "No .mcf files found in the current directory"
    exit 1
fi

echo "Found .mcf files:"
for file in $mcf_files; do
    echo "  - $(basename "$file")"
done
echo ""

# Process each .mcf file
for mcf_file in $mcf_files; do
    formula_name=$(basename "$mcf_file" .mcf)
    
    echo "-----------------------------------------------------------------------"
    echo "Checked formula $formula_name.mcf"
    echo "-----------------------------------------------------------------------"
    
    # Step 1: Transform the initial model
    echo "Step 1: Transforming model.lps..."
    /home/jfg/MCRL2/bin/lpsfununfold model.lps -v | \
    /home/jfg/MCRL2/bin/lpssuminst | \
    /home/jfg/MCRL2/bin/lpsparunfold -s"LockSideStreamSideTriple" | \
    /home/jfg/MCRL2/bin/lpsparunfold -s"LockSideTuple" | \
    /home/jfg/MCRL2/bin/lpsparunfold -s"ConfigLockTuple" | \
    /home/jfg/MCRL2/bin/lpsrewr -v > "model2_${formula_name}.lps"

    if [ $? -eq 0 ]; then
        echo "✓ Step 1 completed successfully"
    else
        echo "✗ Step 1 failed for $formula_name.mcf"
        results+=("$formula_name.mcf: FAILED (Step 1)")
        continue
    fi

    # Step 2: Generate PBES from the transformed model
    echo "Step 2: Generating PBES from model2_${formula_name}.lps..."
    /home/jfg/MCRL2/bin/lps2pbes "model2_${formula_name}.lps" -f"$mcf_file" -v "model2_${formula_name}.pbes"

    if [ $? -eq 0 ]; then
        echo "✓ Step 2 completed successfully"
    else
        echo "✗ Step 2 failed for $formula_name.mcf"
        results+=("$formula_name.mcf: FAILED (Step 2)")
        continue
    fi

    # Step 3: Apply PBES transformations
    echo "Step 3: Applying PBES transformations..."
    /home/jfg/MCRL2/bin/pbesrewr -pquantifier-inside "model2_${formula_name}.pbes" -v | \
    /home/jfg/MCRL2/bin/pbesrewr -pquantifier-one-point -v | \
    /home/jfg/MCRL2/bin/pbesrewr | \
    /home/jfg/MCRL2/bin/pbesrewr -pquantifier-all -v | \
    /home/jfg/MCRL2/bin/pbesrewr | \
    /home/jfg/MCRL2/bin/pbesstategraph -v | \
    /home/jfg/MCRL2/bin/pbesconstelm -cv | \
    /home/jfg/MCRL2/bin/pbesrewr | \
    /home/jfg/MCRL2/bin/pbesparelm -v | \
    /home/jfg/MCRL2/bin/pbesconstelm -cve | \
    /home/jfg/MCRL2/bin/pbesrewr > "model2_2_${formula_name}.pbes"

    if [ $? -eq 0 ]; then
        echo "✓ Step 3 completed successfully"
    else
        echo "✗ Step 3 failed for $formula_name.mcf"
        results+=("$formula_name.mcf: FAILED (Step 3)")
        continue
    fi

    # Step 4: Solve the PBES symbolically
    echo "Step 4: Solving PBES symbolically..."
    solve_output=$(/home/jfg/MCRL2/bin/pbessolvesymbolic --memory-limit=64 "model2_2_${formula_name}.pbes" -v --split-conditions --cached -rjittyc --groups=used --chaining --saturation)
    solve_exit_code=$?
    
    # Extract the final result (true/false) from the output
    solve_result=$(echo "$solve_output" | tail -1 | grep -oE "(true|false)")
    
    if [ $solve_exit_code -eq 0 ]; then
        echo "✓ Step 4 completed successfully for $formula_name.mcf"
        if [ -n "$solve_result" ]; then
            results+=("$formula_name.mcf: $solve_result")
        else
            results+=("$formula_name.mcf: completed (result unclear)")
        fi
    else
        echo "✗ Step 4 failed for $formula_name.mcf"
        results+=("$formula_name.mcf: FAILED")
    fi
    
    echo ""
done

echo "========================================"
echo "Batch processing completed!"
echo ""
echo "SUMMARY OF RESULTS:"
echo "==================="
for result in "${results[@]}"; do
    echo "$result"
done