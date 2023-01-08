rm *.snap
sudo snap remove mill
snapcraft --use-lxd
sudo snap install --dangerous mill*.snap
mill

# snapcraft login
# snapcraft upload --release=stable mill*.snap
