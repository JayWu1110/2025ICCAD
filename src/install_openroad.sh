apt update
apt install vim -y
apt install git -y
git submodule update --init --recursive
bash ./third-party/OpenROAD/etc/DependencyInstaller.sh -base
bash ./third-party/OpenROAD/etc/DependencyInstaller.sh -common
./third-party/OpenROAD/etc/Build.sh -build-man
apt install libboost1.71-dev libboost-iostreams1.71-dev libboost-serialization1.71-dev -y
cd /workspace/third-party/OpenROAD/build && make install -j20
