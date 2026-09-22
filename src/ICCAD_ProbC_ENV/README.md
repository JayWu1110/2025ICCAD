# Download and install Docker Desktop from:
```
https://www.docker.com/products/docker-desktop/
```

# Start an Ubuntu container:
```
docker run -it ubuntu:22.04
```

# Exit the container and create a named one for OpenROAD:
```
docker create -it --name openroad-env ubuntu:22.04
```

# Copy Local Project Files into Container openroad-env
```
docker cp ./openRoad_eval_script openroad-env:/workspace/
docker cp ./ASAP7 openroad-env:/workspace/
docker cp ./aes_cipher_top openroad-env:/workspace/
```
# Download openroad_2.0-17598-ga008522d8_amd64-ubuntu-22.04.deb
```
https://github.com/Precision-Innovations/OpenROAD/releases
```

# Copy openroad_2.0-17598-ga008522d8_amd64-ubuntu-22.04.deb into the container openroad-env
```
docker cp openroad_2.0-17598-ga008522d8_amd64-ubuntu-22.04.deb openroad-env:/root/
```

# Indside the container, run it
```
openroad /workspace/openRoad_eval_script/eval_def.tcl
```
# Please refer to supplements/openroad_commands.txt for supported commands. 
# You can modify eval_def.tcl to perform other experiments.


# (Optional) Enable GUI
# Install VcXsrv on Windows
```
https://sourceforge.net/projects/vcxsrv/
```

# Launch openroad GUI
```
openroad -gui
```






