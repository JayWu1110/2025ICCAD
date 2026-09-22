docker run --gpus '"device=0,1"' -it \
-e DISPLAY=$DISPLAY \
-e QT_X11_NO_MITSHM=1 \
-v /tmp/.X11-unix:/tmp/.X11-unix:rw \
-v $HOME/.Xauthority:/root/.Xauthority:rw \
-v ./..:/workspace \
--network=host \
-w /workspace \
iccad25_probc_env:latest bash
