# PGS Browser

The script computes raw, predicted, and ancestry-adjusted PGS with corresponding percentiles and standard deviations for each sample using a chosen PGS model from browser.<br>

For more details, see "Documentation" page: https://pgs.nchigm.org/

Note: this repository stores Docker wrapper script that allows to run `pgsb-cli` script inside of the container.

#### **Input**
  - `--vcf` or `--bfile` - individual-level genetic data in .vcf or plink format
  - `--pgs_model` - PGS model downloaded from PGS Browser
  - `--outdir` - output directory for all of the produced files
  - `--min_overlap` (optional) - minimal variant overlap between model and genotypes (default: 0.7)
    
#### **Execution**
    
1. Be sure that you have intalled `docker` on your machine and it is up and running:
  * `command -v docker` - ensures the docker binary is available
  * `docker info` - queries the daemon. If Docker is not running, this step will fail.
    
2. Launch the CLI
    
Example:
```bash
./pgsb-docker-cli.sh \
  --vcf 1000G.6FINNS.vcf.gz \
  --pgs_model PGS000001.tsv.gz \
  --min_overlap 0.95 \
  --outdir outputs/
```
    
#### **Main output**
    
 - **`RESULT_PGS_SCORES.tsv`**<br>
        Columns: <br>
        - *#IID* - Individual sample identifiers extracted from the `.vcf` or PLINK files.<br>
        - *PGSNNNNNN_raw* - Raw PGS values calculated from the matched PGS model.<br>
        - *PGSNNNNNN_pred* - Predicted PGS values, estimated from the first 5 principal components (PC1–PC5) to account for genetic ancestry.<br>
        - *PGSNNNNNN_adj* - Raw PGS values adjusted for ancestry (input for *Cohort Operations*).<br>
        - *Sd* - Standardized version of the adjusted PGS.<br>
        - *Percentile* - Percentiles corresponding to the distribution of the adjusted PGS (input for *Prediction*).<br>
 - `model_ALL_additive_0.scorefile.gz` - matched PGS model<br>
 - `projected_pcs.tsv` - PC coordinates in PC1-6 for the provided samples<br>
 - `predicted_ancestry.tsv` - Predicted continental population (see 1000G) and corresponding probability.<br>

For more details, see the video tutorial at `pgs.nchigm.org`.

### **License**

CC BY-NC-ND 4.0

© Nikita Kolosov, Mykyta Artomov  
The software is provided “as is,” without any warranty, and the copyright holders are not liable for any claims, damages, or other liabilities arising from the use or distribution of the software.
The usage of PGS browser and associated tools (`pgsb-cli`) is free for academic (non-commercial) and personal use.  
For the commercial licensing please reach out to Tech.Commercialization@NationwideChildrens.org   
