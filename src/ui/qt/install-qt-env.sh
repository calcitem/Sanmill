#!/bin/bash

# Function to detect the operating system
detect_os() {
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        echo "ubuntu"
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        echo "macos"
    else
        echo "unknown"
    fi
}

# Function to install qt on MacOS
install_qt_macos() {
    brew install cmake
    brew install qt
    brew install qt6
    echo 'export PATH="/opt/homebrew/opt/qt@6/bin:$PATH"' >> ~/.zshrc
    source ~/.zshrc
}

# Function to install qt on Ubuntu
install_qt_ubuntu() {
    sudo apt-get update
    sudo apt-get install -y qt6-base-dev qt6-multimedia-dev qtcreator cmake
}

# Main function to install qt
install_qt() {
    os=$(detect_os)
    if [[ "$os" == "macos" ]]; then
        install_qt_macos
    elif [[ "$os" == "ubuntu" ]]; then
        install_qt_ubuntu
    else
        echo "Unsupported operating system. This script supports MacOS and Ubuntu only."
        exit 1
    fi
}

# Run the main function
install_qt
