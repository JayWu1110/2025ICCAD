# 2025 ICCAD Contest Problem C: Incremental Placement Optimization Beyond Detailed Placement: Simultaneous Gate Sizing, Buffering, and Cell Relocation

## 1. Problem Formulation
This project addresses the 2025 ICCAD Contest Problem C: Incremental Placement Optimization Beyond Detailed Placement: Simultaneous Gate Sizing, Buffering, and Cell Relocation. Unlike traditional sequential flows, where gate sizing, buffering, and cell relocation are applied one at a time, this contest challenges us to simultaneously perform all three optimizations to achieve globally better power, performance, and area.

## 2. Goal
The goal is to repair timing violations (e.g., negative slack), reduce power and half-perimeter wirelength (HPWL), and maintain legal placement.

## 3. Directory
```text
.
├── slides/
│   └── EDA_Fianl_Presentation.pdf
├── report/
│   └── EDA_Fianl_Report.pdf
├── src/
│   ├── aes_cipher_top/
│   ├── ASAP7/
│   ├── ICCAD_ProbC_ENV/
│   └── openRoad_eval_script/
└── supplements/
    ├── ICCAD_C_Exp_result.xlsx
    └── openroad_commands.txt
```

## 4. How to compile and run

Download and install Docker Desktop from:
<https://www.docker.com/products/docker-desktop/>

Start an Ubuntu container:
```bash
docker run -it ubuntu:22.04
```

Exit the container and create a named one for OpenROAD:
```bash
docker create -it --name openroad-env ubuntu:22.04
```

Copy Local Project Files into Container openroad-env
```bash
docker cp ./openRoad_eval_script openroad-env:/workspace/
docker cp ./ASAP7 openroad-env:/workspace/
docker cp ./aes_cipher_top openroad-env:/workspace/
```
Download openroad_2.0-17598-ga008522d8_amd64-ubuntu-22.04.deb
<https://github.com/Precision-Innovations/OpenROAD/releases>

Copy openroad_2.0-17598-ga008522d8_amd64-ubuntu-22.04.deb into the container openroad-env
```bash
docker cp openroad_2.0-17598-ga008522d8_amd64-ubuntu-22.04.deb openroad-env:/root/
```

Inside the container, run it
```bash
openroad /workspace/openRoad_eval_script/eval_def.tcl
```
Please refer to supplements/openroad_commands.txt for supported commands. 
You can modify eval_def.tcl to perform other experiments.


(Optional) Enable GUI
Install VcXsrv on Windows
<https://sourceforge.net/projects/vcxsrv/>

Launch openroad GUI
```bash
openroad -gui
```